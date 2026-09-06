/*
   NSMenu+Eau.m

   Swizzles NSMenu and related classes to enable NSMacintoshInterfaceStyle
   support with upstream (unmodified) libs-gui.

   This allows the Eau theme to:
   1. Receive notifications when the main menu changes
   2. Control menu visibility (hide in-app menu bar for global menu)
   3. Enforce the invariant that before a new menu panel is shown, every
      panel left open by an earlier interaction is closed (the exception
      is a submenu, whose parent chain stays put).  Upstream only tears
      the first-level dropdown down for NSWindows95InterfaceStyle, so
      under the Macintosh style orphaned panels used to stay mapped and
      wedge the menu bar.
   4. Implement overflowing menu scrolling (Leopard-style) when a menu
      has more items than fit on screen
*/

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import <string.h>
#import <X11/Xlib.h>
#import <X11/Xutil.h>

#import "Eau.h"
#import "EauMenuScrollManager.h"

/* ---- NSMenuPanel forward declaration (private) ---- */
@interface NSObject (EauMenuPanel)
- (id)_menu;
@end

/* Forward declaration of private NSMenuView methods used for
   coordinate calculations. These exist in GNUstep's NSMenuView.m. */
@interface NSMenuView (EauScrollHelper)
- (CGFloat) yOriginForItem: (NSInteger)item;
- (CGFloat) heightForItem: (NSInteger)item;
- (CGFloat) totalHeight;
@end

/* ---- Helper: find NSMenuView in an NSMenuPanel's content view hierarchy ---- */
static NSView *_eau_findMenuViewInView(NSView *view)
{
  if (view == nil) return nil;
  if ([view isKindOfClass: objc_getClass("NSMenuView")])
    {
      return view;
    }
  for (NSView *subview in [view subviews])
    {
      NSView *found = _eau_findMenuViewInView(subview);
      if (found) return found;
    }
  return nil;
}

static NSMenuView *_eau_findMenuViewInWindow(NSWindow *window)
{
  if (!window) return nil;
  NSView *contentView = [window contentView];
  if (!contentView) return nil;

  // NSMenuView is typically a direct subview of the content view, but some
  // apps (e.g. Menu.app's Command menu) wrap it in an intermediate NSView.
  // Recurse so the scroll manager is found regardless of nesting depth.
  return (NSMenuView *)_eau_findMenuViewInView(contentView);
}

/* ---- Overflow handling for tall menus ---- */

/**
 * Detect if the menu contained in `window` overflows the available screen
 * space and, if so, configure the scroll manager and resize the window.
 *
 * Returns YES if overflow mode was entered (window was resized).
 */
static BOOL _eau_handleMenuOverflow(NSWindow *window, NSRect *frame)
{
  NSMenuView *menuView = _eau_findMenuViewInWindow(window);
  if (!menuView) return NO;

  // Delegate the full overflow-detection / setup logic to the shared
  // class method on EauMenuScrollManager.  This method is still needed
  // because the caller (clamp helper) uses a modified frame pointer to
  // apply the window resize via the original IMP, avoiding re-entry.
  BOOL result = [EauMenuScrollManager setupOverflowForMenuView: menuView];
  if (result)
    {
      // The class method already resized the window and view.  Read the
      // new window frame so the caller can apply it via the original IMP
      // (the class method uses a swizzled setFrame: which would recurse
      // if we didn't go through the original IMP here).
      NSRect newFrame = [window frame];
      frame->size.height = newFrame.size.height;
      frame->origin.y = newFrame.origin.y;
    }
  return result;
}

/* ---- NSMenuPanel swizzles: clamp menu windows to screen bounds ---- */

// Shared bottom-clamp helper: if the window extends past the screen
// borders, shift it to fit entirely on screen.
// Also detects overflow and resizes the window if the menu is too tall.
// Uses the original setFrame:display: IMP to avoid recursion.
static void (*s_orig_menuWindowSetFrameDisplay)(id, SEL, NSRect, BOOL) = NULL;

static BOOL _eau_clampMenuWindowToScreenBounds(id window)
{
  NSRect frame = [window frame];
  NSScreen *screen = [window screen];
  if (!screen) screen = [NSScreen mainScreen];
  if (!screen) return NO;

  NSRect screenFrame = [screen frame];
  BOOL needsClamp = NO;

  // Bottom edge — shift up
  if (frame.origin.y < screenFrame.origin.y)
    {
      frame.origin.y = screenFrame.origin.y;
      needsClamp = YES;
    }

  // Top edge — shift down
  if (NSMaxY(frame) > NSMaxY(screenFrame))
    {
      frame.origin.y = NSMaxY(screenFrame) - frame.size.height;
      needsClamp = YES;
    }

  // Left edge — shift right
  if (frame.origin.x < screenFrame.origin.x)
    {
      frame.origin.x = screenFrame.origin.x;
      needsClamp = YES;
    }

  // Right edge — shift left
  if (NSMaxX(frame) > NSMaxX(screenFrame))
    {
      frame.origin.x = NSMaxX(screenFrame) - frame.size.width;
      needsClamp = YES;
    }

  if (needsClamp)
    {
      // Use the original IMP directly to avoid re-entering the swizzle.
      if (s_orig_menuWindowSetFrameDisplay)
        s_orig_menuWindowSetFrameDisplay(window, @selector(setFrame:display:), frame, NO);
    }

  // Now handle overflow: if the menu is too tall for the screen,
  // resize it and activate scrolling.
  if (_eau_handleMenuOverflow(window, &frame))
    {
      // Apply the overflow-resized frame
      if (s_orig_menuWindowSetFrameDisplay)
        s_orig_menuWindowSetFrameDisplay(window, @selector(setFrame:display:), frame, NO);
      return YES;
    }

  return needsClamp;
}

static void (*s_orig_menuWindowSetFrameOrigin)(id, SEL, NSPoint) = NULL;

static void s_eau_menuWindowSetFrameOrigin(id self, SEL _cmd, NSPoint aPoint)
{
  if (s_orig_menuWindowSetFrameOrigin)
    s_orig_menuWindowSetFrameOrigin(self, _cmd, aPoint);
  _eau_clampMenuWindowToScreenBounds(self);
}

static void s_eau_menuWindowSetFrameDisplay(id self, SEL _cmd, NSRect frameRect, BOOL flag)
{
  if (s_orig_menuWindowSetFrameDisplay)
    s_orig_menuWindowSetFrameDisplay(self, _cmd, frameRect, flag);
  _eau_clampMenuWindowToScreenBounds(self);
}

static void _eau_swizzleMenuWindowFrameMethods(void)
{
  Class menuPanelClass = objc_getClass("NSMenuPanel");
  if (!menuPanelClass)
    {
      NSDebugLog(@"Eau: NSMenuPanel class not found, skipping menu window swizzles");
      return;
    }

  // Swizzle setFrameOrigin:
  SEL selOrigin = sel_registerName("setFrameOrigin:");
  Method mOrigin = class_getInstanceMethod(menuPanelClass, selOrigin);
  if (mOrigin)
    {
      s_orig_menuWindowSetFrameOrigin = (void (*)(id, SEL, NSPoint))method_getImplementation(mOrigin);
      method_setImplementation(mOrigin, (IMP)s_eau_menuWindowSetFrameOrigin);
      NSDebugLog(@"Eau: Swizzled NSMenuPanel setFrameOrigin: for bottom-screen clamping");
    }

  // Swizzle setFrame:display: (catches sizeToFit calls that bypass setFrameOrigin:)
  SEL selFrameDisplay = sel_registerName("setFrame:display:");
  Method mFrameDisplay = class_getInstanceMethod(menuPanelClass, selFrameDisplay);
  if (mFrameDisplay)
    {
      s_orig_menuWindowSetFrameDisplay = (void (*)(id, SEL, NSRect, BOOL))method_getImplementation(mFrameDisplay);
      method_setImplementation(mFrameDisplay, (IMP)s_eau_menuWindowSetFrameDisplay);
      NSDebugLog(@"Eau: Swizzled NSMenuPanel setFrame:display: for bottom-screen clamping");
    }
}

/* ---- Tracked windows + active tracking counter ---- */
static volatile int _eau_activeTrackingCount = 0;
static __weak NSMenuView *_eau_trackedMenuView = nil;
static BOOL _eau_keyboardNavActive = NO;
static Display *_eau_x11_display = NULL;

// Accessors for other compilation units (NSMenuView+Eau.m)
NSMenuView *EauGetTrackedMenuView(void) { return _eau_trackedMenuView; }
BOOL EauGetKeyboardNavActive(void) { return _eau_keyboardNavActive; }
void EauSetKeyboardNavActive(BOOL active) { _eau_keyboardNavActive = active; }

static void _eau_ensureState(void)
{
  if (_eau_x11_display == NULL)
    _eau_x11_display = XOpenDisplay(NULL);
}

/* ---- Destroy ALL X11 "Menu" windows + their containers ---- */
static void _eau_destroyX11MenuWindows(void)
{
  _eau_ensureState();
  if (_eau_x11_display == NULL) return;

  /* Walk the X11 tree looking for GNUstep "Menu" windows in Normal
     state.  These are orphaned dropdowns.  We destroy BOTH the
     window AND its parent container, because the NSWindow's X11
     window is often a child of an unmanaged container (0x40f7ce
     style) that stays visible even after the child is destroyed. */
  Window root = DefaultRootWindow(_eau_x11_display);
  Window unused_root, unused_parent;
  Window *children = NULL;
  unsigned int nchildren = 0;

  if (!XQueryTree(_eau_x11_display, root, &unused_root, &unused_parent,
                  &children, &nchildren))
    return;

  for (unsigned int i = 0; i < nchildren; i++)
    {
      Window w = children[i];
      XWindowAttributes attr;
      if (!XGetWindowAttributes(_eau_x11_display, w, &attr))
        continue;
      if (attr.map_state != IsViewable)
        continue;

      /* Check WM_CLASS for "Menu".  GNUstep windows carry the class hint
         "Menu", "Menu" (res_name=Menu, res_class=Menu) for ALL of a menu
         app's windows - the bar, dropdowns, panels and caches alike.  The
         old check for res_class "GNUstep" matched nothing, so orphaned
         dropdowns were never cleaned up and wedged the menu bar. */
      XClassHint classHint;
      if (!XGetClassHint(_eau_x11_display, w, &classHint))
        continue;
      BOOL isMenu = (classHint.res_name
                     && strcmp(classHint.res_name, "Menu") == 0
                     && classHint.res_class
                     && strcmp(classHint.res_class, "Menu") == 0);
      XFree(classHint.res_name);
      XFree(classHint.res_class);
      if (!isMenu)
        continue;

      /* Only destroy windows that are clearly dropdown menus.  The menu bar
         itself is a "Menu" "Menu" window too (at y=0, 22px tall), as are
         small utility windows such as the 22px search panel and the 14/18px
         GSCache windows.  A real dropdown is taller than a menu item
         (menuItemHeight is 22px, so a single-item menu window is >22px);
         skip anything at or below the bar height. */
      if (attr.height <= 22)
        continue;

      /* Found a visible GNUstep Menu window.  Destroy the parent
         container (w itself may be the child).  Walk up one level
         to find the actual parent container to destroy. */
      Window parent = w;
      Window root2 = None;
      Window *children2 = NULL;
      unsigned int nc2 = 0;
      if (XQueryTree(_eau_x11_display, parent, &root2, &parent,
                     &children2, &nc2))
        {
          if (children2) XFree(children2);
        }
      // parent now holds the actual parent of w

      // Also recurse into children to destroy any sub-windows
      // (deeper submenus)
      Window *subchildren = NULL;
      unsigned int nsub = 0;
      if (XQueryTree(_eau_x11_display, w, &unused_root, &unused_parent,
                     &subchildren, &nsub))
        {
          for (unsigned int j = 0; j < nsub; j++)
            {
              XDestroyWindow(_eau_x11_display, subchildren[j]);
            }
          if (subchildren) XFree(subchildren);
        }

      // Destroy w itself
      XDestroyWindow(_eau_x11_display, w);

      // If parent is not root, also destroy the parent container
      if (parent != root && parent != None)
        {
          XDestroyWindow(_eau_x11_display, parent);
        }
    }

  if (children) XFree(children);
  XSync(_eau_x11_display, False);
}

/* ---- Close-ahead enforcement: never show a new panel on top of old ones ----
 *
 * Upstream only tears down the first-level dropdown for
 * NSWindows95InterfaceStyle (see NSMenuView -trackWithEvent: teardown and
 * the mainWindowMenuView guard).  Under the Macintosh style an orphaned
 * panel stays mapped, swallows clicks and wedges the menu bar.
 *
 * Invariant enforced here: before a new menu panel is displayed, every
 * visible panel that is NOT part of the new panel's own ancestor chain
 * (menu + supermenus) is closed first.  Submenu nesting is exempt by
 * construction: a submenu's parent menus are its supermenus, so they stay
 * in the keep-set.
 *
 * The AppKit-level pass only closes panels GNUstep still reports visible.
 * During a fast sweep over the menu bar the previous dropdown is already
 * marked hidden by the tracking loop while its X11 window is still mapped
 * (the original wedge), so a second pass withdraws stale panels directly
 * at the X11 level regardless of the AppKit visibility flag.
 */
static void _eau_closeStaleMenuPanelsForMenu(NSMenu *openingMenu)
{
  if (openingMenu == nil) return;

  Class panelClass = objc_getClass("NSMenuPanel");
  if (panelClass == nil) return;

  /* NOTE: we deliberately do NOT iterate [NSApp windows] here.  GNUstep menu
   * panels have is_released_when_closed set, so the tracking loop frees them;
   * a panel that appears in [NSApp windows] can already be deallocated (its
   * memory reused - the freed-object pattern fills it with the NSMenuPanel
   * class pointer), and messaging it then SIGSEGVs.  The stale-panel "wedge"
   * is an X11-mapping problem, so the X11-level withdrawal below is the
   * correct and crash-free way to fix it.
   */

  /* X11-level fallback: withdraw every still-mapped "Menu" dropdown window
     that is not part of the opening menu's keep-set.  AppKit's visibility
     flag is not consulted here because the stale panel is typically already
     flagged hidden by the tracking loop while its X11 window remains mapped
     (that is the wedge this enforcement exists to prevent).  Withdrawing,
     rather than destroying, keeps the cached NSMenuPanel window usable for
     later re-display.
     The keep-set is built from openingMenu's own window chain (menus, which
     are retained by the menu system and cannot dangle), NOT from [NSApp
     windows] (which can contain freed panels). */
  _eau_ensureState();
  if (_eau_x11_display == NULL) return;

  NSMutableSet *keepXids = [NSMutableSet set];
  {
    NSMenu *km = openingMenu;
    while (km != nil)
      {
        NSWindow *pw = [km window];
        if (pw != nil)
          {
            unsigned long xid = (unsigned long)[pw windowRef];
            if (xid != 0)
              [keepXids addObject: [NSNumber numberWithUnsignedLong: xid]];
          }
        km = [km supermenu];
      }
  }

  Window root = DefaultRootWindow(_eau_x11_display);
  Window unused_root, unused_parent;
  Window *children = NULL;
  unsigned int nchildren = 0;

  if (!XQueryTree(_eau_x11_display, root, &unused_root, &unused_parent,
                  &children, &nchildren))
    return;

  for (unsigned int i = 0; i < nchildren; i++)
    {
      Window w = children[i];
      XWindowAttributes attr;
      if (!XGetWindowAttributes(_eau_x11_display, w, &attr))
        continue;

      if (attr.map_state != IsViewable)
        continue;

      XClassHint classHint;
      if (!XGetClassHint(_eau_x11_display, w, &classHint))
        continue;
      BOOL isMenu = (classHint.res_name
                     && strcmp(classHint.res_name, "Menu") == 0
                     && classHint.res_class
                     && strcmp(classHint.res_class, "Menu") == 0);
      XFree(classHint.res_name);
      XFree(classHint.res_class);
      if (!isMenu)
        continue;

      /* Keep the existing guard: skip anything at or below the menu bar
         height so the bar itself and the small utility windows survive. */
      if (attr.height <= 22)
        continue;

      if ([keepXids containsObject: [NSNumber numberWithUnsignedLong: (unsigned long)w]])
        continue;

      NSDebugLog(@"Eau+Menu: withdrawing stale dropdown X window 0x%lx "
                 "before opening %@", (unsigned long)w, openingMenu);
      XWithdrawWindow(_eau_x11_display, w,
                      XScreenNumberOfScreen(attr.screen));

      /* Withdraw the parent too: GNUstep may reparent the NSWindow's X11
         window under an unmanaged container that stays visible on its own. */
      Window parent = w;
      Window *children2 = NULL;
      unsigned int nc2 = 0;
      if (XQueryTree(_eau_x11_display, w, &unused_root, &parent,
                     &children2, &nc2))
        {
          if (children2) XFree(children2);
        }
      if (parent != root && parent != None)
        XWithdrawWindow(_eau_x11_display, parent,
                        XScreenNumberOfScreen(attr.screen));
    }

  if (children) XFree(children);
  XSync(_eau_x11_display, False);
}

/* ---- NSMenuPanel orderFrontRegardless swizzle ---- */

static void (*s_orig_menuPanelOrderFrontRegardless)(id, SEL) = NULL;

static void s_eau_menuPanelOrderFrontRegardless(id self, SEL _cmd)
{
  NSMenu *menu = [(id)self _menu];
  if (menu != nil)
    _eau_closeStaleMenuPanelsForMenu(menu);
  if (s_orig_menuPanelOrderFrontRegardless)
    s_orig_menuPanelOrderFrontRegardless(self, _cmd);
}

/* ---- trackWithEvent: swizzle (increment/decrement, then cleanup) ---- */

static BOOL (*s_orig_trackWithEvent)(id, SEL, id) = NULL;

static BOOL s_eau_trackWithEvent(id self, SEL _cmd, NSEvent *event)
{
  _eau_activeTrackingCount++;
  _eau_trackedMenuView = (NSMenuView *)self;
  BOOL result = NO;
  @try
    {
      if (s_orig_trackWithEvent)
        result = s_orig_trackWithEvent(self, _cmd, event);
    }
  @catch (NSException *e) {}
  _eau_activeTrackingCount--;
  if (_eau_activeTrackingCount == 0)
    _eau_trackedMenuView = nil;
  NSDebugLog(@"Eau+Menu: trackWithEvent end tracking=%d",
             _eau_activeTrackingCount);
  _eau_destroyX11MenuWindows();
  return result;
}

/* ---- nextEventMatchingMask: swizzle for scroll wheel during tracking ---- */

static NSEvent* (*s_orig_nextEventMatchingMask)(id, SEL, NSUInteger, NSDate*, NSString*, BOOL) = NULL;

/* Find the scroll manager for the menu currently being tracked.
 *
 * The scroll manager is associated with the MENU VIEW's window (and the view
 * itself), set up by setupOverflowForMenuView: when the menu was displayed.
 * [NSApp keyWindow] is NOT reliable during tracking: GNUstep menu panels are
 * not key windows, and in Menu.app (global menu bar) the key window is often
 * nil while a dropdown is open.  So walk the tracked view's attached-submenu
 * chain (same logic as the keyboard-navigation code) to the deepest OPEN
 * submenu and look the manager up on its window/view.  Fall back to the key
 * window for non-menu apps where that works.
 */
static EauMenuScrollManager *_eau_activeScrollManager(void)
{
  if (_eau_activeTrackingCount <= 0) return nil;

  NSMenuView *view = _eau_trackedMenuView;
  while (view)
    {
      NSWindow *w = [view window];
      if (w)
        {
          EauMenuScrollManager *mgr = [EauMenuScrollManager scrollManagerForWindow: w];
          if (!mgr)
            {
              mgr = [EauMenuScrollManager scrollManagerForMenuView: view];
            }
          if (mgr) return mgr;
        }
      NSMenuView *attached = [view attachedMenuView];
      NSWindow *aw = [attached window];
      if (!attached || !aw || ![aw isVisible]) break; // closed submenu
      view = attached;
    }

  // Fallback: some apps make the menu panel the key window.
  NSWindow *keyWindow = [NSApp keyWindow];
  if (keyWindow)
    {
      EauMenuScrollManager *mgr = [EauMenuScrollManager scrollManagerForWindow: keyWindow];
      if (!mgr)
        {
          NSMenuView *menuView = _eau_findMenuViewInWindow(keyWindow);
          if (menuView)
            {
              mgr = [EauMenuScrollManager scrollManagerForMenuView: menuView];
            }
        }
      if (mgr) return mgr;
    }
  return nil;
}

static NSEvent* s_eau_nextEventMatchingMask(id self, SEL _cmd, NSUInteger mask, NSDate *date, NSString *mode, BOOL dequeue)
{
  // During menu tracking, add scroll wheel and keyboard events to the mask
  // so we can process them in the tracking loop.
  if (_eau_activeTrackingCount > 0)
    {
      NSDebugLog(@"Eau+Menu: nextEvent adding KeyDown mask");
      mask |= NSScrollWheelMask;
      mask |= NSKeyDownMask;
    }

  NSEvent *event = s_orig_nextEventMatchingMask(self, _cmd, mask, date, mode, dequeue);

  // When keyboard navigation is active, ignore mouse-moved events so the
  // tracking loop doesn't re-evaluate highlight based on stale cursor position.
  if (_eau_keyboardNavActive && event && [event type] == NSMouseMoved)
    {
      // Discard and fetch the next event (up to a limit to avoid infinite loop).
      int limit = 50;
      while (limit-- > 0)
        {
          event = s_orig_nextEventMatchingMask(self, _cmd, mask, date, mode, dequeue);
          if (!event || [event type] != NSMouseMoved)
            break;
        }
    }
  // Any mouse click deactivates keyboard nav.
  if (event && ([event type] == NSLeftMouseDown || [event type] == NSRightMouseDown
                || [event type] == NSOtherMouseDown))
    {
      _eau_keyboardNavActive = NO;
    }

  if (event && _eau_activeTrackingCount > 0)
    {
      // --- Edge scrolling: poll mouse position and scroll if near edge ---
      // We do this on EVERY event during tracking because NSTimer-based
      // edge scrolling doesn't fire reliably in NSEventTrackingRunLoopMode
      // on this GNUstep version.  pollEdgeScroll has its own throttle.
      {
        EauMenuScrollManager *mgr = _eau_activeScrollManager();
        if (mgr)
          {
            [mgr pollEdgeScroll];
          }
      }

      // --- Scroll wheel handling ---
      if ([event type] == NSScrollWheel)
        {
          EauMenuScrollManager *mgr = _eau_activeScrollManager();
          if (mgr && [mgr isScrolling])
            {
              CGFloat deltaY = [event deltaY];
              [mgr scrollByDelta: deltaY];
            }
        }

      // --- Keyboard navigation (arrows, Enter, Escape) ---
      if ([event type] == NSKeyDown && _eau_trackedMenuView)
        {
          // Route to deepest OPEN submenu, or top-level tracking view.
          // GNUstep's detachSubmenu doesn't clear _attachedMenu, so
          // attachedMenuView may return a closed submenu.  Check the
          // submenu window's visibility to skip detached-but-not-cleared
          // submenus.
          NSMenuView *target = _eau_trackedMenuView;
          NSMenuView *attached = [target attachedMenuView];
          while (attached)
            {
              NSWindow *w = [attached window];
              if (!w || ![w isVisible]) break; // closed
              target = attached;
              attached = [target attachedMenuView];
            }
          // NSLog(@"Eau+Menu: key '%@' tracking=%d target=%@ horiz=%d cur=%ld",
          //       [event characters], _eau_activeTrackingCount,
          //       target, [target isHorizontal],
          //       (long)[target highlightedItemIndex]);
          [target keyDown: event];
        }
    }

  return event;
}

@implementation NSMenu (Eau)

#pragma mark - Swizzled Methods

/**
 * Swizzled -menuChanged implementation.
 *
 * The original menuChanged propagates up the menu hierarchy and sets
 * _menu.mainMenuChanged when reaching the main menu. Upstream only
 * handles this flag for NSWindows95InterfaceStyle.
 *
 * This swizzle posts NSMacintoshMenuDidChangeNotification when the
 * change reaches the main menu and NSMacintoshInterfaceStyle is active.
 */
- (void)eau_menuChanged
{
  // Call original implementation (handles propagation and flag setting)
  [self eau_menuChanged];

  // If this is the main menu and using Macintosh style, post notification
  if ([NSApp mainMenu] == self)
    {
      NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
      if (style == NSMacintoshInterfaceStyle)
        {
          [[NSNotificationCenter defaultCenter]
            postNotificationName:@"NSMacintoshMenuDidChangeNotification"
            object:self];
        }
    }
}

/**
 * Swizzled -setMain: implementation.
 *
 * The original setMain: configures the menu as the application's main menu.
 * Upstream only calls updateAllWindowsWithMenu: for NSWindows95InterfaceStyle.
 *
 * This swizzle posts NSMacintoshMenuDidChangeNotification when a menu
 * becomes the main menu and NSMacintoshInterfaceStyle is active.
 */
- (void)eau_setMain:(BOOL)isMain
{
  // Call original implementation
  [self eau_setMain:isMain];

  // If becoming main menu and using Macintosh style, post notification
  if (isMain)
    {
      NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
      if (style == NSMacintoshInterfaceStyle)
        {
          [[NSNotificationCenter defaultCenter]
            postNotificationName:@"NSMacintoshMenuDidChangeNotification"
            object:self];
        }
    }
}

/**
 * Swizzled -display implementation.
 *
 * The original display method shows the menu window unconditionally.
 * While upstream has proposedVisibility:forMenu: in _isVisible, this
 * is only used for querying state, not controlling display.
 *
 * This swizzle checks proposedVisibility:forMenu: before displaying,
 * allowing the theme to hide the in-app menu bar when using a global
 * menu bar (Menu.app).  Additionally, before showing a new dropdown it
 * closes any orphaned menu windows from a previous tracking session
 * that were not properly cleaned up.
 */
- (void)eau_display
{
  // Let theme control visibility
  // The theme's proposedVisibility:forMenu: returns NO for the main menu
  // when Menu.app is available, hiding the in-app menu bar
  if (![[GSTheme theme] proposedVisibility:YES forMenu:self])
    {
      return;
    }

  // Call original implementation
  [self eau_display];
}

/**
 * Swizzled -displayTransient implementation.
 *
 * Pass-through for transient menus (context menus, torn-off menus, etc.).
 * Bottom-screen clamping is handled by the NSMenuPanel setFrameOrigin:
 * swizzle which catches all menu window positioning.
 */
- (void)eau_displayTransient
{
  // Same close-ahead as eau_display/orderFrontRegardless: transient
  // panels are shown via _bWindow orderFront:, which bypasses the
  // NSMenuPanel orderFrontRegardless swizzle, so enforce here too.
  _eau_closeStaleMenuPanelsForMenu(self);
  [self eau_displayTransient];
}

/**
 * Swizzled -performActionForItemAtIndex: implementation.
 *
 * Classic Mac OS (System 7) menu feedback: when the user triggers an item
 * by releasing the mouse over it, the item blinks twice (highlight,
 * unhighlight, highlight, unhighlight) before the menu closes.
 *
 * GNUstep calls this from -[NSMenuView _trackWithEvent:] AFTER the mouse
 * has been released but BEFORE the menu window is taken down and the item
 * is unhighlighted (that happens back in _trackWithEvent:).  So we can
 * blink here while the menu is still on screen.
 *
 * Ordering: we call the original implementation FIRST (firing the action
 * immediately - we must not delay the user's command while the menu
 * blinks), then perform the blink as pure visual feedback.  The action is
 * synchronous, so by the time it returns the menu window is still visible
 * and the highlight is still set - perfect for the blink.
 *
 * We only blink for mouse-driven activation: during tracking the menu
 * panel is visible and _highlightedItemIndex matches `index`.  Key
 * equivalents call this too (via performKeyEquivalent:), but then the menu
 * is normally not visible, so the visibility/highlight checks below make
 * the blink a no-op.
 */
- (void)eau_performActionForItemAtIndex:(NSInteger)index
{
  // Fire the action immediately; the blink is only visual feedback.
  [self eau_performActionForItemAtIndex:index];

  // Blink only while a menu is actively being tracked on screen.
  if (_eau_activeTrackingCount <= 0) return;

  // Blink only when the triggered item itself carries an action.  An item
  // that merely has a submenu (and nothing else) uses the no-op
  // submenuAction: that setSubmenu: installs (NSMenuItem.m:244), so it must
  // not blink - only items whose own action will actually run get the
  // feedback.  Items that have BOTH a submenu and a real action (e.g. a
  // submenu-bearing entry that also performs something on click) do blink.
  {
    id item = [self itemAtIndex: index];
    if (!item) return;
    SEL action = [item action];

    // Skip the blink for items that merely open a submenu: setSubmenu:
    // installs the no-op submenuAction: on them.  Compare by NAME, not SEL
    // pointer: the selector the item carries was registered by the host app,
    // which may not be pointer-identical to our @selector(submenuAction:)
    // even though the names match (selectors are not safely comparable
    // across bundle boundaries on this runtime).
    if (!action) return;
    {
      const char *actionName = sel_getName(action);
      if (actionName && strcmp(actionName, "submenuAction:") == 0) return;
    }
  }

  NSMenuView *view = (NSMenuView *)[self menuRepresentation];
  if (!view || ![view isKindOfClass: objc_getClass("NSMenuView")]) return;

  NSWindow *win = [view window];
  if (!win || ![win isVisible]) return;

  // Re-establish the highlight on the triggered item.
  //
  // For an item that ALSO has a submenu, GNUstep's _executeItemAtIndex:
  // (Macintosh style) calls detachSubmenu BEFORE performActionForItemAtIndex:,
  // and detachSubmenu clears the highlight (setHighlightedItemIndex: -1 in
  // upstream NSMenuView.m).  So we must SET the highlight here rather than
  // require it to still be set; otherwise submenu-bearing items would never
  // blink.  After the blink we leave the item highlighted - _trackWithEvent:
  // unhighlights it again (line 1936) so the end state is unchanged.

  // Two blink cycles.  Each cycle unhighlights briefly, then restores the
  // highlight, letting the run loop draw the intermediate states.
  const int blinkCycles = 2;
  const double blinkDuration = 0.06;
  for (int cycle = 0; cycle < blinkCycles; cycle++)
    {
      [view setHighlightedItemIndex:-1];
      [win display];
      [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:blinkDuration]];

      [view setHighlightedItemIndex:index];
      [win display];
      [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:blinkDuration]];
    }
}


/**
 * Swizzled -close implementation.
 *
 * Tracks that the menu's window is being closed.
 */
- (void)eau_close
{
  [self eau_close];
}

/**
 * Swizzled -closeTransient implementation.
 */
- (void)eau_closeTransient
{
  [self eau_closeTransient];
}

/**
 * Swizzled -_attachMenu: implementation.
 */
- (void)eau_attachMenu:(NSMenu *)aMenu
{
  [self eau_attachMenu:aMenu];
}

@end

#pragma mark - Swizzling Setup

/**
 * Helper function to swizzle a method on NSMenu.
 *
 * @param menuClass The NSMenu class
 * @param originalSel The original selector to swizzle
 * @param swizzledSel The replacement selector
 * @param methodName Human-readable method name for logging
 */
static void swizzleNSMenuMethod(Class menuClass,
                                SEL originalSel,
                                SEL swizzledSel,
                                const char *methodName)
{
  Method originalMethod = class_getInstanceMethod(menuClass, originalSel);
  Method swizzledMethod = class_getInstanceMethod(menuClass, swizzledSel);

  if (!originalMethod)
    {
      NSDebugLog(@"Eau: Cannot swizzle NSMenu -%s: original method not found", methodName);
      return;
    }

  if (!swizzledMethod)
    {
      NSDebugLog(@"Eau: Cannot swizzle NSMenu -%s: swizzled method not found", methodName);
      return;
    }

  // Prevent double-swizzling on bundle reload
  IMP originalIMP = method_getImplementation(originalMethod);
  IMP swizzledIMP = method_getImplementation(swizzledMethod);
  if (originalIMP == swizzledIMP)
    {
      NSDebugLog(@"Eau: NSMenu -%s already swizzled, skipping", methodName);
      return;
    }

  method_exchangeImplementations(originalMethod, swizzledMethod);
  NSDebugLog(@"Eau: Swizzled NSMenu -%s for Macintosh menu support", methodName);
}

/**
 * Constructor function that runs when the theme bundle loads.
 *
 * Installs method swizzles on NSMenu to enable NSMacintoshInterfaceStyle
 * support with upstream libs-gui.
 */
__attribute__((constructor))
static void initNSMenuSwizzling(void)
{
  Class menuClass = objc_getClass("NSMenu");
  if (!menuClass)
    {
      NSDebugLog(@"Eau: Failed to get NSMenu class for swizzling");
      return;
    }

  NSDebugLog(@"Eau: Installing NSMenu swizzles for Macintosh interface style support");

  // Swizzle -menuChanged
  // Posts notification when menu changes reach the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(menuChanged),
                      @selector(eau_menuChanged),
                      "menuChanged");

  // Swizzle -setMain:
  // Posts notification when a menu becomes the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(setMain:),
                      @selector(eau_setMain:),
                      "setMain:");

  // Swizzle -display
  // Allows theme to hide menu window via proposedVisibility:forMenu:
  // and closes orphaned menu windows when a new dropdown is opened.
  swizzleNSMenuMethod(menuClass,
                      @selector(display),
                      @selector(eau_display),
                      "display");

  // Swizzle -displayTransient
  // Same orphaned-menu cleanup for transient menus (context menus,
  // torn-off menus, submenus of transient menus).
  swizzleNSMenuMethod(menuClass,
                      @selector(displayTransient),
                      @selector(eau_displayTransient),
                      "displayTransient");

  // Swizzle -performActionForItemAtIndex:
  // Classic Mac OS (System 7) blink feedback: the triggered item blinks
  // twice before the menu closes (the action fires immediately).
  swizzleNSMenuMethod(menuClass,
                      @selector(performActionForItemAtIndex:),
                      @selector(eau_performActionForItemAtIndex:),
                      "performActionForItemAtIndex:");

  // Swizzle -trackWithEvent: on NSMenuView to count active tracking
  // sessions and run cleanup when tracking ends.
  Class menuViewClass = objc_getClass("NSMenuView");
  if (menuViewClass)
    {
      Method origTW = class_getInstanceMethod(menuViewClass,
                                              @selector(trackWithEvent:));
      if (origTW)
        {
          s_orig_trackWithEvent
            = (BOOL (*)(id, SEL, id))method_getImplementation(origTW);
          method_setImplementation(origTW, (IMP)s_eau_trackWithEvent);
        }
    }

  // Swizzle setFrameOrigin: and setFrame:display: on NSMenuPanel to clamp
  // menu windows to the bottom screen border. This catches ALL menu
  // positioning regardless of which code path is used.
  _eau_swizzleMenuWindowFrameMethods();

  // Swizzle NSMenuPanel orderFrontRegardless to enforce the invariant that
  // no new menu panel is ever shown on top of panels left open by an earlier
  // interaction (only the new panel's own submenu chain stays open).  Every
  // dropdown/submenu/popup display ends in orderFrontRegardless on the
  // NSMenuPanel (_aWindow), so this is the single choke point for regular
  // (non-transient) panels.
  {
    Class menuPanelClass = objc_getClass("NSMenuPanel");
    if (menuPanelClass)
      {
        Method m = class_getInstanceMethod(menuPanelClass,
                                           @selector(orderFrontRegardless));
        if (m)
          {
            s_orig_menuPanelOrderFrontRegardless
              = (void (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m,
              (IMP)s_eau_menuPanelOrderFrontRegardless);
            NSDebugLog(@"Eau: Swizzled NSMenuPanel orderFrontRegardless for stale-panel close-ahead");
          }
      }
  }

  // Swizzle nextEventMatchingMask:untilDate:inMode:dequeue: on NSApplication
  // to add scroll wheel support during menu tracking.
  {
    Class appClass = objc_getClass("NSApplication");
    if (appClass)
      {
        SEL sel = sel_registerName("nextEventMatchingMask:untilDate:inMode:dequeue:");
        Method m = class_getInstanceMethod(appClass, sel);
        if (m)
          {
            {
              // Use memcpy for type-punning to avoid -Wincompatible-function-pointer-types
              IMP imp = method_getImplementation(m);
              memcpy(&s_orig_nextEventMatchingMask, &imp, sizeof(s_orig_nextEventMatchingMask));
            }
            method_setImplementation(m, (IMP)s_eau_nextEventMatchingMask);
            NSDebugLog(@"Eau: Swizzled NSApplication nextEventMatchingMask: for scroll wheel menu support");
          }
      }
  }
}
