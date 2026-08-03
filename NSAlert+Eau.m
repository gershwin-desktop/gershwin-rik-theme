//
// NSAlert+Eau.m
//
// Comprehensive NSAlert customization for Eau theme.
// Replaces GSAlertPanel with EauAlertPanel for full control over appearance.
//

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import "NSAlert+Eau.h"
#import "Eau.h"
#import "AppearanceMetrics.h"

// Import centralized layout constants from AppearanceMetrics.h

#define useControl(control) ([control superview] != nil)

// Forward declarations
static void setControl(NSView *content, id control, NSString *title);
static void setButton(NSView *content, NSButton *control, NSButton *templateBtn);
static void setKeyEquivalent(NSButton *button);
static NSScrollView *makeScrollViewWithRect(NSRect rect);

// Declare -beep on NSApplication so callers in this file don't warn at compile time
@interface NSApplication (EauBeep)
- (void)beep;
@end

// Private category to declare swizzled selectors so the compiler knows about them
@interface EauAlertPanel (Swizzles)
- (id)eau_initWithoutGModel;
- (id)eau_initWithoutGModelHelper __attribute__((objc_method_family(init)));
- (NSInteger)eau_runModal;
- (NSInteger)eau_runModalHelper;
- (NSButton *)eau_getDefButton;
@end

#pragma mark - EauAlertPanel Implementation

// Re-entrant guard flag, stored as an associated object so EauAlertPanel
// method implementations are safe to swizzle onto any class (e.g., GSAlertPanel)
// that shares the same ivar layout but lacks a dedicated _isStoppingModal ivar.
static const void *kEAUAlertIsStoppingKey = &kEAUAlertIsStoppingKey;
static const void *kEAUAlertWindowRetainKey = &kEAUAlertWindowRetainKey;

static BOOL eauAlertIsStopping(id panel)
{
    return [objc_getAssociatedObject(panel, kEAUAlertIsStoppingKey) boolValue];
}

static void eauAlertSetStopping(id panel, BOOL val)
{
    objc_setAssociatedObject(panel,
                             kEAUAlertIsStoppingKey,
                             @(val),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation EauAlertPanel

+ (void) initialize
{
    if (self == [EauAlertPanel class])
    {
        [self setVersion: 1];
    }
}

- (id) initWithContentRect: (NSRect)rect
{
    // NSLog(@"Eau: EauAlertPanel initWithContentRect called");
    self = [super initWithContentRect: rect
                            styleMask: NSTitledWindowMask
                              backing: NSBackingStoreRetained
                                defer: YES];
    if (self == nil)
    {
        // NSLog(@"Eau: EauAlertPanel super init returned nil");
        return nil;
    }
    
    // NSLog(@"Eau: EauAlertPanel setting properties");
    [self setTitle: @" "];
    [self setLevel: NSModalPanelWindowLevel];
    [self setHidesOnDeactivate: NO];
    [self setBecomesKeyOnlyIfNeeded: NO];
    // One-shot: destroys the X11 back-end window when ordered out (during
    // alert dismissal).  This prevents a crash at dealloc time: NSWindow
    // dealloc calls _terminateBackendWindow, but if the X11 window was
    // already destroyed, _windowNum is 0 and _terminateBackendWindow is
    // safely skipped.  Without this, _terminateBackendWindow in dealloc
    // tries to destroy the X11 window and crashes (segfault).
    [self setOneShot: YES];
    
    NSView *content = [self contentView];
    NSFont *titleFont = METRICS_FONT_SYSTEM_BOLD_13;
    
    // Icon button - positioned at top left
    NSRect iconRect = NSMakeRect(METRICS_ICON_LEFT, 
                                  rect.size.height - METRICS_ICON_TOP - METRICS_ICON_SIDE,
                                  METRICS_ICON_SIDE, METRICS_ICON_SIDE);
    icoButton = [[NSButton alloc] initWithFrame: iconRect];
    [icoButton setAutoresizingMask: NSViewMaxXMargin | NSViewMinYMargin];
    [icoButton setBordered: NO];
    [icoButton setEnabled: NO];
    [icoButton setTitle: @""];   // Never show the default "Button" text
    [[icoButton cell] setImageDimsWhenDisabled: NO];
    [[icoButton cell] setImageScaling: NSImageScaleProportionallyUpOrDown];
    [icoButton setImagePosition: NSImageOnly];
    [icoButton setImage: [[NSApplication sharedApplication] applicationIconImage]];
    [content addSubview: icoButton];
    
    // Title field - positioned to the right of icon, top aligned
    NSRect titleRect = NSMakeRect(METRICS_TEXT_LEFT, 0, 0, 0);
    titleField = [[NSTextField alloc] initWithFrame: titleRect];
    [titleField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [titleField setEditable: NO];
    [titleField setSelectable: NO];
    [titleField setBezeled: NO];
    [titleField setDrawsBackground: NO];
    [titleField setStringValue: @""];
    [titleField setFont: titleFont];
    [titleField setAlignment: NSLeftTextAlignment];
    
    // NO horizontal line - this is what we want to remove from the default appearance
    // The default GSAlertPanel adds an NSBox with NSGrooveBorder here
    // We intentionally omit it for the Eau theme
    
    // Message field - positioned below title, same left alignment
    messageField = [[NSTextField alloc] initWithFrame: NSZeroRect];
    [messageField setEditable: NO];
    [messageField setSelectable: YES];
    [messageField setBezeled: NO];
    [messageField setDrawsBackground: NO];
    [messageField setAlignment: NSLeftTextAlignment];
    [messageField setStringValue: @""];
    [messageField setFont: METRICS_FONT_SYSTEM_REGULAR_11];
    [[messageField cell] setWraps: YES];
    [[messageField cell] setLineBreakMode: NSLineBreakByWordWrapping];
    
    // Buttons
    defButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertDefaultReturn];
    [defButton setKeyEquivalent: @"\r"];
    // // NSLog(@"Eau: defButton key equivalent set to: '%@' - FORCED LOG", [defButton keyEquivalent]);
    [defButton setHighlightsBy: NSPushInCellMask | NSChangeGrayCellMask | NSContentsCellMask];
    @try {
        [defButton setImagePosition: NSImageRight];
        [defButton setImage: [NSImage imageNamed: @"common_ret"]];
        [defButton setAlternateImage: [NSImage imageNamed: @"common_retH"]];
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception loading button images: %@", e);
    }
    [defButton setFont: titleFont];  // Mark as default with bold font
    
    altButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertAlternateReturn];
    othButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertOtherReturn];
    
    // Scroll view for long messages
    scroll = makeScrollViewWithRect(NSMakeRect(0, 0, 80, 80));
    
    result = NSAlertErrorReturn;
    isGreen = YES;

    // NSLog(@"Eau: EauAlertPanel initWithContentRect completed successfully");
    return self;
}

- (id) init
{
    // NSLog(@"Eau: EauAlertPanel init called");

    // Compute a centered initial frame so the X window is never created at
    // (0,0) (bottom-left in OS coordinates).  This prevents a visual flash
    // where the alert appears near the bottom-left corner before -center
    // repositions it.  Use visibleFrame to stay within the usable screen area.
    NSScreen *screen = [NSScreen mainScreen];
    CGFloat winW = METRICS_WIN_MIN_WIDTH;
    CGFloat winH = METRICS_WIN_MIN_HEIGHT;
    CGFloat screenW = [screen visibleFrame].size.width;
    CGFloat screenH = [screen visibleFrame].size.height;
    CGFloat x = ([screen visibleFrame].origin.x
                 + (screenW - winW) / 2);
    CGFloat y = ([screen visibleFrame].origin.y
                 + (screenH - winH) / 2);

    return [self initWithContentRect: NSMakeRect(x, y, winW, winH)];
}

// Helper method injected into GSAlertPanel via swizzling.
// Instead of building a GSAlertPanel (the old look), morphs `self` into an
// EauAlertPanel at the ObjC runtime level so it renders with full Eau metrics.
//
// GSAlertPanel and EauAlertPanel have identical ivar layouts (same ivars, same
// types, same order), so object_setClass() is safe — every ivar access resolves
// to the correct offset regardless of which class's method table we dispatch
// through.  The only previous difference was a _isStoppingModal ivar on
// EauAlertPanel, which has been refactored into an associated object
// (eauAlertIsStopping / eauAlertSetStopping) so the instance sizes match.
- (id) eau_initWithoutGModelHelper
{
    // Do NOT call the original GSAlertPanel _initWithoutGModel — we're building
    // an EauAlertPanel from scratch instead.

    // Morph this GSAlertPanel instance into an EauAlertPanel.
    // GSAlertPanel and EauAlertPanel have identical ivar layouts (the old
    // _isStoppingModal ivar was refactored into an associated object), so
    // object_setClass() is safe.
    object_setClass(self, [EauAlertPanel class]);

    // Call EauAlertPanel's initWithContentRect: directly (not init, to avoid ARC
    // self-assignment constraints in non-init-family helper methods).  This
    // initializes the NSPanel part and creates all subviews with Eau metrics
    // from AppearanceMetrics.h.
    //
    // Compute a centered initial frame the same way EauAlertPanel.init does.
    NSScreen *screen = [NSScreen mainScreen];
    CGFloat winW = METRICS_WIN_MIN_WIDTH;
    CGFloat winH = METRICS_WIN_MIN_HEIGHT;
    CGFloat screenW = [screen visibleFrame].size.width;
    CGFloat screenH = [screen visibleFrame].size.height;
    CGFloat x = ([screen visibleFrame].origin.x
                 + (screenW - winW) / 2);
    CGFloat y = ([screen visibleFrame].origin.y
                 + (screenH - winH) / 2);

    return [self initWithContentRect: NSMakeRect(x, y, winW, winH)];
}

// Helper method to get the default button from GSAlertPanel
// GSAlertPanel has an ivar 'defButton' that we need to access
- (NSButton *) eau_getDefButton
{
    // Try to access the defButton ivar
    Ivar defButtonIvar = class_getInstanceVariable([self class], "defButton");
    if (defButtonIvar)
    {
        return object_getIvar(self, defButtonIvar);
    }
    return nil;
}

// Helper method that will be injected into GSAlertPanel's runModal
// This ensures focus and pulsing work for legacy alert panels
- (NSInteger) eau_runModalHelper
{
    NSDebugLog(@"Eau: eau_runModalHelper called for GSAlertPanel");
    
    // Get the default button from the ivar
    NSButton *defBtn = [self eau_getDefButton];
    
    // Raise the window to ensure it gets input focus
    [NSApp activateIgnoringOtherApps: YES];
    [(NSPanel *)self orderFrontRegardless];
    [(NSPanel *)self makeKeyAndOrderFront: self];
    
    // Ensure the default button has focus and pulsing
    if (defBtn && [[defBtn superview] superview] != nil)
    {
        [(NSPanel *)self makeFirstResponder: defBtn];
        // Set default button cell to enable pulsing animation
        [(NSPanel *)self setDefaultButtonCell: [defBtn cell]];
        NSDebugLog(@"Eau: GSAlertPanel set default button focus and pulsing for button: %@", defBtn);
    }
    
    // Call the original runModal implementation
    return [self eau_runModal];
}

- (void) dealloc
{
    // NSLog(@"Eau: EauAlertPanel dealloc called for panel: %p", self);
    
    @try {
        // Stop any pending animations or callbacks
        [self setDefaultButtonCell: nil];
        [self setDelegate: nil];
    } @catch (id ex) {}

    // In ARC, ivars are automatically released when the object is deallocated
    // We don't need to explicitly release them, but we can set them to nil for safety
    defButton = nil;
    altButton = nil;
    othButton = nil;
    icoButton = nil;
    titleField = nil;
    messageField = nil;
    scroll = nil;
    
    // NSLog(@"Eau: EauAlertPanel dealloc cleaning up completed");
    // In ARC, [super dealloc] is NOT called - it happens automatically
}

- (NSButton *) _makeButtonWithRect: (NSRect)rect tag: (NSInteger)tag
{
    NSButton *button = [[NSButton alloc] initWithFrame: rect];
    [button setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
    [button setButtonType: NSMomentaryPushInButton];
    [button setTitle: @""];
    [button setTarget: self];
    [button setAction: @selector(buttonAction:)];
    [button setTag: tag];
    [button setFont: [NSFont systemFontOfSize: 0]];
    NSDebugLog(@"Eau: Created button with tag %ld, target: %@, action: %@", tag, [button target], NSStringFromSelector([button action]));
    return button;
}

- (void) sizePanelToFit
{
    // NSLog(@"Eau: sizePanelToFit called");
    @try {
    NSRect bounds;
    NSSize ssize;
    NSSize bsize;
    NSSize wsize = {0.0, 0.0};
    NSScreen *screen;
    NSView *content;
    NSButton *buttons[3];
    float position = 0.0;
    int numberOfButtons;
    int i;
    BOOL needsScroll;
    BOOL couldNeedScroll;
    NSUInteger mask = [self styleMask];
    float textAreaWidth;
    float titleHeight = 0.0;
    float messageHeight = 0.0;
    
    screen = [self screen];
    if (screen == nil)
        screen = [NSScreen mainScreen];
    
    bounds = [screen frame];
    bounds = [NSWindow contentRectForFrameRect: bounds styleMask: mask];
    ssize = bounds.size;
    ssize.width = METRICS_SIZE_SCALE * ssize.width;
    ssize.height = METRICS_SIZE_SCALE * ssize.height;
    
    // Start with minimum width
    wsize.width = METRICS_WIN_MIN_WIDTH;
    textAreaWidth = wsize.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
    
    // Calculate title size
    if (useControl(titleField))
    {
        NSRect rect = [titleField frame];
        // Constrain title to available width and let it wrap if needed
        NSSize titleSize = [[titleField attributedStringValue]
                            boundingRectWithSize: NSMakeSize(textAreaWidth, 1e6)
                            options: NSStringDrawingUsesLineFragmentOrigin].size;
        titleHeight = titleSize.height;
        rect.size = titleSize;
        [titleField setFrame: rect];
    }
    
    // Count buttons and calculate button area size
    bsize.width = METRICS_BUTTON_MIN_WIDTH;
    bsize.height = METRICS_BUTTON_HEIGHT;
    buttons[0] = defButton;
    buttons[1] = altButton;
    buttons[2] = othButton;
    numberOfButtons = 0;
    
    for (i = 0; i < 3; i++)
    {
        if (useControl(buttons[i]))
        {
            NSRect rect = [buttons[i] frame];
            if (bsize.width < rect.size.width)
                bsize.width = rect.size.width;
            if (bsize.height < rect.size.height)
                bsize.height = rect.size.height;
            numberOfButtons++;
        }
    }
    
    // Message field sizing with word wrap
    needsScroll = NO;
    couldNeedScroll = useControl(messageField);
    if (couldNeedScroll)
    {
        NSRect rect = [messageField frame];
        // Calculate message size with wrapping
        NSSize msgSize = [[messageField attributedStringValue]
                          boundingRectWithSize: NSMakeSize(textAreaWidth, 1e6)
                          options: NSStringDrawingUsesLineFragmentOrigin].size;
        messageHeight = msgSize.height;
        rect.size = msgSize;
        [messageField setFrame: rect];
    }
    
    // Calculate total height needed
    // Top margin + title + gap + message + gap to buttons + buttons + bottom margin
    float textContentHeight = METRICS_CONTENT_TOP_MARGIN + titleHeight;
    if (messageHeight > 0)
    {
        textContentHeight += METRICS_TITLE_MESSAGE_GAP + messageHeight;
    }
    textContentHeight += METRICS_CONTENT_BOTTOM_MARGIN;
    
    if (numberOfButtons > 0)
    {
        textContentHeight += bsize.height + METRICS_CONTENT_BOTTOM_MARGIN;
    }
    
    // Ensure icon has enough space (icon height + margins)
    float iconContentHeight = METRICS_ICON_TOP + METRICS_ICON_SIDE + METRICS_CONTENT_BOTTOM_MARGIN;
    if (numberOfButtons > 0)
    {
        iconContentHeight += bsize.height + METRICS_CONTENT_BOTTOM_MARGIN;
    }
    
    wsize.height = (textContentHeight > iconContentHeight) ? textContentHeight : iconContentHeight;
    
    // Resize window if message is too long
    if (ssize.height < wsize.height)
    {
        wsize.height = ssize.height;
        needsScroll = couldNeedScroll;
    }
    else if (wsize.height < METRICS_WIN_MIN_HEIGHT)
    {
        wsize.height = METRICS_WIN_MIN_HEIGHT;
    }
    
    if (needsScroll)
        wsize.width += [NSScroller scrollerWidth] + 4.0;
    
    if (ssize.width < wsize.width)
        wsize.width = ssize.width;
    else if (wsize.width < METRICS_WIN_MIN_WIDTH)
        wsize.width = METRICS_WIN_MIN_WIDTH;
    
    bounds = NSMakeRect(0, 0, wsize.width, wsize.height);
    bounds = [NSWindow frameRectForContentRect: bounds styleMask: mask];
    [self setMaxSize: bounds.size];
    [self setMinSize: bounds.size];
    [self setContentSize: wsize];
    content = [self contentView];
    bounds = [content bounds];
    
    // Place icon at top left
    if (useControl(icoButton))
    {
        NSRect iconRect = NSMakeRect(METRICS_ICON_LEFT,
                                      bounds.size.height - METRICS_ICON_TOP - METRICS_ICON_SIDE,
                                      METRICS_ICON_SIDE, METRICS_ICON_SIDE);
        [icoButton setFrame: iconRect];
    }
    
    // Place buttons at bottom right
    if (numberOfButtons > 0)
    {
        position = bounds.origin.x + bounds.size.width - METRICS_CONTENT_SIDE_MARGIN;
        for (i = 0; i < 3; i++)
        {
            if (useControl(buttons[i]))
            {
                NSRect rect;
                position -= bsize.width;
                rect.origin.x = position;
                rect.origin.y = bounds.origin.y + METRICS_CONTENT_BOTTOM_MARGIN;
                rect.size.width = bsize.width;
                rect.size.height = bsize.height;
                [buttons[i] setFrame: rect];
                position -= METRICS_BUTTON_VERT_INTERSPACE;
            }
        }
    }
    
    // Calculate vertical positions for title and message
    float buttonAreaHeight = (numberOfButtons > 0) ? (METRICS_CONTENT_BOTTOM_MARGIN + bsize.height) : 0;
    
    // Place title at top, left-aligned with TextLeft
    float currentY = bounds.size.height - METRICS_CONTENT_TOP_MARGIN;
    if (useControl(titleField))
    {
        NSRect trect = [titleField frame];
        trect.origin.x = METRICS_TEXT_LEFT;
        trect.size.width = bounds.size.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
        currentY -= trect.size.height;
        trect.origin.y = currentY;
        [titleField setFrame: trect];
    }
    
    // Place message below title, same left alignment
    if (useControl(messageField))
    {
        NSRect mrect = [messageField frame];
        
        if (needsScroll)
        {
            NSRect srect;
            float width;
            
            srect.origin.x = METRICS_TEXT_LEFT;
            srect.origin.y = buttonAreaHeight + METRICS_CONTENT_BOTTOM_MARGIN;
            srect.size.width = bounds.size.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
            srect.size.height = currentY - METRICS_TITLE_MESSAGE_GAP - srect.origin.y;
            [scroll setFrame: srect];
            
            if (!useControl(scroll))
                [content addSubview: scroll];
            
            [messageField removeFromSuperview];
            width = [NSScrollView contentSizeForFrameSize: srect.size
                                    hasHorizontalScroller: NO
                                      hasVerticalScroller: YES
                                               borderType: [scroll borderType]].width;
            mrect.origin = NSZeroPoint;
            mrect.size = [[messageField attributedStringValue]
                          boundingRectWithSize: NSMakeSize(width, 1e6)
                          options: NSStringDrawingUsesLineFragmentOrigin].size;
            [messageField setFrame: mrect];
            [scroll setDocumentView: messageField];
        }
        else
        {
            currentY -= METRICS_TITLE_MESSAGE_GAP;
            mrect.origin.x = METRICS_TEXT_LEFT;
            mrect.size.width = bounds.size.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
            currentY -= mrect.size.height;
            mrect.origin.y = currentY;
            [messageField setFrame: mrect];
        }
    }
    else if (useControl(scroll))
    {
        [scroll removeFromSuperview];
    }
    
    isGreen = NO;
    // NSLog(@"Eau: sizePanelToFit displaying content");
    [content display];
    // NSLog(@"Eau: sizePanelToFit completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in sizePanelToFit: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

- (void) buttonAction: (id)sender
{
    BOOL stopping = eauAlertIsStopping(self);
    // NSLog(@"Eau: buttonAction called, sender: %@, stopping: %d", sender, stopping);
    if (sender == nil)
    {
        NSLog(@"Eau: WARNING - buttonAction called with nil sender");
        return;
    }

    // Prevent re-entrant calls while stopping modal
    if (stopping)
    {
        NSLog(@"Eau: WARNING - buttonAction called while already stopping modal, ignoring");
        return;
    }

    NSInteger tag = [sender tag];
    // NSLog(@"Eau: buttonAction tag: %ld", tag);
    if (![self isActivePanel])
    {
        NSLog(@"Eau: WARNING - buttonAction called when not in modal loop");
        return;
    }

    result = tag;
    eauAlertSetStopping(self, YES);

    // NSLog(@"Eau: buttonAction will stop modal with result: %ld", result);

    // Defer stopping the modal to the next run loop iteration.
    // We use performSelector with specific modes because dispatch_async to the
    // main queue may not execute while the run loop is in NSModalPanelRunLoopMode.
    [self performSelector: @selector(_stopModalDeferred)
               withObject: nil
               afterDelay: 0.0
                  inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];

    // NSLog(@"Eau: buttonAction scheduled deferred modal stop");
}

- (void) _stopModalDeferred
{
    // Ensure we check isActivePanel to avoid stopping a context we don't own anymore
    if ([self isActivePanel] || [NSApp modalWindow] == self) {
        // NSLog(@"Eau: _stopModalDeferred executing for result: %ld", result);
        [NSApp stopModalWithCode: result];
    } else {
        // NSLog(@"Eau: _stopModalDeferred skipped - panel no longer active");
    }
    eauAlertSetStopping(self, NO);
}

- (NSInteger) result
{
    return result;
}

- (NSButton *) defaultButton
{
    return defButton;
}

- (BOOL) isActivePanel
{
    return [NSApp modalWindow] == self;
}

- (NSInteger) runModal
{
    NSLog(@"Eau: EauAlertPanel runModal — title=\"%@\"", [self title]);
    
    // Beep when alert is displayed (diagnostics)
    NSApplication *app = [NSApplication sharedApplication];
    // NSLog(@"Eau: EauAlertPanel about to beep - NSApp class: %@ respondsToSelector: %d",
    //       NSStringFromClass([app class]), (int)[app respondsToSelector:@selector(beep)]);
    if ([app respondsToSelector:@selector(beep)]) {
        [app performSelector:@selector(beep)];
    } else {
        // NSLog(@"Eau: NSApp does not respond to -beep");
    }
    
    @try {
        // Bail out if no text was set (initialized but unused panel)
        NSString *title = titleField ? [[titleField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
        NSString *msg = messageField ? [[messageField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
        if (([title length] == 0) && ([msg length] == 0))
          {
            NSLog(@"Eau: EauAlertPanel runModal suppressed — title and message are empty/whitespace (probably a bug in the application)");
            return NSAlertErrorReturn;
          }

        if (isGreen)
        {
            // NSLog(@"Eau: EauAlertPanel calling sizePanelToFit");
            [self sizePanelToFit];
            // NSLog(@"Eau: EauAlertPanel sizePanelToFit completed");
        }
    
        // NSLog(@"[EauTrace] EauAlertPanel runModal: BEFORE center frame=%@ OSorigin=(%.0f,%.0f) size=(%.0f,%.0f)",
        //       NSStringFromRect([self frame]),
        //       [self frame].origin.x, [self frame].origin.y,
        //       [self frame].size.width, [self frame].size.height);
    
    // Ensure we're the key window and can handle events
    [self center];
    
        // NSLog(@"[EauTrace] EauAlertPanel runModal: AFTER center frame=%@ OSorigin=(%.0f,%.0f) size=(%.0f,%.0f)",
        //       NSStringFromRect([self frame]),
        //       [self frame].origin.x, [self frame].origin.y,
        //       [self frame].size.width, [self frame].size.height);
    
    // Float above all other windows (alert takes priority)
    [self setLevel: NSScreenSaverWindowLevel];

    // Raise the window to ensure it gets input focus
    [NSApp activateIgnoringOtherApps: YES];
    [self orderFrontRegardless];
        // NSLog(@"[EauTrace] EauAlertPanel runModal: AFTER orderFrontRegardless frame=%@",
        //       NSStringFromRect([self frame]));
    [self makeKeyAndOrderFront: self];
    
    // Make sure the default button has focus for Enter key handling
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
    }
    
    NSDebugLog(@"Eau: runModal - window is key: %d", [self isKeyWindow]);
    NSDebugLog(@"Eau: runModal - first responder: %@", [self firstResponder]);
    
    // NSLog(@"Eau: About to call runModalForWindow");
    __block id closeObs = [[NSNotificationCenter defaultCenter]
      addObserverForName: NSWindowWillCloseNotification
      object: self queue: nil usingBlock: ^(NSNotification *note) {
        [NSApp abortModal];
      }];
    result = [NSApp runModalForWindow: self];
    [[NSNotificationCenter defaultCenter] removeObserver: closeObs];
    // NSLog(@"Eau: runModalForWindow returned with result: %ld", result);
    [self orderOut: self];
    // NSLog(@"Eau: EauAlertPanel runModal completed");
    return result;
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in EauAlertPanel runModal: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
        return NSAlertErrorReturn;
    }
}

- (void) keyDown: (NSEvent *)event
{
    NSString *chars = [event characters];
    NSDebugLog(@"Eau: keyDown received: '%@'", chars);
    if ([chars length] > 0)
    {
        unichar keyChar = [chars characterAtIndex: 0];
    
    // Handle Enter/Return for default button
    if (keyChar == '\r' && useControl(defButton))
    {
        NSDebugLog(@"Eau: keyDown Enter pressed, clicking default button");
        [self buttonAction: defButton];
        return;
    }
    
    // Handle Spacebar to activate focused button
    if (keyChar == ' ')
    {
        NSView *current = (NSView *)[self firstResponder];
        if (current == defButton && useControl(defButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking default button");
            [self buttonAction: defButton];
        }
        else if (current == altButton && useControl(altButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking alternate button");
            [self buttonAction: altButton];
        }
        else if (current == othButton && useControl(othButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking other button");
            [self buttonAction: othButton];
        }
        else if (useControl(defButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking default button");
            [self buttonAction: defButton];
        }
        return;
    }
    
    // Handle Escape for Cancel button
    if (keyChar == 0x1B && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
    {
        [self buttonAction: altButton];
        return;
    }
    
    // Handle Tab to cycle through buttons
    if (keyChar == '\t')
    {
        NSView *current = (NSView *)[self firstResponder];
        NSView *next = [current nextKeyView];
        if (next != nil)
        {
            [self makeFirstResponder: next];
        }
        else if (useControl(defButton))
        {
            [self makeFirstResponder: defButton];
        }
        return;
    }
    
    // Handle Shift-Tab to cycle backwards
    if (([event modifierFlags] & NSShiftKeyMask) && keyChar == '\t')
    {
        NSView *current = (NSView *)[self firstResponder];
        NSView *prev = [current previousKeyView];
        if (prev != nil)
        {
            [self makeFirstResponder: prev];
        }
        else if (useControl(othButton))
        {
            [self makeFirstResponder: othButton];
        }
        else if (useControl(altButton))
        {
            [self makeFirstResponder: altButton];
        }
        else if (useControl(defButton))
        {
            [self makeFirstResponder: defButton];
        }
        return;
    }
    
    // Handle Right Arrow to cycle forward through buttons
    if (keyChar == NSRightArrowFunctionKey && (([event modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask)) == 0))
    {
        NSView *current = (NSView *)[self firstResponder];
        if (current == defButton)
        {
            if (useControl(altButton))
                [self makeFirstResponder: altButton];
            else if (useControl(othButton))
                [self makeFirstResponder: othButton];
        }
        else if (current == altButton)
        {
            if (useControl(othButton))
                [self makeFirstResponder: othButton];
            else
                [self makeFirstResponder: defButton];
        }
        else if (current == othButton)
        {
            [self makeFirstResponder: defButton];
        }
        return;
    }
    
    // Handle Left Arrow to cycle backward through buttons
    if (keyChar == NSLeftArrowFunctionKey && (([event modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask)) == 0))
    {
        NSView *current = (NSView *)[self firstResponder];
        if (current == defButton)
        {
            if (useControl(othButton))
                [self makeFirstResponder: othButton];
            else if (useControl(altButton))
                [self makeFirstResponder: altButton];
        }
        else if (current == altButton)
        {
            [self makeFirstResponder: defButton];
        }
        else if (current == othButton)
        {
            if (useControl(altButton))
                [self makeFirstResponder: altButton];
            else if (useControl(defButton))
                [self makeFirstResponder: defButton];
        }
        return;
    }
    }
    
    [super keyDown: event];
}

- (void) copyAllTextToPasteboard
{
    NSMutableArray *parts = [NSMutableArray array];
    NSString *winTitle = [self title];
    if ([winTitle length] > 0)
    {
        [parts addObject: winTitle];
    }
    if (useControl(titleField))
    {
        NSString *t = [titleField stringValue];
        if ([t length] > 0)
        {
            [parts addObject: t];
        }
    }
    if (useControl(messageField))
    {
        NSString *m = [messageField stringValue];
        if ([m length] > 0)
        {
            [parts addObject: m];
        }
    }
    NSMutableArray *btnLabels = [NSMutableArray array];
    if (useControl(defButton))
    {
        [btnLabels addObject: [defButton title]];
    }
    if (useControl(altButton))
    {
        [btnLabels addObject: [altButton title]];
    }
    if (useControl(othButton))
    {
        [btnLabels addObject: [othButton title]];
    }
    if ([btnLabels count] > 0)
    {
        [parts addObject: [btnLabels componentsJoinedByString: @"    "]];
    }
    if ([parts count] == 0)
    {
        return;
    }
    NSString *summary = [parts componentsJoinedByString: @"\n"];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes: [NSArray arrayWithObject: NSPasteboardTypeString]
               owner: nil];
    [pb setString: summary forType: NSPasteboardTypeString];
    NSDebugLog(@"Eau: Copied dialog text to pasteboard: %@", summary);
}

- (BOOL) performKeyEquivalent: (NSEvent *)event
{
    NSString *chars = [event characters];
    NSUInteger modifiers = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;
    // NSLog(@"Eau: performKeyEquivalent received: '%@', modifiers: %lu, isActivePanel: %d", chars, (unsigned long)modifiers, [self isActivePanel]);

    // During modal operation, intercept ALL keyboard events to prevent app shortcuts
    if ([self isActivePanel])
    {
        // Handle Cmd-C (Alt-C on GNUstep) to copy all dialog text to clipboard
        if ((modifiers & NSCommandKeyMask) && [chars caseInsensitiveCompare: @"c"] == NSOrderedSame)
        {
            // NSLog(@"Eau: performKeyEquivalent Cmd-C pressed, copying dialog text");
            [self copyAllTextToPasteboard];
            return YES;
        }

        // Handle Return/Enter for default button
        if ([chars isEqualToString: @"\r"] && useControl(defButton))
        {
            // NSLog(@"Eau: performKeyEquivalent Enter pressed, clicking default button");
            [self buttonAction: defButton];
            return YES;
        }

        // Handle Spacebar for default button
        if ([chars isEqualToString: @" "] && modifiers == 0 && useControl(defButton))
        {
            // NSLog(@"Eau: performKeyEquivalent Spacebar pressed, clicking default button");
            [self buttonAction: defButton];
            return YES;
        }

        // Handle Escape for cancel button
        if ([chars isEqualToString: @"\e"] && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
        {
            // NSLog(@"Eau: performKeyEquivalent Escape pressed, clicking cancel button");
            [self buttonAction: altButton];
            return YES;
        }

        // Let unhandled events (Tab, arrow keys) propagate to keyDown:
        return NO;
    }

    return [super performKeyEquivalent: event];
}

- (void) sendEvent: (NSEvent *)event
{
    if ([event type] == NSKeyDown)
    {
        NSString *chars = [event characters];
        // NSLog(@"Eau: sendEvent received keyDown: '%@', isActivePanel: %d", chars, [self isActivePanel]);
        
        // CRITICAL: During modal operation, try performKeyEquivalent FIRST
        // This ensures keyboard events are handled by the dialog, not the app
        if ([self isActivePanel])
        {
            if ([self performKeyEquivalent: event])
            {
                // NSLog(@"Eau: Event consumed by performKeyEquivalent, not propagating to app");
                return;  // Event was handled, DO NOT call super or keyDown
            }
        }
        
        // Always handle keyboard events ourselves - prevent app shortcuts from stealing them
        if ([chars length] > 0)
        {
            unichar keyChar = [chars characterAtIndex: 0];
            
            // Handle Return/Enter for default button
            if (keyChar == '\r' && useControl(defButton))
            {
                // NSLog(@"Eau: sendEvent Enter pressed, clicking default button");
                [self buttonAction: defButton];
                return;  // Don't call super - we handled it
            }
            
            // Handle Spacebar for default button
            if (keyChar == ' ' && useControl(defButton))
            {
                // NSLog(@"Eau: sendEvent Spacebar pressed, clicking default button");
                [self buttonAction: defButton];
                return;  // Don't call super - we handled it
            }
            
            // Handle Escape for cancel button
            if (keyChar == 0x1B && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
            {
                // NSLog(@"Eau: sendEvent Escape pressed, clicking cancel button");
                [self buttonAction: altButton];
                return;  // Don't call super - we handled it
            }
        }
    }
    [super sendEvent: event];
}

/* Ensure the window is centered right before it is ordered front.
   This prevents a visual flash where the X window would otherwise be
   created at the OS (0,0) position (near bottom-left of the screen)
   before being moved to the correct center position by -center. */
- (void) orderFrontRegardless
{
    [self center];
    [super orderFrontRegardless];
}

- (BOOL) canBecomeKeyWindow
{
    return YES;
}

- (BOOL) canBecomeMainWindow
{
    return YES;
}

/* GSExceptionPanel calls setUserInfo: on the panel after morphing it to
   EauAlertPanel via object_setClass().  Store the userInfo via an
   associated object to avoid adding an ivar. */
static const void *kEAUUserInfoKey = &kEAUUserInfoKey;

- (void) setUserInfo: (NSDictionary *)userInfo
{
    objc_setAssociatedObject(self, kEAUUserInfoKey, userInfo,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id) userInfo
{
    return objc_getAssociatedObject(self, kEAUUserInfoKey);
}

/* GSExceptionPanel calls userInfoPanel on the morphed panel to order it out. */
- (id) userInfoPanel
{
    return self;
}

- (void) setTitleBar: (NSString *)titleBar
                icon: (NSImage *)icon
               title: (NSString *)title
             message: (NSString *)message
{
    // NSLog(@"Eau: setTitleBar called with title='%@', message='%@'", title, message);
    @try {
    NSView *content = [self contentView];
    if (content == nil)
    {
        NSLog(@"Eau: WARNING - contentView is nil");
        return;
    }
    
    // NSLog(@"Eau: Setting window title");
    if (titleBar != nil)
        [self setTitle: titleBar];
    
    // NSLog(@"Eau: Setting icon");
    [icoButton setTitle: @""];   // Guard: never show the default "Button" text
    [icoButton setImagePosition: NSImageOnly];
    if (icon != nil)
        [icoButton setImage: icon];
    
    if (title == nil)
        title = titleBar;
    
    // NSLog(@"Eau: Setting title field");
    setControl(content, titleField, title);
    
    // NSLog(@"Eau: Handling scroll view");
    if (useControl(scroll))
    {
        [scroll setDocumentView: nil];
        [scroll removeFromSuperview];
        [messageField removeFromSuperview];
    }
    
    // NSLog(@"Eau: Setting message field");
    setControl(content, messageField, message);
    
    // Always use left alignment for consistent appearance
    [messageField setAlignment: NSLeftTextAlignment];
    
    // NSLog(@"Eau: setTitleBar completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in setTitleBar: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

- (void) setTitleBar: (NSString *)titleBar
                icon: (NSImage *)icon
               title: (NSString *)title
             message: (NSString *)message
                 def: (NSString *)defaultButton
                 alt: (NSString *)alternateButton
               other: (NSString *)otherButton
{
    NSView *content = [self contentView];
    
    [self setTitleBar: titleBar icon: icon title: title message: message];
    setControl(content, defButton, defaultButton);
    setControl(content, altButton, alternateButton);
    setControl(content, othButton, otherButton);
    
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
        // Set the default button cell to enable blue pulsing animation
        [self setDefaultButtonCell: [defButton cell]];
    }
    else
        [self makeFirstResponder: self];
    
    if (useControl(altButton))
        setKeyEquivalent(altButton);
    if (useControl(othButton))
        setKeyEquivalent(othButton);
    
    // Set up key view chain
    {
        BOOL ud = useControl(defButton);
        BOOL ua = useControl(altButton);
        BOOL uo = useControl(othButton);
        
        if (ud)
        {
            if (uo)
                [defButton setNextKeyView: othButton];
            else if (ua)
                [defButton setNextKeyView: altButton];
            else
            {
                [defButton setPreviousKeyView: nil];
                [defButton setNextKeyView: nil];
            }
        }
        
        if (uo)
        {
            if (ua)
                [othButton setNextKeyView: altButton];
            else if (ud)
                [othButton setNextKeyView: defButton];
            else
            {
                [othButton setPreviousKeyView: nil];
                [othButton setNextKeyView: nil];
            }
        }
        
        if (ua)
        {
            if (ud)
                [altButton setNextKeyView: defButton];
            else if (uo)
                [altButton setNextKeyView: othButton];
            else
            {
                [altButton setPreviousKeyView: nil];
                [altButton setNextKeyView: nil];
            }
        }
    }
    
    [self sizePanelToFit];
    isGreen = YES;
    result = NSAlertErrorReturn;
}

- (void) setButtons: (NSArray *)buttons
{
    // NSLog(@"Eau: setButtons called with %lu buttons", (unsigned long)[buttons count]);
    @try {
    NSView *content = [self contentView];
    if (content == nil)
    {
        NSLog(@"Eau: WARNING - contentView is nil in setButtons");
        return;
    }
    NSUInteger count = [buttons count];
    
    // NSLog(@"Eau: Setting button 0");
    setButton(content, defButton, count > 0 ? [buttons objectAtIndex: 0] : nil);
    // NSLog(@"Eau: Setting button 1");
    setButton(content, altButton, count > 1 ? [buttons objectAtIndex: 1] : nil);
    // NSLog(@"Eau: Setting button 2");
    setButton(content, othButton, count > 2 ? [buttons objectAtIndex: 2] : nil);
    
    // NSLog(@"Eau: Setting up first responder");
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
        // Set the default button cell to enable blue pulsing animation
        [self setDefaultButtonCell: [defButton cell]];
    }
    else
        [self makeFirstResponder: self];
    
    // NSLog(@"Eau: Setting up key view chain");
    if (count > 2)
    {
        [defButton setNextKeyView: othButton];
        [othButton setNextKeyView: altButton];
        [altButton setNextKeyView: defButton];
    }
    else if (count > 1)
    {
        [defButton setNextKeyView: altButton];
        [altButton setNextKeyView: defButton];
    }
    else if (count > 0)
    {
        [defButton setPreviousKeyView: nil];
        [defButton setNextKeyView: nil];
    }
    
    // NSLog(@"Eau: Calling sizePanelToFit from setButtons");
    [self sizePanelToFit];
    // NSLog(@"Eau: sizePanelToFit completed from setButtons");
    isGreen = YES;
    result = NSAlertErrorReturn;
    // NSLog(@"Eau: setButtons completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in setButtons: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

@end

#pragma mark - Helper Functions

static NSScrollView *makeScrollViewWithRect(NSRect rect)
{
    float lineHeight = [METRICS_FONT_SYSTEM_REGULAR_11 boundingRectForFont].size.height;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame: rect];
    
    [scrollView setBorderType: NSLineBorder];
    [scrollView setBackgroundColor: [NSColor controlBackgroundColor]];
    [scrollView setHasHorizontalScroller: NO];
    [scrollView setHasVerticalScroller: YES];
    [scrollView setScrollsDynamically: YES];
    [scrollView setLineScroll: lineHeight];
    [scrollView setPageScroll: lineHeight * 10.0];
    return scrollView;
}

static void setControl(NSView *content, id control, NSString *title)
{
    if (title != nil)
    {
        if ([control respondsToSelector: @selector(setTitle:)])
            [control setTitle: title];
        else if ([control respondsToSelector: @selector(setStringValue:)])
            [control setStringValue: title];
        [control sizeToFit];
        if (!useControl(control))
            [content addSubview: control];
    }
    else if (useControl(control))
    {
        [control removeFromSuperview];
    }
}

static void setButton(NSView *content, NSButton *control, NSButton *templateBtn)
{
    if (templateBtn != nil)
    {
        [control setTitle: [templateBtn title]];
        [control setKeyEquivalent: [templateBtn keyEquivalent]];
        [control setKeyEquivalentModifierMask: [templateBtn keyEquivalentModifierMask]];
        [control setTag: [templateBtn tag]];
        [control sizeToFit];
        if (!useControl(control))
            [content addSubview: control];
    }
    else if (useControl(control))
    {
        [control removeFromSuperview];
    }
}

static void setKeyEquivalent(NSButton *button)
{
    NSString *title = [button title];
    
    if (![[button keyEquivalent] isEqualToString: @"\r"])
    {
        if ([title isEqualToString: @"Cancel"])
        {
            [button setKeyEquivalent: @"\e"];
            [button setKeyEquivalentModifierMask: 0];
        }
        else if ([title isEqualToString: @"Don't Save"])
        {
            [button setKeyEquivalent: @"d"];
            [button setKeyEquivalentModifierMask: NSCommandKeyMask];
        }
        else
        {
            [button setKeyEquivalent: @""];
            [button setKeyEquivalentModifierMask: 0];
        }
    }
}

#pragma mark - NSAlert Category for Swizzling

/* NSAlert (Eau) Category
 * 
 * Comprehensive NSAlert customization for the Eau theme.
 * 
 * WHAT THIS DOES:
 * - Swizzles NSAlert's _setupPanel to use EauAlertPanel for custom appearance
 * - Swizzles NSAlert's runModal to add focus management for text fields
 * - Ensures any text fields in alerts receive focus immediately when shown
 * - Sets up proper tab navigation between controls in the alert
 * - Configures default button for pulsating animation
 * 
 * WHY WE DO THIS:
 * - Users expect text fields in alerts to be immediately ready for input
 * - The cursor should blink in text fields without requiring a click
 * - Tab key should work to navigate between buttons and controls
 * - Default button should pulse to indicate it's the primary action
 * 
 * FOCUS MANAGEMENT STRATEGY:
 * When an alert appears, we search for editable text fields and set the first
 * one found as the initialFirstResponder. This ensures:
 * 1. The field editor activates automatically
 * 2. The cursor blinks immediately
 * 3. Keyboard input works without clicking
 * 4. Tab navigation is properly configured
 * 
 * If no text field exists, focus goes to the default button.
 */
@implementation NSAlert (Eau)

+ (void) load
{
    static BOOL didSwizzle = NO;
    if (didSwizzle)
        return;
    didSwizzle = YES;
    
    NSDebugLog(@"Eau: Installing NSAlert customizations");
    // // NSLog(@"Eau: Installing NSAlert customizations - FORCED LOG");
    
    // Swizzle NSAlert's _setupPanel to use EauAlertPanel
    Class alertClass = NSClassFromString(@"NSAlert");
    SEL origSetupSel = @selector(_setupPanel);
    SEL swizzledSetupSel = @selector(eau_setupPanel);
    
    // // NSLog(@"Eau: Found NSAlert class: %@", alertClass);
    
    Method origSetupMethod = class_getInstanceMethod(alertClass, origSetupSel);
    Method swizzledSetupMethod = class_getInstanceMethod(alertClass, swizzledSetupSel);
    
    // // NSLog(@"Eau: Original _setupPanel method: %p", origSetupMethod);
    // // NSLog(@"Eau: Swizzled eau_setupPanel method: %p", swizzledSetupMethod);
    
    if (origSetupMethod && swizzledSetupMethod)
    {
        BOOL didAdd = class_addMethod(alertClass,
                                      origSetupSel,
                                      method_getImplementation(swizzledSetupMethod),
                                      method_getTypeEncoding(swizzledSetupMethod));
        if (didAdd)
        {
            class_replaceMethod(alertClass,
                                swizzledSetupSel,
                                method_getImplementation(origSetupMethod),
                                method_getTypeEncoding(origSetupMethod));
        }
        else
        {
            method_exchangeImplementations(origSetupMethod, swizzledSetupMethod);
        }
        NSDebugLog(@"Eau: NSAlert _setupPanel swizzled successfully");
        // // NSLog(@"Eau: NSAlert _setupPanel swizzled successfully - FORCED LOG");
    }
    else
    {
        NSDebugLog(@"Eau: Warning - could not find _setupPanel method to swizzle");
        // // NSLog(@"Eau: Warning - could not find _setupPanel method to swizzle - FORCED LOG");
    }
    
    // Swizzle NSAlert's runModal to ensure proper activation
    SEL origRunModalSel = @selector(runModal);
    SEL swizzledRunModalSel = @selector(eau_runModal);
    
    Method origRunModalMethod = class_getInstanceMethod(alertClass, origRunModalSel);
    Method swizzledRunModalMethod = class_getInstanceMethod(alertClass, swizzledRunModalSel);
    
    if (origRunModalMethod && swizzledRunModalMethod)
    {
        BOOL didAddRunModal = class_addMethod(alertClass,
                                              origRunModalSel,
                                              method_getImplementation(swizzledRunModalMethod),
                                              method_getTypeEncoding(swizzledRunModalMethod));
        if (didAddRunModal)
        {
            class_replaceMethod(alertClass,
                                swizzledRunModalSel,
                                method_getImplementation(origRunModalMethod),
                                method_getTypeEncoding(origRunModalMethod));
        }
        else
        {
            method_exchangeImplementations(origRunModalMethod, swizzledRunModalMethod);
        }
        NSDebugLog(@"Eau: NSAlert runModal swizzled successfully");
    }
    else
    {
        NSDebugLog(@"Eau: Warning - could not find runModal method to swizzle");
    }
    
    // Also swizzle GSAlertPanel's _initWithoutGModel to handle legacy alert functions
    // (NSRunAlertPanel, NSGetAlertPanel, etc.) which create GSAlertPanel directly
    Class gsAlertPanelClass = NSClassFromString(@"GSAlertPanel");
    if (gsAlertPanelClass)
    {
        SEL origInitSel = @selector(_initWithoutGModel);
        SEL swizzledInitSel = @selector(eau_initWithoutGModel);
        
        // Add the swizzled init method to GSAlertPanel dynamically
        Method initHelperMethod = class_getInstanceMethod([EauAlertPanel class], @selector(eau_initWithoutGModelHelper));
        if (initHelperMethod)
        {
            class_addMethod(gsAlertPanelClass,
                           swizzledInitSel,
                           method_getImplementation(initHelperMethod),
                           method_getTypeEncoding(initHelperMethod));
            
            Method origInitMethod = class_getInstanceMethod(gsAlertPanelClass, origInitSel);
            Method newSwizzledMethod = class_getInstanceMethod(gsAlertPanelClass, swizzledInitSel);
            
            if (origInitMethod && newSwizzledMethod)
            {
                method_exchangeImplementations(origInitMethod, newSwizzledMethod);
                NSDebugLog(@"Eau: GSAlertPanel _initWithoutGModel swizzled successfully");
            }
        }

        // Note: GSAlertPanel runModal/sizePanelToFit swizzles are intentionally
        // disabled here to avoid crashes in legacy alert panels.
    }
}

// Replacement for NSAlert's runModal method
// - Ensures activation and key focus
// - Preserves GNUstep lifecycle (setup, run modal, order out, destroy window)
// - Avoids KVC retain/release side effects on _window
- (NSInteger) eau_runModal
{
    NSLog(@"Eau: NSAlert eau_runModal — messageText=\"%@\" informativeText=\"%@\"",
          [self messageText], [self informativeText]);
    NSLog(@"Eau: NSAlert caller stack: %@", [NSThread callStackSymbols]);
    @try {

    if (![NSThread isMainThread])
    {
        __block NSInteger result;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self eau_runModal];
        });
        return result;
    }
    
    // Never show an alert that has no text (probably a bug in the app)
    NSString *msgText = [[self messageText] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *infoText = [[self informativeText] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ((msgText == nil || [msgText length] == 0) &&
        (infoText == nil || [infoText length] == 0))
      {
        NSLog(@"Eau: NSAlert suppressed — both messageText and informativeText are empty/whitespace (probably a bug in the application)");
        return NSAlertErrorReturn;
      }

    // Call _setupPanel - this invokes the Eau custom setup since methods were swizzled
    // After swizzling: _setupPanel -> eau_setupPanel code, eau_setupPanel -> original code
    [self performSelector: @selector(_setupPanel)];
    
    // Beep when alert is displayed (diagnostics)
    NSApplication *eauApp = [NSApplication sharedApplication];
    // NSLog(@"Eau: NSAlert about to beep - NSApp class: %@ respondsToSelector: %d",
    //       NSStringFromClass([eauApp class]), (int)[eauApp respondsToSelector:@selector(beep)]);
    if ([eauApp respondsToSelector:@selector(beep)]) {
        [eauApp performSelector:@selector(beep)];
    } else {
        // NSLog(@"Eau: NSApp does not respond to -beep");
    }
    
    // Get the _window ivar (NSAlert owns the panel instance)
    NSWindow *window = nil;
    @try {
        window = [self valueForKey: @"_window"];
    }
    @catch (NSException *exception) {
        Ivar windowIvar = class_getInstanceVariable([self class], "_window");
        if (windowIvar)
        {
            window = object_getIvar(self, windowIvar);
        }
    }
    
    if (window)
    {
        NSInteger result = NSAlertErrorReturn;

        // FOCUS MANAGEMENT: Ensure any text fields in the alert receive focus immediately
        // so the cursor blinks and keyboard input works without clicking.
        NSView *contentView = [window contentView];
        if (contentView)
        {
            NSArray *subviews = [contentView subviews];
            NSTextField *firstTextField = nil;
            
            // Search for the first editable text field in the alert
            for (NSView *view in subviews)
            {
                if ([view isKindOfClass:[NSTextField class]])
                {
                    NSTextField *textField = (NSTextField *)view;
                    if ([textField isEditable])
                    {
                        firstTextField = textField;
                        NSDebugLog(@"NSAlert+Eau: Found editable text field %p in alert", textField);
                        break;
                    }
                }
            }
            
            // Set initial first responder to enable immediate keyboard input
            if (firstTextField)
            {
                NSDebugLog(@"NSAlert+Eau: Setting initial first responder to text field %p", firstTextField);
                [window setInitialFirstResponder: firstTextField];
            }
            else
            {
                NSDebugLog(@"NSAlert+Eau: No editable text field found in alert");
            }
        }
        
        // CRITICAL: Make the alert window key so it receives keyboard input immediately.
        // Without this, the alert appears but doesn't have focus - user must click it.
        NSDebugLog(@"NSAlert+Eau: Activating app and making alert window key for immediate input");
        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        NSDebugLog(@"NSAlert+Eau: Alert window is now key: %d", [window isKeyWindow]);

        if ([window isKindOfClass: [EauAlertPanel class]])
        {
            EauAlertPanel *panel = (EauAlertPanel *)window;
            result = [panel runModal];
        }
        else
        {
            [NSApp activateIgnoringOtherApps: YES];
            [window center];
            [window orderFrontRegardless];
            [window makeKeyAndOrderFront: nil];
            
            NSDebugLog(@"Eau: NSAlert running modal for window: %@", window);
            [NSApp runModalForWindow: window];
            if ([window respondsToSelector: @selector(result)])
            {
                result = [(EauAlertPanel *)window result];
            }
        }

        [window orderOut: self];

        // Store result via KVC if possible
        @try {
            [self setValue: @(result) forKey: @"_result"];
        }
        @catch (NSException *exception) {
            // Ignore if ivar doesn't exist
        }

        // Defer cleanup to ensure NSAlert stays alive until it's done. 
        // Using performSelector with modes ensures this runs even if we are still
        // in a modal session (nested modals).
        [self performSelector: @selector(eau_cleanupPanel)
                   withObject: nil
                   afterDelay: 0.1
                      inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];

        return result;
    }
    
    // Fallback: if window creation failed, return failure
    // NSLog(@"Eau: NSAlert eau_runModal - window was nil, returning NSAlertFirstButtonReturn");
    return NSAlertFirstButtonReturn;
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: FATAL EXCEPTION in eau_runModal: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
        return NSAlertErrorReturn;
    }
}

// Cleanup helper to clear NSAlert's window after modal teardown.
- (void)eau_cleanupPanel
{
    // NSLog(@"Eau: eau_cleanupPanel called for NSAlert %p", self);
    Ivar windowIvar = class_getInstanceVariable([self class], "_window");
    if (windowIvar)
    {
        // Check current value
        id currentWindow = object_getIvar(self, windowIvar);
        if (currentWindow) {
            // NSLog(@"Eau: Cleaning up window %p before release", currentWindow);
            @try {
                // Ensure pulse animation and delegate are cleared while window is still alive
                if ([currentWindow respondsToSelector: @selector(setDefaultButtonCell:)]) {
                    [currentWindow setDefaultButtonCell: nil];
                }
                if ([currentWindow respondsToSelector: @selector(setDelegate:)]) {
                    [currentWindow setDelegate: nil];
                }
            } @catch (NSException *e) {
                // NSLog(@"Eau: Exception during window cleanup: %@", e);
            }

            // NSLog(@"Eau: Clearing _window ivar on NSAlert (keeping associated object to prevent premature dealloc)");
            object_setIvar(self, windowIvar, nil);
            // IMPORTANT: Do NOT release the associated object here.  The _window ivar
            // in GNUstep's NSAlert is __weak, so the associated object with
            // OBJC_ASSOCIATION_RETAIN_NONATOMIC is the ONLY strong reference keeping
            // the EauAlertPanel alive.  Releasing it here triggers -dealloc while the
            // window system (DPS/X11 backend) may still have pending operations or
            // references to the panel, causing a crash (segfault) after dealloc
            // completes.  The associated object will be automatically released when
            // NSAlert itself is deallocated, which is a safe time for the panel to die.
            //
            // The panel is fully inert at this point (no delegate, no animation, ordered
            // out) so keeping it alive until NSAlert deallocates is safe and prevents
            // the use-after-free crash.
        }
    }
    else
    {
        // NSLog(@"Eau: _window ivar not found during cleanup, trying KVC");
        @try {
            [self setValue: nil forKey: @"_window"];
            // Also keep the associated object here for the same reason as above.
        }
        @catch (NSException *exception) {
            // Ignore if ivar doesn't exist
        }
    }
}

// Replacement for NSAlert's _setupPanel method
// Builds a themed EauAlertPanel and assigns it to NSAlert's _window ivar.
- (void) eau_setupPanel
{
    // NSLog(@"Eau: eau_setupPanel called for NSAlert");
    
    EauAlertPanel *panel;
    NSString *title;
    
    @try {
    // NSLog(@"Eau: Creating EauAlertPanel");
    panel = [[EauAlertPanel alloc] init];
    if (panel == nil)
    {
        NSLog(@"Eau: CRITICAL - EauAlertPanel init returned nil");
        return;
    }
    // NSLog(@"Eau: EauAlertPanel created successfully: %@", panel);
    
    // Access NSAlert's ivars through KVC or accessor methods
    // NSLog(@"Eau: Accessing NSAlert properties");
    NSAlertStyle style = NSWarningAlertStyle;
    NSString *messageText = nil;
    NSString *informativeText = nil;
    NSImage *icon = nil;
    NSArray *buttons = nil;
    
    @try {
        style = [self alertStyle];
        // NSLog(@"Eau: alertStyle: %ld", (long)style);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting alertStyle: %@", e);
    }
    
    @try {
        messageText = [self messageText];
        // NSLog(@"Eau: messageText: %@", messageText);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting messageText: %@", e);
    }
    
    @try {
        informativeText = [self informativeText];
        // NSLog(@"Eau: informativeText: %@", informativeText);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting informativeText: %@", e);
    }
    
    @try {
        icon = [self icon];
        // NSLog(@"Eau: icon: %@", icon);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting icon: %@", e);
    }
    
    @try {
        buttons = [self buttons];
        // NSLog(@"Eau: buttons count: %lu", (unsigned long)[buttons count]);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting buttons: %@", e);
    }
    
    // Set default icons based on alert style if no custom icon is provided
    if (icon == nil)
    {
        // NSLog(@"Eau: No icon provided, using default for style %ld", (long)style);
        @try {
            switch (style)
            {
                case NSCriticalAlertStyle:
                    icon = [NSImage imageNamed: @"GSStop"];
                    break;
                case NSInformationalAlertStyle:
                    // No default icon for informational alerts
                    break;
                case NSWarningAlertStyle:
                default:
                    icon = [NSImage imageNamed: @"NSCaution"];
                    break;
            }
            // if (icon != nil)
            //     NSLog(@"Eau: Loaded default icon: %@", icon);
        } @catch (NSException *e) {
            // NSLog(@"Eau: Exception loading default icon: %@", e);
        }
    }
    
    switch (style)
    {
        case NSCriticalAlertStyle:
            title = @"";
            break;
        case NSInformationalAlertStyle:
            title = @"";
            break;
        case NSWarningAlertStyle:
        default:
            title = @"";
            break;
    }
    
    if (messageText == nil) {
        NSLog(@"Eau: NSAlert with nil messageText (title will be \"Alert\") — informativeText=%@, self=%@",
              informativeText, self);
    }
    @try {
        [panel setTitleBar: title
                      icon: icon
                     title: messageText != nil ? messageText : @"Alert"
                   message: informativeText != nil ? informativeText : @""];
        // NSLog(@"Eau: setTitleBar completed");
    } @catch (NSException *e) {
        NSLog(@"Eau: EXCEPTION in setTitleBar: %@", e);
    }
    
    @try {
        if ([buttons count] == 0)
        {
            // NSLog(@"Eau: No buttons, adding default OK button");
            [self addButtonWithTitle: @"OK"];
            buttons = [self buttons];
        }
        
        // NSLog(@"Eau: Setting %lu buttons on panel", (unsigned long)[buttons count]);
        [panel setButtons: buttons];
        // NSLog(@"Eau: setButtons completed");
    } @catch (NSException *e) {
        NSLog(@"Eau: EXCEPTION in setButtons: %@", e);
    }
    
    // Set the _window ivar directly when possible to avoid KVC retain/release side effects
    // NSLog(@"Eau: Setting _window ivar on NSAlert");
    {
        Ivar windowIvar = class_getInstanceVariable([self class], "_window");
        if (windowIvar)
        {
            object_setIvar(self, windowIvar, panel);
            objc_setAssociatedObject(self, kEAUAlertWindowRetainKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            // NSLog(@"Eau: Successfully set _window via ivar");
        }
        else
        {
            @try {
                [self setValue: panel forKey: @"_window"];
                // NSLog(@"Eau: Successfully set _window via KVC");
            }
            @catch (NSException *exception) {
                NSLog(@"Eau: CRITICAL - could not set _window ivar on NSAlert: %@", exception);
            }
        }
    }
    
    // NSLog(@"Eau: eau_setupPanel completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: FATAL EXCEPTION in eau_setupPanel: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

@end
