/*
 * EauMenuScrollManager.m
 *
 * Scroll state manager for overflowing menus.
 *
 * Coordinate system:
 *   NSMenuView uses GNUstep coordinates (y=0 at bottom, y increases upward).
 *   Item 0 (top of menu) has the highest yOrigin; item N-1 (bottom) has y=0.
 *
 *   scrollOffset = the content y-position at the bottom of the viewport.
 *   scrollOffset = 0 shows bottom items; scrollOffset = maxScrollOffset shows top items.
 *   Initial state: scrollOffset = maxScrollOffset (showing top items).
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "EauMenuScrollManager.h"
#import <AppKit/NSMenuView.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>

/* Edge scrolling parameters */
#define EDGE_SCROLL_THRESHOLD  40.0   // Pixels from edge to trigger autoscroll
#define EDGE_SCROLL_RATE       300.0  // Points per second
#define EDGE_SCROLL_FPS        30.0   // Timer frequency
#define SCROLL_WHEEL_FACTOR    8.0    // Multiplier for scroll wheel deltas

/* Association key for attaching scroll manager to views/windows */
static char kEauScrollManagerAssociationKey;

/* Forward declaration of private NSMenuView methods used for
   coordinate calculations. These exist in GNUstep's NSMenuView.m. */
@interface NSMenuView (EauScrollHelper)
- (CGFloat) yOriginForItem: (NSInteger)item;
- (CGFloat) heightForItem: (NSInteger)item;
- (CGFloat) totalHeight;
@end

@implementation EauMenuScrollManager

@synthesize scrollOffset = _scrollOffset;
@synthesize scrolling = _isScrolling;
@synthesize visibleHeight = _visibleHeight;

- (void)dealloc
{
  _menuView = nil;
}

#pragma mark - Setup

- (void) setupWithMenuView: (NSMenuView *)menuView
               totalHeight: (CGFloat)totalHeight
             visibleHeight: (CGFloat)visibleHeight
{
  _menuView = menuView;
  _totalContentHeight = totalHeight;
  _visibleHeight = visibleHeight;
  _isScrolling = YES;

  // Initialise to show the TOP of the menu (items near index 0).
  // In GNUstep coords, item 0 has the highest yOrigin, so we need
  // scrollOffset ≈ totalHeight - visibleHeight to see the top items.
  _scrollOffset = MAX(0, totalHeight - visibleHeight);

  // Associate with the menu view so rectOfItemAtIndex: can find us
  objc_setAssociatedObject(menuView,
                           &kEauScrollManagerAssociationKey,
                           self,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  // Also associate with the menu view's window so the clamping code
  // and event handling can find the scroll manager from the window.
  NSWindow *window = [menuView window];
  if (window)
    {
      objc_setAssociatedObject(window,
                               &kEauScrollManagerAssociationKey,
                               self,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

+ (EauMenuScrollManager *)scrollManagerForMenuView: (NSMenuView *)menuView
{
  if (!menuView) return nil;
  return (EauMenuScrollManager *)objc_getAssociatedObject(menuView,
                                                          &kEauScrollManagerAssociationKey);
}

+ (EauMenuScrollManager *)scrollManagerForWindow: (NSWindow *)window
{
  if (!window) return nil;
  return (EauMenuScrollManager *)objc_getAssociatedObject(window,
                                                          &kEauScrollManagerAssociationKey);
}

#pragma mark - Overflow Detection (class method, callable from any code path)

+ (BOOL) setupOverflowForMenuView: (NSMenuView *)menuView
{
  if (!menuView || [menuView isHorizontal]) return NO;

  NSWindow *window = [menuView window];
  if (!window) return NO;

  NSScreen *screen = [window screen];
  if (!screen) screen = [NSScreen mainScreen];
  if (!screen) return NO;

  NSRect screenFrame = [screen frame];

  // Total content height of the menu.
  CGFloat totalHeight = [menuView totalHeight];
  if (totalHeight < 1) return NO;

  // Usable vertical space (menu bar excluded).
  CGFloat menuBarHeight = [[GSTheme theme] menuBarHeight] + 2;
  CGFloat maxUsableHeight = screenFrame.size.height - menuBarHeight;

  // If the menu fits on screen no overflow is needed.
  if (totalHeight <= maxUsableHeight) return NO;

  // Determine the current position of the window and which direction has
  // more room.  In GNUstep screen coordinates the origin is the bottom-left
  // corner; the window's frame tells us exactly where it sits.
  NSRect winFrame = [window frame];
  CGFloat winBottom = winFrame.origin.y;
  CGFloat screenTop  = NSMaxY(screenFrame);
  CGFloat screenBottom = NSMinY(screenFrame);

  CGFloat availAbove = screenTop - winBottom - menuBarHeight;
  CGFloat availBelow = winBottom - screenBottom;

  CGFloat visibleHeight;
  CGFloat newBottom;

  if (availAbove >= availBelow)
    {
      // Place the menu extending upward from its current bottom edge.
      visibleHeight = MIN(availAbove, totalHeight);
      newBottom = winBottom;
    }
  else
    {
      // Place the menu extending downward from the screen's bottom edge.
      visibleHeight = MIN(availBelow, totalHeight);
      newBottom = screenBottom;
    }

  if (visibleHeight < 30) visibleHeight = maxUsableHeight;

  // Create (or update) the scroll manager.
  EauMenuScrollManager *mgr = [self scrollManagerForMenuView: menuView];
  if (!mgr)
    {
      mgr = [[self alloc] init];
      [mgr setupWithMenuView: menuView
                 totalHeight: totalHeight
               visibleHeight: visibleHeight];
    }
  else
    {
      /* Lazy-loaded menus (e.g. Menu.app's Applications submenu, populated
       * when the Command menu opens) may have been sized with fewer items
       * first, leaving the manager's total content height stale.  Refresh it
       * so maxScrollOffset reflects the full menu. */
      [mgr setTotalContentHeight: totalHeight];
      [mgr setVisibleHeight: visibleHeight];
    }

  // Resize the menu view so its bounds reflect the visible viewport.
  {
    NSSize vs = [menuView frame].size;
    vs.height = visibleHeight;
    [menuView setFrameSize: vs];
  }

  // Resize the window to the visible viewport height.
  // ONLY set the frame if it actually needs changing — this serves as a
  // re-entrancy guard: the swizzled setFrame:display: in NSMenu+Eau.m
  // calls back into this method, and without this guard we'd loop.
  {
    NSRect currentWinFrame = [window frame];
    if (currentWinFrame.size.height != visibleHeight
        || currentWinFrame.origin.y != newBottom)
      {
        NSRect wf = winFrame;
        wf.size.height = visibleHeight;
        wf.origin.y = newBottom;
        [window setFrame: wf display: NO];
      }
  }

  // Centre the initial selection.
  NSMenu *menu = [menuView menu];
  if (menu)
    {
      NSInteger idx = [menuView highlightedItemIndex];
      if (idx < 0)
        {
          for (NSInteger i = 0; i < (NSInteger)[menu numberOfItems]; i++)
            {
              NSMenuItem *item = [menu itemAtIndex: i];
              if ([item isEnabled] && ![item isSeparatorItem] && ![item isAlternate])
                {
                  idx = i;
                  break;
                }
            }
        }
      if (idx >= 0)
        {
          // Try to show the selected item near the top of the viewport so
          // there is always room to scroll down.  If the item is too close
          // to the bottom of the content to position it near the top, we
          // fall back to showing the top of the menu instead.
          CGFloat itemOrigin   = [menuView yOriginForItem: idx];
          CGFloat itemHeight   = [menuView heightForItem: idx];
          CGFloat targetInTop  = itemOrigin + itemHeight - [mgr visibleHeight];
          if (targetInTop >= 0)
            {
              // Item fits in the top portion — position the viewport so the
              // item sits near the top edge.
              mgr.scrollOffset = targetInTop;
            }
          // else: item is near the bottom — keep the default top-of-menu
          // scrollOffset set above.
        }
    }

  return YES;
}

- (CGFloat)maxScrollOffset
{
  return MAX(0, _totalContentHeight - _visibleHeight);
}

- (void)setScrollOffset:(CGFloat)offset
{
  _scrollOffset = MAX(0, MIN(offset, self.maxScrollOffset));
}

- (void) setVisibleHeight: (CGFloat)height
{
  _visibleHeight = height;
  // Re-clamp scroll offset
  self.scrollOffset = _scrollOffset;
}

- (void) setTotalContentHeight: (CGFloat)height
{
  _totalContentHeight = height;
  /* Re-initialise to show the TOP of the menu, like the initial setup:
     the first time this manager is created the menu may have had only a
     few items (lazy population), leaving scrollOffset at 0 (= bottom of
     content).  With the full height available now, reset to the top so
     item 0 is what the user sees first. */
  _scrollOffset = MAX(0, _totalContentHeight - _visibleHeight);
  self.scrollOffset = _scrollOffset;
}

#pragma mark - Scrolling Operations

- (void) scrollByDelta: (CGFloat)deltaY
{
  // Scroll wheel deltaY convention in GNUstep:
  // Positive deltaY typically means "scroll up" (content moves down).
  // In our inverted content coord system (origin bottom-left, items grow upward),
  // increasing scrollOffset reveals items with higher y (toward the menu top).
  //
  // Sign may need adjustment for platform: if scrolling feels inverted,
  // change the + to - below.
  CGFloat newOffset = _scrollOffset - (deltaY * SCROLL_WHEEL_FACTOR);
  // Clamp
  newOffset = MAX(0, MIN(newOffset, self.maxScrollOffset));

  if (newOffset != _scrollOffset)
    {
      _scrollOffset = newOffset;
      [self _updateDisplay];
    }
}

- (void) scrollToRevealItemAtIndex: (NSInteger)index centered: (BOOL)center
{
  if (!_menuView || index < 0) return;

  CGFloat itemOrigin = [_menuView yOriginForItem: index];
  CGFloat itemHeight = [_menuView heightForItem: index];

  CGFloat targetOffset;
  if (center)
    {
      // Centre the item vertically in the viewport
      targetOffset = itemOrigin - (_visibleHeight / 2.0) + (itemHeight / 2.0);
    }
  else
    {
      // Scroll so the item is at the top of the viewport
      // (item's bottom edge at the top of the viewport)
      targetOffset = itemOrigin + itemHeight - _visibleHeight;
    }

  self.scrollOffset = targetOffset;
  [self _updateDisplay];
}

- (void) scrollItemAtIndexToVisible: (NSInteger)index
{
  if (!_menuView || index < 0) return;

  CGFloat itemOrigin = [_menuView yOriginForItem: index];
  CGFloat itemHeight = [_menuView heightForItem: index];

  // In our coordinate system:
  // viewport in content coords: [scrollOffset, scrollOffset + visibleHeight]
  // Item in content coords: [itemOrigin, itemOrigin + itemHeight]
  CGFloat viewBottom = _scrollOffset;
  CGFloat viewTop = _scrollOffset + _visibleHeight;
  CGFloat itemTop = itemOrigin + itemHeight;
  CGFloat itemBottom = itemOrigin;

  // Check if item is already fully visible
  if (itemBottom >= viewBottom && itemTop <= viewTop)
    {
      return;
    }

  // Item extends above viewport top — scroll up (increase scrollOffset)
  if (itemTop > viewTop)
    {
      self.scrollOffset = itemTop - _visibleHeight;
    }
  // Item extends below viewport bottom — scroll down (decrease scrollOffset)
  else if (itemBottom < viewBottom)
    {
      self.scrollOffset = itemBottom;
    }

  [self _updateDisplay];
}

- (NSRect) viewportRectFromContentRect: (NSRect)contentRect
{
  contentRect.origin.y -= _scrollOffset;
  return contentRect;
}

- (NSPoint) contentPointFromViewportPoint: (NSPoint)viewportPoint
{
  viewportPoint.y += _scrollOffset;
  return viewportPoint;
}

#pragma mark - Edge Autoscroll

- (BOOL) isEdgeScrolling
{
  // Returns YES if we've done edge scrolling within the last 0.1s.
  // This guards scroll-into-view from conflicting with active edge scrolling.
  if (_lastEdgeScrollTime == 0) return NO;
  return ([NSDate timeIntervalSinceReferenceDate] - _lastEdgeScrollTime) < 0.1;
}

- (void) startEdgeScrolling
{
  // No-op: edge scrolling is now driven by pollEdgeScroll from the event loop.
}

- (void) stopEdgeScrolling
{
  _lastEdgeScrollTime = 0;
}

- (void) pollEdgeScroll
{
  if (!_menuView || !_isScrolling) return;

  NSWindow *window = [_menuView window];
  if (!window) return;

  // Throttle: only scroll every ~33ms (~30 fps)
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  if (now - _lastEdgeScrollTime < (1.0 / EDGE_SCROLL_FPS))
    return;

  // Get mouse position in the view's coordinate system.
  NSPoint mouseInWindow = [window mouseLocationOutsideOfEventStream];
  NSPoint mouseInView = [_menuView convertPoint: mouseInWindow fromView: nil];
  CGFloat mouseY = mouseInView.y;

  // Edge detection
  CGFloat scrollChange = 0;

  // Near the top edge -> scroll up (reveal items above)
  if (mouseY > _visibleHeight - EDGE_SCROLL_THRESHOLD
      && _scrollOffset < self.maxScrollOffset)
    {
      scrollChange = EDGE_SCROLL_RATE / EDGE_SCROLL_FPS;
    }
  // Near the bottom edge -> scroll down (reveal items below)
  else if (mouseY < EDGE_SCROLL_THRESHOLD
           && _scrollOffset > 0)
    {
      scrollChange = -EDGE_SCROLL_RATE / EDGE_SCROLL_FPS;
    }

  if (scrollChange != 0)
    {
      _lastEdgeScrollTime = now;
      CGFloat oldOffset = _scrollOffset;
      self.scrollOffset = _scrollOffset + scrollChange;

      if (_scrollOffset != oldOffset)
        {
          [self _updateDisplay];
        }
    }
}

#pragma mark - Scroll Arrow Indicators

- (void) drawScrollIndicatorsInView: (NSView *)view
{
  if (!_isScrolling || !view) return;

  CGFloat viewWidth = [view bounds].size.width;
  CGFloat maxScroll = self.maxScrollOffset;

  [[NSColor colorWithCalibratedWhite: 0.18 alpha: 1.0] set];

  CGFloat cx = viewWidth / 2.0;   // centre of the menu

  // ── Top arrow (points ↑) ────────────────────────────────────────────
  // Shown when content is hidden above the viewport (scrollOffset < maxScroll).
  if (_scrollOffset < maxScroll)
    {
      NSPoint pts[3] = {
        NSMakePoint(cx - 4.0, _visibleHeight - 8.0),
        NSMakePoint(cx + 4.0, _visibleHeight - 8.0),
        NSMakePoint(cx,        _visibleHeight - 2.0)
      };
      NSBezierPath *path = [NSBezierPath bezierPath];
      [path moveToPoint: pts[0]];
      [path lineToPoint: pts[1]];
      [path lineToPoint: pts[2]];
      [path closePath];
      [path fill];
    }

  // ── Bottom arrow (points ↓) ─────────────────────────────────────────
  // Shown when content is hidden below the viewport (scrollOffset > 0).
  if (_scrollOffset > 0)
    {
      NSPoint pts[3] = {
        NSMakePoint(cx - 4.0, 7.0),
        NSMakePoint(cx + 4.0, 7.0),
        NSMakePoint(cx,        1.0)
      };
      NSBezierPath *path = [NSBezierPath bezierPath];
      [path moveToPoint: pts[0]];
      [path lineToPoint: pts[1]];
      [path lineToPoint: pts[2]];
      [path closePath];
      [path fill];
    }
}

#pragma mark - Internal

- (void) _updateDisplay
{
  // Force immediate redraw.  setNeedsDisplay: alone does not cause a
  // visible update during the tracking loop — the view is only drawn
  // when the event loop naturally processes display events, which
  // doesn't happen frequently enough during menu tracking.
  [_menuView setNeedsDisplay: YES];
  [_menuView displayIfNeeded];
}

@end
