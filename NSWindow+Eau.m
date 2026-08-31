#include "Eau+Button.h"
#include "EauWindowButton.h"
#include "EauTitleBarButton.h"
#include "Eau+TitleBarButtons.h"
#include "EauGrowBoxView.h"
#include "AppearanceMetrics.h"
#include <AppKit/NSAnimation.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSAlert.h>
#import "GNUstepGUI/GSTheme.h"
#import <objc/runtime.h>

@interface DefaultButtonAnimation: NSAnimation
{
  __weak NSButtonCell * defaultbuttoncell;
  BOOL reverse;
}

@property (nonatomic, assign) BOOL reverse;
@property (nonatomic, weak) NSButtonCell * defaultbuttoncell;

@end

// Dialog logging helpers (used by NSWindow presentation hooks).
static BOOL EAUIsDialogWindow(NSWindow *window)
{
  if (window == nil)
    {
      return NO;
    }
  if ([window isKindOfClass: [NSPanel class]])
    {
      return YES;
    }
  if ([window level] >= NSModalPanelWindowLevel)
    {
      return YES;
    }
  if (([window styleMask] & NSUtilityWindowMask) != 0)
    {
      return YES;
    }
  return NO;
}

static void EAUCollectDialogTextFromView(NSMutableArray *parts, NSView *view)
{
  if (view == nil || parts == nil)
    {
      return;
    }
    
  @try {
    if ([view isKindOfClass: [NSTextField class]])
      {
        NSTextField *field = (NSTextField *)view;
        NSString *value = [field stringValue];
        if (value != nil && [value length] > 0)
          {
            [parts addObject: value];
          }
      }
    
    // Check if subviews array exists and is valid
    NSArray *subviews = nil;
    @try {
      subviews = [view subviews];
    } @catch (id ex) {}
    
    if (subviews) {
      NSUInteger count = [subviews count];
      for (NSUInteger i = 0; i < count; i++)
        {
          @try {
            EAUCollectDialogTextFromView(parts, [subviews objectAtIndex: i]);
          } @catch (id ex) {}
        }
    }
  } @catch (NSException *e) {
    // Silently ignore errors during view traversal (e.g. during dealloc)
  }
}

static NSString *EAUDialogTextSummary(NSWindow *window)
{
  NSMutableArray *parts = [NSMutableArray array];
  NSString *title = [window title];
  if (title != nil && [title length] > 0)
    {
      [parts addObject: title];
    }
  EAUCollectDialogTextFromView(parts, [window contentView]);
  if ([parts count] == 0)
    {
      return @"";
    }
  return [parts componentsJoinedByString: @" | "];
}

static void EAUWindowLog(NSString *event, NSWindow *window)
{
  if (window == nil)
    {
      NSDebugLog(@"EauWindowLog: %@ window=(null)", event);
      return;
    }
  NSString *summary = nil;
  if (EAUIsDialogWindow(window))
    {
      summary = EAUDialogTextSummary(window);
    }
  NSDebugLog(@"EauWindowLog: %@ window=%p class=%@ title='%@' visible=%d key=%d main=%d level=%ld",
         event,
         window,
         NSStringFromClass([window class]),
         [window title],
         (int)[window isVisible],
         (int)[window isKeyWindow],
         (int)[window isMainWindow],
         (long)[window level]);
  if (summary != nil && [summary length] > 0)
    {
      NSDebugLog(@"EauDialog: window=%p class=%@ text='%@'", window, NSStringFromClass([window class]), summary);
    }
}

@implementation NSWindow (EauLogging)

+ (void) load
{
  static BOOL swizzled = NO;
  if (swizzled)
    {
      return;
    }
  swizzled = YES;

  Class cls = [NSWindow class];
  Method orig;
  Method swiz;

  orig = class_getInstanceMethod(cls, @selector(orderFront:));
  swiz = class_getInstanceMethod(cls, @selector(eau_orderFront:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(orderFrontRegardless));
  swiz = class_getInstanceMethod(cls, @selector(eau_orderFrontRegardless));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(makeKeyAndOrderFront:));
  swiz = class_getInstanceMethod(cls, @selector(eau_makeKeyAndOrderFront:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(orderOut:));
  swiz = class_getInstanceMethod(cls, @selector(eau_orderOut:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(close));
  swiz = class_getInstanceMethod(cls, @selector(eau_close));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  /* windowWillReturnFieldEditor:toObject: swizzling REMOVED - it was causing crashes */

  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(eau_windowWillClose:)
                                               name: NSWindowWillCloseNotification
                                             object: nil];
}

+ (void) eau_windowWillClose: (NSNotification *)note
{
  NSWindow *window = (NSWindow *)[note object];
  EAUWindowLog(@"willClose", window);
}


- (void) eau_orderFront: (id)sender
{
  EAUWindowLog(@"orderFront", self);
  [EauGrowBoxView addToWindow:self];
  [self eau_orderFront: sender];
}

- (void) eau_orderFrontRegardless
{
  EAUWindowLog(@"orderFrontRegardless", self);
  [EauGrowBoxView addToWindow:self];
  [self eau_orderFrontRegardless];
}

- (void) eau_makeKeyAndOrderFront: (id)sender
{
  EAUWindowLog(@"makeKeyAndOrderFront", self);
  [EauGrowBoxView addToWindow:self];
  [self eau_makeKeyAndOrderFront: sender];
}

- (void) eau_orderOut: (id)sender
{
  EAUWindowLog(@"orderOut", self);
  [self eau_orderOut: sender];
}

- (void) eau_close
{
  EAUWindowLog(@"close", self);
  [self eau_close];
}

/* REMOVED: eau_windowWillReturnFieldEditor:toObject: swizzling.
   This delegate method should not be swizzled into NSWindow itself.
   The swizzle caused objc_msgSend_stret crashes due to incorrect type
   encoding. If GWDialog needs to customize field editor behavior, it
   should implement this as a proper delegate method on its delegate object,
   not swizzle it into the window class. */

@end

@implementation DefaultButtonAnimation

@synthesize reverse;
@synthesize defaultbuttoncell;

- (void)setCurrentProgress:(NSAnimationProgress)progress
{
  [super setCurrentProgress: progress];
  if(defaultbuttoncell)
    {
        // Check if the button cell is enabled before updating pulse progress
        BOOL isEnabled = YES;
        @try {
            if ([defaultbuttoncell respondsToSelector:@selector(isEnabled)]) {
              isEnabled = [defaultbuttoncell isEnabled];
            }
            
            if (isEnabled) {
              if(reverse)
              {
                defaultbuttoncell.pulseProgress = [NSNumber numberWithFloat: 1.0 - progress];
              }else{
                defaultbuttoncell.pulseProgress = [NSNumber numberWithFloat: progress];
              }
              NSView *cv = [defaultbuttoncell controlView];
              if (cv) {
                  [cv setNeedsDisplay: YES];
              }
            } else {
              // Button is disabled, stop the animation and reset pulse progress
              NSDebugLog(@"DefaultButtonAnimation: Button cell is disabled, stopping animation");
              defaultbuttoncell.pulseProgress = [NSNumber numberWithFloat: 0.0];
              NSView *cv = [defaultbuttoncell controlView];
              if (cv) {
                  [cv setNeedsDisplay: YES];
              }
              [self stopAnimation];
              return;
            }
        } @catch (NSException *e) {
            [self stopAnimation];
            return;
        }
    }
  if (defaultbuttoncell && progress >= 1.0)
  {
    reverse = !reverse;
    NSDebugLog(@"DefaultButtonAnimation: Reversing direction and restarting animation");
    if ([self isAnimating]) {
        [self startAnimation];
    }
  }
}
@end

@interface DefaultButtonAnimationController : NSObject <NSWindowDelegate>

{
  DefaultButtonAnimation * animation;
  __weak NSButtonCell * buttoncell;
}

@property (nonatomic, weak) NSButtonCell * buttoncell;
@property (nonatomic, strong) NSAnimation * animation;

@end
@implementation DefaultButtonAnimationController
@synthesize buttoncell;
@synthesize animation;
- (id) initWithButtonCell: (NSButtonCell*) cell
{
  NSDebugLog(@"DefaultButtonAnimationController: initWithButtonCell called with cell %p", cell);
  if (self = [super init]) {
    self.buttoncell = cell;    NSDebugLog(@"DefaultButtonAnimationController: Initialized for button cell %p", cell);    
    // Register for additional window notifications to handle visibility changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowWillClose:) 
                                                 name:NSWindowWillCloseNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowDidMiniaturize:) 
                                                 name:NSWindowDidMiniaturizeNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowDidDeminiaturize:) 
                                                 name:NSWindowDidDeminiaturizeNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidBecomeKey:)
                                                 name:NSWindowDidBecomeKeyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResignKey:)
                                                 name:NSWindowDidResignKeyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applicationDidHide:) 
                                                 name:NSApplicationDidHideNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applicationDidUnhide:) 
                                                 name:NSApplicationDidUnhideNotification 
                                               object:nil];
    
    // Monitor for control state changes (enabled/disabled) using KVO
    if ([buttoncell controlView]) {
      NSControl *control = (NSControl *)[buttoncell controlView];
      @try {
        [control addObserver:self
                  forKeyPath:@"enabled"
                     options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                     context:NULL];
        NSDebugLog(@"DefaultButtonAnimationController: Added KVO observer for enabled property on control %p", control);
      }
      @catch (NSException *exception) {
        NSDebugLog(@"DefaultButtonAnimationController: ERROR adding KVO observer for enabled property: %@", exception);
      }
    }
    
    NSDebugLog(@"DefaultButtonAnimationController: Successfully initialized with cell %p", cell);
  }
  return self;
}

/* windowWillReturnFieldEditor:toObject:
 * NSWindowDelegate method that allows customizing the field editor for text input.
 * The field editor is a shared NSText object used for editing text in NSTextField
 * and other text controls.
 *
 * CRITICAL: This method MUST be implemented to avoid a crash on ARM64 architecture.
 * Without this implementation, the Objective-C runtime can incorrectly use
 * objc_msgSend_stret (structure-return calling convention) instead of objc_msgSend
 * (pointer-return calling convention), causing a SIGSEGV when the window tries to
 * get a field editor for text input.
 *
 * By explicitly implementing this method and returning nil, we:
 * 1. Prevent the objc_msgSend_stret crash
 * 2. Tell NSWindow to use its default field editor (which is correct behavior)
 * 3. Ensure text fields work properly with focus and keyboard input
 *
 * This is safe for GWDialog and other windows that use text fields.
 */
- (id)windowWillReturnFieldEditor:(id)fieldEditor toObject:(id)anObject
{
  NSDebugLog(@"DefaultButtonAnimationController: windowWillReturnFieldEditor called for object %p, returning nil (use default)", anObject);
  return nil;  // Return nil to use the default field editor
}


- (void) dealloc
{
  NSDebugLog(@"DefaultButtonAnimationController: dealloc called");
  
  @try {
    // Stop animation and remove all notifications
    if (animation) {
      [animation setDelegate: nil];
      [animation stopAnimation];
      animation = nil;
    }
    
    // Use a local copy of buttoncell to avoid issues if it becomes nil during dealloc
    NSButtonCell *cell = buttoncell;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Remove KVO observer for enabled property safely
    // We only do this if we can still reach the control and it seems valid
    if (cell) {
      @try {
        NSView *cv = [cell controlView];
        if (cv && [cv isKindOfClass:[NSControl class]]) {
          NSControl *control = (NSControl *)cv;
          // paracoid check: only remove if it's still alive enough to have property
          [control removeObserver:self forKeyPath:@"enabled"];
          NSDebugLog(@"DefaultButtonAnimationController: Removed KVO observer for enabled property on control %p", control);
        }
      } @catch (NSException *exception) {
        NSDebugLog(@"DefaultButtonAnimationController: Exception removing KVO: %@", exception);
      }
      
      @try {
        [cell setPulseProgress: [NSNumber numberWithFloat: 0.0]];
        [cell setIsDefaultButton: [NSNumber numberWithBool: NO]];
      } @catch (id ex) {}
    }
  } @catch (NSException *exception) {
    NSDebugLog(@"DefaultButtonAnimationController: ERROR in dealloc: %@", exception);
  }
  
  buttoncell = nil;
}

- (void) startPulse
{
  NSDebugLog(@"DefaultButtonAnimationController: startPulse called for cell %p", buttoncell);
  [self startPulse: NO];
}
- (void) startPulse: (BOOL) reverse
{
  NSDebugLog(@"DefaultButtonAnimationController: startPulse:reverse called with reverse=%d for cell %p", reverse, buttoncell);
  
  // Check if the button cell is enabled before starting animation
  BOOL isEnabled = YES;
  if ([buttoncell respondsToSelector:@selector(isEnabled)]) {
    isEnabled = [buttoncell isEnabled];
  }
  
  if (!isEnabled) {
    NSDebugLog(@"DefaultButtonAnimationController: Button cell is disabled, not starting animation");
    return;
  }
  
  animation = [[DefaultButtonAnimation alloc] initWithDuration:METRICS_PULSE_DURATION
                                animationCurve:NSAnimationEaseInOut];
  animation.reverse = reverse;
  [animation addProgressMark: 1.0];
  [animation setDelegate: self];
  [animation setFrameRate:30.0];
  [animation setAnimationBlockingMode:NSAnimationNonblocking];
  animation.defaultbuttoncell = buttoncell;
  
  NSDebugLog(@"DefaultButtonAnimationController: Starting animation %p for cell %p", animation, buttoncell);
  [animation startAnimation];
  NSDebugLog(@"DefaultButtonAnimationController: Animation started for cell %p", buttoncell);
}
- (void)animation:(NSAnimation *)a
            didReachProgressMark:(NSAnimationProgress)progress
{
  //[animation stopAnimation];
  //[self startPulse: !animation.reverse];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
      NSDebugLog(@"DefaultButtonAnimationController: Window resigned key, stopping animation");
      [animation stopAnimation];
}

// TS: added this method
- (void)windowDidBecomeKey:(NSNotification *)notification
{
      NSWindow *window = [notification object];
      NSWindow *buttonWindow = [[buttoncell controlView] window];
      
      NSDebugLog(@"DefaultButtonAnimationController: Window became key notification received");
      NSDebugLog(@"DefaultButtonAnimationController: Notifying window %p, button window %p", window, buttonWindow);
      
      if (window == buttonWindow)
        {
          if ([self shouldAnimationBeRunning]) {
              NSDebugLog(@"DefaultButtonAnimationController: Button's window became key and button is enabled, starting animation");
              [animation startAnimation];
          } else {
              NSDebugLog(@"DefaultButtonAnimationController: Button's window became key but button is disabled, not starting animation");
          }
        }
      else
        {
          NSDebugLog(@"DefaultButtonAnimationController: Different window became key, ignoring");
        }
}

// Additional notification handlers for proper visibility management
- (void)windowWillClose:(NSNotification *)notification
{
    NSWindow *closingWindow = [notification object];
    NSWindow *buttonWindow = nil;
    
    @try {
        buttonWindow = [[buttoncell controlView] window];
    } @catch (id ex) {}
    
    if (closingWindow == buttonWindow || closingWindow == nil) {
        NSDebugLog(@"DefaultButtonAnimationController: Button's window is closing, stopping animation");
        if (animation) {
            [animation stopAnimation];
        }
    }
}

- (void)windowDidMiniaturize:(NSNotification *)notification
{
    NSWindow *miniaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (miniaturizedWindow == buttonWindow) {
        NSDebugLog(@"DefaultButtonAnimationController: Button's window was miniaturized, stopping animation");
        [animation stopAnimation];
    }
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    NSWindow *deminiaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (deminiaturizedWindow == buttonWindow && [self shouldAnimationBeRunning]) {
        NSDebugLog(@"DefaultButtonAnimationController: Button's window was deminiaturized and button is enabled, starting animation");
        [animation startAnimation];
    }
}

- (void)applicationDidHide:(NSNotification *)notification
{
    NSDebugLog(@"DefaultButtonAnimationController: Application was hidden, stopping animation");
    [animation stopAnimation];
}

- (void)applicationDidUnhide:(NSNotification *)notification
{
    if ([self shouldAnimationBeRunning]) {
        NSDebugLog(@"DefaultButtonAnimationController: Application was unhidden and button is enabled and visible, starting animation");
        [animation startAnimation];
    } else {
        NSDebugLog(@"DefaultButtonAnimationController: Application was unhidden but button is disabled or window not visible, not starting animation");
    }
}

// Helper method to check if animation should be running
- (BOOL)shouldAnimationBeRunning
{
    // Check if button cell is enabled
    BOOL isEnabled = YES;
    if ([buttoncell respondsToSelector:@selector(isEnabled)]) {
        isEnabled = [buttoncell isEnabled];
    }
    
    if (!isEnabled) {
        return NO;
    }
    
    // Check if window is visible and key
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    if (!buttonWindow || ![buttonWindow isKeyWindow] || [buttonWindow isMiniaturized]) {
        return NO;
    }
    
    // Check if application is hidden
    if ([NSApp isHidden]) {
        return NO;
    }
    
    return YES;
}

// Handle control state changes (enabled/disabled) using KVO
- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object 
                        change:(NSDictionary *)change 
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"enabled"]) {
        NSDebugLog(@"DefaultButtonAnimationController: Button enabled state changed, checking animation state");
        
        // Immediately reset pulse progress if button becomes disabled
        if ([buttoncell respondsToSelector:@selector(isEnabled)] && ![buttoncell isEnabled]) {
            NSDebugLog(@"DefaultButtonAnimationController: Button disabled - immediately resetting pulse progress");
            buttoncell.pulseProgress = [NSNumber numberWithFloat: 0.0];
            [[buttoncell controlView] setNeedsDisplay: YES];
        }
        
        if ([self shouldAnimationBeRunning]) {
            if (![animation isAnimating]) {
                NSDebugLog(@"DefaultButtonAnimationController: Button became enabled and visible, starting animation");
                [self startPulse];
            }
        } else {
            if ([animation isAnimating]) {
                NSDebugLog(@"DefaultButtonAnimationController: Button became disabled or invisible, stopping animation");
                [animation stopAnimation];
            }
        }
    }
}
@end

// TS: forward dec
@interface NSWindow(EauTheme)
- (void) EAUsetDefaultButtonCell: (NSButtonCell *)aCell;
@end

@implementation Eau(NSWindow)

// NSWindow.m standardWindowButton:forStyleMask: defers to the theme which
// implements this method (in the theme class).
- (NSButton *) standardWindowButton: (NSWindowButton)button
                       forStyleMask: (NSUInteger) mask
{
  NSDebugLog(@"NSWindow+Eau standardWindowButton:forStyleMask:");

  if (EauTitleBarButtonStyleIsOrb()) {
    EauWindowButton *orbButton = [[EauWindowButton alloc] init];
    [orbButton setRefusesFirstResponder: YES];
    [orbButton setButtonType: NSMomentaryChangeButton];
    [orbButton setImagePosition: NSImageOnly];
    [orbButton setBordered: YES];
    [orbButton setTag: button];

    switch (button) {
      case NSWindowCloseButton:
        [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.97 green:0.26 blue:0.23 alpha:1]];
        [orbButton setImage: [NSImage imageNamed: @"common_Close"]];
        [orbButton setAlternateImage: [NSImage imageNamed: @"common_CloseH"]];
        [orbButton setAction: @selector(performClose:)];
        break;
      case NSWindowMiniaturizeButton:
        [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.9 green:0.7 blue:0.3 alpha:1]];
        [orbButton setImage: [NSImage imageNamed: @"common_Miniaturize"]];
        [orbButton setAlternateImage: [NSImage imageNamed: @"common_MiniaturizeH"]];
        [orbButton setAction: @selector(miniaturize:)];
        break;
      case NSWindowZoomButton:
        [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.322 green:0.778 blue:0.244 alpha:1]];
        [orbButton setImage: [NSImage imageNamed: @"common_Zoom"]];
        [orbButton setAlternateImage: [NSImage imageNamed: @"common_ZoomH"]];
        [orbButton setAction: @selector(zoom:)];
        break;
      case NSWindowToolbarButton:
        [orbButton setAction: @selector(toggleToolbarShown:)];
        break;
      case NSWindowDocumentIconButton:
      default:
        break;
    }
    return orbButton;
  }

  EauTitleBarButton *newButton;

  switch (button)
    {
      case NSWindowCloseButton:
        newButton = [EauTitleBarButton closeButton];
        [newButton setAction: @selector(performClose:)];
        break;
      case NSWindowMiniaturizeButton:
        newButton = [EauTitleBarButton minimizeButton];
        [newButton setAction: @selector(miniaturize:)];
        break;

      case NSWindowZoomButton:
        newButton = [EauTitleBarButton maximizeButton];
        [newButton setAction: @selector(zoom:)];
        break;

      case NSWindowToolbarButton:
        // FIXME - fallback to old style for toolbar button
        {
          EauWindowButton *oldButton = [[EauWindowButton alloc] init];
          [oldButton setAction: @selector(toggleToolbarShown:)];
          [oldButton setRefusesFirstResponder: YES];
          [oldButton setButtonType: NSMomentaryChangeButton];
          [oldButton setImagePosition: NSImageOnly];
          [oldButton setBordered: YES];
          [oldButton setTag: button];
          return oldButton;
        }
      case NSWindowDocumentIconButton:
      default:
        // FIXME - fallback to old style for document icon
        {
          EauWindowButton *oldButton = [[EauWindowButton alloc] init];
          [oldButton setRefusesFirstResponder: YES];
          [oldButton setButtonType: NSMomentaryChangeButton];
          [oldButton setImagePosition: NSImageOnly];
          [oldButton setBordered: YES];
          [oldButton setTag: button];
          return oldButton;
        }
    }

  [newButton setTag: button];
  return newButton;
}

- (void) _overrideNSWindowMethod_setDefaultButtonCell: (NSButtonCell *)aCell {
  NSDebugLog(@"_overrideNSWindowMethod_setDefaultButtonCell:");
  NSWindow *xself = (NSWindow*)self;
  [xself EAUsetDefaultButtonCell:aCell];
}

@end

@implementation NSWindow(EauTheme)

static const void *kEAUDefaultButtonControllerKey = &kEAUDefaultButtonControllerKey;

/* EAUsetDefaultButtonCell:
 * 
 * Custom implementation of setDefaultButtonCell: for the Eau theme.
 * This method is installed as a replacement for NSWindow's setDefaultButtonCell:
 * via the _overrideNSWindowMethod_setDefaultButtonCell: block architecture.
 * 
 * WHAT THIS DOES:
 * - Creates a DefaultButtonAnimationController to manage button pulsing animation
 * - Sets the button's key equivalent to Enter (\r) so pressing Enter activates it
 * - Marks the button cell as the default button (isDefaultButton = YES)
 * - Retains the controller via objc_setAssociatedObject to keep it alive
 * - CONDITIONALLY sets the controller as window delegate (NOT for GWDialog!)
 * 
 * WHY DELEGATE HANDLING IS CRITICAL:
 * GWDialog and other windows with text fields need special handling.
 * When an NSTextField becomes first responder, NSWindow calls the delegate method:
 *   [delegate windowWillReturnFieldEditor:toObject:]
 * 
 * PROBLEM: On ARM64, if this delegate method isn't properly implemented with the
 * correct type encoding, the Objective-C runtime can incorrectly use objc_msgSend_stret
 * (structure-return calling convention) instead of objc_msgSend (pointer-return
 * calling convention), causing a SIGSEGV crash when the field editor is requested.
 * 
 * SOLUTION: 
 * 1. For GWDialog: Don't set a delegate at all. The animation controller still works
 *    via NSNotificationCenter (windowDidBecomeKey, windowDidResignKey, etc.) and
 *    doesn't need to be a delegate.
 * 2. For other windows: Safely set the delegate after checking for existing delegates.
 * 3. DefaultButtonAnimationController implements windowWillReturnFieldEditor:toObject:
 *    returning nil, which tells NSWindow to use its default field editor.
 * 
 * FOCUS MANAGEMENT:
 * By not setting a delegate on GWDialog, we preserve the text field's
 * initialFirstResponder setup done in GWDialog+Eau.m, giving immediate focus
 * with a blinking cursor when dialogs open. Users can type immediately.
 */
- (void) EAUsetDefaultButtonCell: (NSButtonCell *)aCell
{
  NSDebugLog(@"NSWindow+Eau: EAUsetDefaultButtonCell called with cell %p for window %p", aCell, self);
  
  _defaultButtonCell = aCell;
  
  // Clear any existing animation controller first
  id oldController = objc_getAssociatedObject(self, kEAUDefaultButtonControllerKey);
  if (oldController) {
    if ([self delegate] == oldController) {
      [self setDelegate: nil];
    }
    objc_setAssociatedObject(self, kEAUDefaultButtonControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }

  if (aCell == nil) {
    return;
  }

  [self enableKeyEquivalentForDefaultButtonCell];

  [aCell setKeyEquivalent: @"\r"];
  [aCell setKeyEquivalentModifierMask: 0];
  [aCell setIsDefaultButton: [NSNumber numberWithBool: YES]];

  NSDebugLog(@"NSWindow+Eau: Creating DefaultButtonAnimationController for cell %p", aCell);
  DefaultButtonAnimationController * animationcontroller = [[DefaultButtonAnimationController alloc] initWithButtonCell: aCell];

  // Retain controller via association to ensure it stays alive
  objc_setAssociatedObject(self,
                           kEAUDefaultButtonControllerKey,
                           animationcontroller,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  /* CRITICAL FOCUS MANAGEMENT:
   * We deliberately DO NOT set the animation controller as delegate for GWDialog.
   * 
   * Why? GWDialog has text fields that need focus when the dialog opens. When a
   * text field becomes first responder, NSWindow calls the delegate method
   * windowWillReturnFieldEditor:toObject: to get a field editor.
   * 
   * If we set a delegate here, there's a risk of:
   * 1. Method resolution issues causing objc_msgSend_stret crashes on ARM64
   * 2. Interfering with GWDialog's own text field management
   * 3. Breaking the initial first responder setup done in GWDialog+Eau.m
   * 
   * The animation controller doesn't need to be a delegate to work - it receives
   * window notifications (windowDidBecomeKey, windowDidResignKey, etc.) via
   * NSNotificationCenter, which is sufficient for controlling the button animation.
   * 
   * For other window types (non-GWDialog), we can safely set the delegate because
   * they typically don't have the same text field focus requirements on open.
   */
  if ([self isKindOfClass: NSClassFromString(@"GWDialog")])
    {
      NSDebugLog(@"NSWindow+Eau: Skipping delegate assignment for GWDialog %p to preserve text field focus", self);
    }
  else
    {
      // Guard against overriding existing delegates for non-GWDialog windows
      id currentDelegate = [self delegate];
      if (currentDelegate == nil || currentDelegate == animationcontroller)
        {
          NSDebugLog(@"NSWindow+Eau: Setting window delegate to animation controller %p for window %p", animationcontroller, self);
          [self setDelegate: animationcontroller];
        }
      else
        {
          NSDebugLog(@"NSWindow+Eau: Preserving existing delegate %@ for window %p", currentDelegate, self);
        }
    }
  
  NSDebugLog(@"NSWindow+Eau: Starting pulse animation for cell %p", aCell);
  [animationcontroller startPulse];
  
  NSDebugLog(@"NSWindow+Eau: Default button cell setup completed for cell %p", aCell);
}

- (void) animateDefaultButton: (id)sender
{
}

@end