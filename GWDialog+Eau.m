#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Eau.h"
#import "AppearanceMetrics.h"

@interface GWDialog : NSWindow
@end

@interface GWDialogView : NSView
@end

@interface NSWindow (EauDialogServices)
- (id)eau_validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType;
@end

@interface GWDialog (EauInit)
- (id)eau_initWithTitle: (NSString *)title
          editText: (NSString *)eText
        switchTitle: (NSString *)swTitle __attribute__((objc_method_family(init)));
@end


// Helper to access ivars from GWDialog/GWDialogView safely via runtime.
static id EAUGetIvarObject(id obj, const char *name)
{
  Ivar ivar = class_getInstanceVariable([obj class], name);
  if (ivar == NULL)
    {
      return nil;
    }
  return object_getIvar(obj, ivar);
}

// Apply AppearanceMetrics layout and Mac-like dialog behavior for GWDialog.
static void EAULayoutGWDialog(GWDialog *dialog)
{
  NSView *dialogView = (NSView *)EAUGetIvarObject(dialog, "dialogView");
  NSTextField *titleField = (NSTextField *)EAUGetIvarObject(dialog, "titleField");
  NSTextField *editField = (NSTextField *)EAUGetIvarObject(dialog, "editField");
  NSButton *switchButt = (NSButton *)EAUGetIvarObject(dialog, "switchButt");
  NSButton *cancelButt = (NSButton *)EAUGetIvarObject(dialog, "cancelButt");
  NSButton *okButt = (NSButton *)EAUGetIvarObject(dialog, "okButt");

  if (dialogView == nil || titleField == nil || editField == nil
      || cancelButt == nil || okButt == nil)
    {
      return;
    }

  BOOL useSwitch = (switchButt != nil);

  [titleField setFont: METRICS_FONT_SYSTEM_BOLD_13];
  [titleField setEditable: NO];
  [titleField setSelectable: NO];
  [titleField setBezeled: NO];
  [titleField setDrawsBackground: NO];
  [titleField setAlignment: NSLeftTextAlignment];

  [editField setFont: METRICS_FONT_SYSTEM_REGULAR_13];

  if (switchButt != nil)
    {
      [switchButt setFont: METRICS_FONT_SYSTEM_REGULAR_13];
    }

  [cancelButt setFont: METRICS_FONT_SYSTEM_REGULAR_13];
  [okButt setFont: METRICS_FONT_SYSTEM_BOLD_13];

  [cancelButt sizeToFit];
  [okButt sizeToFit];

  NSSize cancelSize = [cancelButt frame].size;
  NSSize okSize = [okButt frame].size;

  cancelSize.width = MAX(METRICS_BUTTON_MIN_WIDTH, cancelSize.width);
  okSize.width = MAX(METRICS_BUTTON_MIN_WIDTH, okSize.width);
  cancelSize.height = METRICS_BUTTON_HEIGHT;
  okSize.height = METRICS_BUTTON_HEIGHT;

  CGFloat minButtonRowWidth = cancelSize.width + okSize.width + METRICS_BUTTON_HORIZ_INTERSPACE;
  CGFloat contentWidth = MAX([dialogView frame].size.width,
                             METRICS_CONTENT_SIDE_MARGIN * 2 + minButtonRowWidth);

  NSSize titleSize = [[titleField cell] cellSize];
  CGFloat titleHeight = MAX(titleSize.height, 18.0);
  CGFloat switchHeight = METRICS_RADIO_BUTTON_SIZE;

  CGFloat y = METRICS_CONTENT_BOTTOM_MARGIN;
  CGFloat buttonY = y;
  y += METRICS_BUTTON_HEIGHT;

  CGFloat switchY = 0.0;
  if (useSwitch)
    {
      y += METRICS_SPACE_16;
      switchY = y;
      y += switchHeight;
    }

  y += METRICS_SPACE_16;
  CGFloat editY = y;
  y += METRICS_TEXT_INPUT_FIELD_HEIGHT;

  y += METRICS_SPACE_12;
  CGFloat titleY = y;
  y += titleHeight;

  y += METRICS_CONTENT_TOP_MARGIN;
  CGFloat contentHeight = y;

  [dialogView setFrame: NSMakeRect(0.0, 0.0, contentWidth, contentHeight)];
  [dialog setContentSize: NSMakeSize(contentWidth, contentHeight)];

  CGFloat x = METRICS_CONTENT_SIDE_MARGIN;
  CGFloat width = contentWidth - (METRICS_CONTENT_SIDE_MARGIN * 2);

  [titleField setFrame: NSMakeRect(x, titleY, width, titleHeight)];
  [editField setFrame: NSMakeRect(x, editY, width, METRICS_TEXT_INPUT_FIELD_HEIGHT)];

  if (useSwitch)
    {
      [switchButt setFrame: NSMakeRect(x, switchY, width, switchHeight)];
    }

  CGFloat okX = contentWidth - METRICS_CONTENT_SIDE_MARGIN - okSize.width;
  CGFloat cancelX = okX - METRICS_BUTTON_HORIZ_INTERSPACE - cancelSize.width;

  [cancelButt setFrame: NSMakeRect(cancelX, buttonY, cancelSize.width, cancelSize.height)];
  [okButt setFrame: NSMakeRect(okX, buttonY, okSize.width, okSize.height)];

  /* Configure button behavior for proper keyboard interaction.
     OK button should respond to Enter and be the default (pulsating) button.
     Cancel button should respond to Escape. This must be done carefully
     to avoid interfering with the existing target/action setup. */
  
  NSDebugLog(@"EauDialog: Configuring button key equivalents and default button");
  
  // Verify buttons exist and have proper targets/actions before modifying
  if (okButt && [okButt target] && [okButt action])
    {
      NSDebugLog(@"EauDialog: OK button has target %@ and action %@", 
             [okButt target], NSStringFromSelector([okButt action]));
      
      // Set Enter key to trigger OK button
      [okButt setKeyEquivalent: @"\r"];
      [okButt setKeyEquivalentModifierMask: 0];
      NSDebugLog(@"EauDialog: Set OK button key equivalent to Enter");
      
      // Mark OK as the default button - this triggers pulsating animation
      NSButtonCell *okCell = [okButt cell];
      if (okCell)
        {
          [dialog setDefaultButtonCell: okCell];
          NSDebugLog(@"EauDialog: Set OK button cell %@ as default button", okCell);
        }
      else
        {
          NSDebugLog(@"EauDialog: WARNING - OK button has no cell, cannot set as default");
        }
    }
  else
    {
      NSDebugLog(@"EauDialog: WARNING - OK button missing target or action, not setting key equivalent");
    }
  
  if (cancelButt && [cancelButt target] && [cancelButt action])
    {
      NSDebugLog(@"EauDialog: Cancel button has target %@ and action %@",
             [cancelButt target], NSStringFromSelector([cancelButt action]));
      
      // Set Escape key to trigger Cancel button
      [cancelButt setKeyEquivalent: @"\e"];
      [cancelButt setKeyEquivalentModifierMask: 0];
      NSDebugLog(@"EauDialog: Set Cancel button key equivalent to Escape");
    }
  else
    {
      NSDebugLog(@"EauDialog: WARNING - Cancel button missing target or action, not setting key equivalent");
    }

  // Set up key view loop for tab navigation.
  // This enables the Tab key to cycle through: editField -> okButt -> cancelButt -> editField
  [editField setNextKeyView: okButt];
  [okButt setNextKeyView: cancelButt];
  [cancelButt setNextKeyView: editField];
  NSDebugLog(@"EauDialog: Configured key view loop for tab navigation");

  // Set initial first responder to the edit field for immediate keyboard input.
  // This ensures the text field gets focus automatically when the dialog opens,
  // so the cursor blinks and the user can type immediately without clicking.
  // This is now safe because we don't set a problematic delegate on GWDialog
  // (see NSWindow+Eau.m eau_setDefaultButtonCell for delegate handling).
  [dialog setInitialFirstResponder: editField];
  NSDebugLog(@"EauDialog: Set initial first responder to edit field %p", editField);

  // Position dialog using golden ratio centering.
  [dialog center];

  // Log dialog content for diagnostics.
  NSDebugLog(@"EauDialog: GWDialog layout title='%@' edit='%@' switch='%@'", 
         [titleField stringValue],
         [(id)editField string],
         (switchButt != nil) ? [switchButt title] : @"");
}
/* GWDialog (Eau) Category
 * 
 * Eau theme customization for GWDialog modal dialogs.
 * 
 * WHAT THIS DOES:
 * - Swizzles GWDialog's initWithTitle:editText:switchTitle: to apply Eau layout
 * - Adjusts dialog geometry and button placement per Eau design metrics
 * - Configures keyboard shortcuts: Enter for OK, Escape for Cancel
 * - Sets up default button for pulsating animation
 * - Ensures text field receives focus immediately when dialog opens
 * - Establishes tab navigation order: text field → OK → Cancel → text field
 * 
 * WHY WE DO THIS:
 * - Users expect to type immediately when a dialog appears (no click required)
 * - Enter key should activate the default (OK) button
 * - Escape key should activate the Cancel button
 * - Tab key should navigate between controls
 * - Default button should pulse to show it's the primary action
 * 
 * FOCUS MANAGEMENT STRATEGY:
 * The text field is set as initialFirstResponder in EAULayoutGWDialog().
 * This works safely because:
 * 1. We don't set a delegate on GWDialog windows (see NSWindow+Eau.m)
 * 2. The DefaultButtonAnimationController implements windowWillReturnFieldEditor:toObject:
 * 3. This prevents objc_msgSend_stret crashes on ARM64 when field editor is requested
 * 
 * DELEGATE HANDLING:
 * GWDialog windows specifically DO NOT get a delegate set in NSWindow+Eau.m
 * eau_setDefaultButtonCell(). This is intentional to avoid field editor issues.
 * The animation controller still works via NSNotificationCenter.
 */@implementation GWDialog (Eau)

+ (void)load
{
  Class dialogClass = NSClassFromString(@"GWDialog");
  if (dialogClass == nil)
    {
      return;
    }

  Method originalInit = class_getInstanceMethod(dialogClass,
                                                @selector(initWithTitle:editText:switchTitle:));
  Method eauInit = class_getInstanceMethod(dialogClass,
                                           @selector(eau_initWithTitle:editText:switchTitle:));
  if (originalInit && eauInit)
    {
      method_exchangeImplementations(originalInit, eauInit);
    }

  // Swizzle runModal to ensure window activation and keyboard focus
  Method originalRunModal = class_getInstanceMethod(dialogClass, @selector(runModal));
  Method eauRunModal = class_getInstanceMethod(dialogClass, @selector(eau_runModal));
  if (originalRunModal && eauRunModal)
    {
      method_exchangeImplementations(originalRunModal, eauRunModal);
      NSDebugLog(@"GWDialog+Eau: Swizzled runModal for focus management");
    }

  // Swizzle NSWindow validRequestorForSendType:returnType: to avoid crashes
  // when services menu validates while GWDialog is modal.
  Class windowClass = [NSWindow class];
  Method origValid = class_getInstanceMethod(windowClass, @selector(validRequestorForSendType:returnType:));
  Method eauValid = class_getInstanceMethod(windowClass, @selector(eau_validRequestorForSendType:returnType:));
  if (origValid && eauValid)
    {
      method_exchangeImplementations(origValid, eauValid);
    }

  /* keyDown swizzle removed - key equivalents are set directly on buttons
     via setKeyEquivalent: in EAULayoutGWDialog, which is the proper way
     to handle Enter and Escape keys. */
}

/* eau_initWithTitle:editText:switchTitle:
 * Swizzled initializer for GWDialog that applies Eau theme layout.
 * Called instead of the original initWithTitle:editText:switchTitle:.
 * Performs layout adjustments, sets up keyboard shortcuts (Enter/Escape),
 * configures the default button for pulsating animation, and ensures
 * proper focus management so the text field is immediately ready for input.
 */
- (id)eau_initWithTitle: (NSString *)title
               editText: (NSString *)eText
            switchTitle: (NSString *)swTitle
{
  NSDebugLog(@"EauDialog: Eau-themed init starting for title='%@'", title);
  
  // Call the original implementation (which is now named eau_initWithTitle due to swizzling)
  id dialog = [self eau_initWithTitle: title editText: eText switchTitle: swTitle];
  if (dialog != nil)
    {
      NSDebugLog(@"EauDialog: Original init completed, applying Eau layout and focus setup");
      EAULayoutGWDialog((GWDialog *)dialog);
      NSDebugLog(@"EauDialog: Initialization complete for dialog %p", dialog);
    }
  return dialog;
}

/* eau_runModal
 * Swizzled runModal method that ensures proper window activation and focus.
 * 
 * CRITICAL FOR INPUT FOCUS:
 * The original GWDialog runModal just calls [NSApp runModalForWindow:self].
 * This is not enough - the window appears but doesn't become key, so it
 * doesn't receive keyboard input. User has to click to give it focus.
 * 
 * We fix this by:
 * 1. Activating the application (brings it to front)
 * 2. Making the dialog window key (gives it keyboard focus)
 * 3. Then running the modal loop
 * 
 * This ensures the text field cursor blinks immediately and keyboard works.
 */
- (NSModalResponse)eau_runModal
{
  NSDebugLog(@"GWDialog: eau_runModal called - activating app and making window key");
  
  // Activate the application to bring it to front
  [[NSApplication sharedApplication] activateIgnoringOtherApps: YES];
  
  // Make this dialog the key window so it receives keyboard input
  [self makeKeyAndOrderFront: nil];
  
  NSDebugLog(@"GWDialog: Window is now key: %d, first responder: %@", 
         [self isKeyWindow], [[self firstResponder] class]);
  
  // Abort modal if window is force-closed externally
  __block id closeObs = [[NSNotificationCenter defaultCenter]
    addObserverForName: NSWindowWillCloseNotification
    object: self queue: nil usingBlock: ^(NSNotification *note) {
      /* Closing must always end the modal session, even for a wedged app */
      @try {
        [NSApp abortModal];
      } @catch (id ex) {}
    }];
  
  // Call the original runModal (which is now named eau_runModal due to swizzling)
  NSModalResponse result = [self eau_runModal];
  
  [[NSNotificationCenter defaultCenter] removeObserver: closeObs];
  return result;
}

@end

@implementation NSWindow (EauDialogServices)

- (id)eau_validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
  if ([self isKindOfClass: NSClassFromString(@"GWDialog")])
    {
      return nil;
    }
  return [self eau_validRequestorForSendType: sendType returnType: returnType];
}

@end

@implementation GWDialogView (Eau)

+ (void)load
{
  Class viewClass = NSClassFromString(@"GWDialogView");
  if (viewClass == nil)
    {
      return;
    }

  Method originalDraw = class_getInstanceMethod(viewClass, @selector(drawRect:));
  Method eauDraw = class_getInstanceMethod(viewClass, @selector(eau_drawRect:));
  if (originalDraw && eauDraw)
    {
      method_exchangeImplementations(originalDraw, eauDraw);
    }
}

- (void)eau_drawRect:(NSRect)rect
{
  [[NSColor windowBackgroundColor] setFill];
  NSRectFill(rect);
}

@end
