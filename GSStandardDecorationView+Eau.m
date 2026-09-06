#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSTheme.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#import "Eau.h"
#import "EauTitleBarButton.h"
#import "EauWindowButton.h"
#import "Eau+TitleBarButtons.h"
#import "AppearanceMetrics.h"

// Associated object keys for zoom button support
static char hasZoomButtonKey;
static char zoomButtonKey;
static char zoomButtonRectKey;
static char originalFrameKey;  // Store original frame before zoom
@interface GSStandardWindowDecorationView(EauTheme)
- (void) EAUupdateRects;
- (BOOL) hasZoomButton;
- (void) setHasZoomButton:(BOOL)flag;
- (NSButton *) zoomButton;
- (void) setZoomButton:(NSButton *)button;
- (NSRect) zoomButtonRect;
- (void) EAUzoomButtonClicked:(id)sender;
@end

@implementation Eau(GSStandardWindowDecorationView)
- (void) _overrideGSStandardWindowDecorationViewMethod_updateRects {
  GSStandardWindowDecorationView* xself = (GSStandardWindowDecorationView*)self;
  NSDebugLog(@"GSStandardDecorationView+Eau updateRects");
  [xself EAUupdateRects];
}
@end

@implementation GSStandardWindowDecorationView(EauTheme)
- (void) EAUupdateRects
{
  GSTheme *theme = [GSTheme theme];
  CGFloat viewWidth = [self bounds].size.width;
  CGFloat viewHeight = [self bounds].size.height;
  BOOL isOrb = EauTitleBarButtonStyleIsOrb();

  // Initialize zoom button if not already done (only for resizable windows)
  NSUInteger styleMask = [[self window] styleMask];
  NSDebugLog(@"Checking zoom button creation: hasZoomButton=%d, hasTitleBar=%d, resizable=%d", [self hasZoomButton], hasTitleBar, (int)(styleMask & NSResizableWindowMask));
  if (![self hasZoomButton] && hasTitleBar && (styleMask & NSResizableWindowMask)) {
    NSDebugLog(@"Creating zoom button for window decoration view");
    NSButton *zButton;
    if (isOrb) {
      EauWindowButton *orbButton = [[EauWindowButton alloc] init];
      [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.322 green:0.778 blue:0.244 alpha:1]];
      [orbButton setRefusesFirstResponder: YES];
      [orbButton setButtonType: NSMomentaryChangeButton];
      [orbButton setImagePosition: NSImageOnly];
      [orbButton setBordered: YES];
      [orbButton setTag: NSWindowZoomButton];
      [orbButton setImage: [NSImage imageNamed: @"common_Zoom"]];
      [orbButton setAlternateImage: [NSImage imageNamed: @"common_ZoomH"]];
      zButton = orbButton;
    } else {
      zButton = [EauTitleBarButton maximizeButton];
    }
    if (zButton) {
      NSDebugLog(@"Zoom button created successfully, setting up target and action");
      [self setZoomButton:zButton];
      [zButton setTarget:self];
      [zButton setAction:@selector(EAUzoomButtonClicked:)];
      [zButton setEnabled:YES];
      [self addSubview:zButton];
      [self setHasZoomButton:YES];
      NSDebugLog(@"Zoom button target: %@, action: %@, window: %@", [zButton target], NSStringFromSelector([zButton action]), window);
    } else {
      NSDebugLog(@"Failed to create zoom button - zButton is nil");
    }
  }

  if (hasTitleBar)
    {
      CGFloat titleHeight = METRICS_TITLEBAR_HEIGHT;
      titleBarRect = NSMakeRect(0.0, viewHeight - titleHeight,
                            viewWidth, titleHeight);
    }
  if (hasResizeBar)
    {
      resizeBarRect = NSMakeRect(0.0, 0.0, viewWidth, [theme resizebarHeight]);
    }

  CGFloat titleBarY = viewHeight - METRICS_TITLEBAR_HEIGHT;

  if (isOrb) {
    // Orb style: all 3 buttons on left, 15x15, vertically centered
    CGFloat buttonY = titleBarY + (METRICS_TITLEBAR_HEIGHT - METRICS_TITLEBAR_ORB_BUTTON_SIZE) / 2.0;
    CGFloat x = METRICS_TITLEBAR_ORB_PADDING_LEFT;

    if (hasCloseButton)
    {
      closeButtonRect = NSMakeRect(x, buttonY,
        METRICS_TITLEBAR_ORB_BUTTON_SIZE, METRICS_TITLEBAR_ORB_BUTTON_SIZE);
      [closeButton setFrame: closeButtonRect];
      x += METRICS_TITLEBAR_ORB_BUTTON_SIZE + METRICS_TITLEBAR_ORB_BUTTON_SPACING;
    }

    if (hasMiniaturizeButton)
    {
      miniaturizeButtonRect = NSMakeRect(x, buttonY,
        METRICS_TITLEBAR_ORB_BUTTON_SIZE, METRICS_TITLEBAR_ORB_BUTTON_SIZE);
      [miniaturizeButton setFrame: miniaturizeButtonRect];
      x += METRICS_TITLEBAR_ORB_BUTTON_SIZE + METRICS_TITLEBAR_ORB_BUTTON_SPACING;
    }

    if ([self hasZoomButton])
    {
      NSRect zoomRect = NSMakeRect(x, buttonY,
        METRICS_TITLEBAR_ORB_BUTTON_SIZE, METRICS_TITLEBAR_ORB_BUTTON_SIZE);

      NSValue *rectValue = [NSValue valueWithRect:zoomRect];
      objc_setAssociatedObject(self, &zoomButtonRectKey, rectValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

      NSButton *zoomButton = [self zoomButton];
      if (zoomButton) {
        [zoomButton setTarget:self];
        [zoomButton setAction:@selector(EAUzoomButtonClicked:)];
        [zoomButton setFrame: zoomRect];
        [zoomButton setEnabled: YES];
        [zoomButton setHidden: NO];
        [zoomButton setNeedsDisplay: YES];
        if ([zoomButton superview] != self) {
          [self addSubview: zoomButton];
        }
      }
    }
  } else {
    // Edge style: close on left, minimize+maximize on right

    // Close button at left edge, full titlebar height
    if (hasCloseButton)
    {
      closeButtonRect = NSMakeRect(
        0,
        titleBarY,
        METRICS_TITLEBAR_HEIGHT, METRICS_TITLEBAR_HEIGHT);
      [closeButton setFrame: closeButtonRect];

      if ([closeButton isKindOfClass:[EauTitleBarButton class]]) {
        [(EauTitleBarButton *)closeButton setTitleBarButtonType:EauTitleBarButtonTypeClose];
        [(EauTitleBarButton *)closeButton setTitleBarButtonPosition:EauTitleBarButtonPositionLeft];
      }
    }

    // Miniaturize button - position depends on whether zoom button exists
    if (hasMiniaturizeButton)
    {
      CGFloat x;
      EauTitleBarButtonPosition position;
      if ([self hasZoomButton]) {
        x = viewWidth - 2 * METRICS_TITLEBAR_HEIGHT;
        position = EauTitleBarButtonPositionRightInner;
      } else {
        x = viewWidth - METRICS_TITLEBAR_HEIGHT;
        position = EauTitleBarButtonPositionRightOuter;
      }
      miniaturizeButtonRect = NSMakeRect(
        x, titleBarY,
        METRICS_TITLEBAR_HEIGHT, METRICS_TITLEBAR_HEIGHT);
      [miniaturizeButton setFrame: miniaturizeButtonRect];

      if ([miniaturizeButton isKindOfClass:[EauTitleBarButton class]]) {
        [(EauTitleBarButton *)miniaturizeButton setTitleBarButtonType:EauTitleBarButtonTypeMinimize];
        [(EauTitleBarButton *)miniaturizeButton setTitleBarButtonPosition:position];
      }
    }

    // Zoom button - outer (rightmost) of two side-by-side buttons on right
    if ([self hasZoomButton])
    {
      CGFloat x = viewWidth - METRICS_TITLEBAR_HEIGHT;
      NSRect zoomButtonRect = NSMakeRect(
        x, titleBarY,
        METRICS_TITLEBAR_HEIGHT, METRICS_TITLEBAR_HEIGHT);

      NSValue *rectValue = [NSValue valueWithRect:zoomButtonRect];
      objc_setAssociatedObject(self, &zoomButtonRectKey, rectValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

      NSButton *zoomButton = [self zoomButton];
      if (zoomButton) {
        NSDebugLog(@"Updating zoom button frame: %@", NSStringFromRect(zoomButtonRect));

        [zoomButton setTarget:self];
        [zoomButton setAction:@selector(EAUzoomButtonClicked:)];
        [zoomButton setFrame: zoomButtonRect];
        [zoomButton setEnabled: YES];
        [zoomButton setHidden: NO];
        [zoomButton setNeedsDisplay: YES];

        if ([zoomButton isKindOfClass:[EauTitleBarButton class]]) {
          [(EauTitleBarButton *)zoomButton setTitleBarButtonType:EauTitleBarButtonTypeMaximize];
          [(EauTitleBarButton *)zoomButton setTitleBarButtonPosition:EauTitleBarButtonPositionRightOuter];
        }

        if ([zoomButton superview] != self) {
          [self addSubview: zoomButton];
        }
      }
    }
  }

}

// Zoom button property implementations
- (BOOL) hasZoomButton
{
  NSNumber *hasZoomButtonNum = objc_getAssociatedObject(self, &hasZoomButtonKey);
  return hasZoomButtonNum ? [hasZoomButtonNum boolValue] : NO;
}

- (void) setHasZoomButton:(BOOL)flag
{
  NSNumber *hasZoomButtonNum = [NSNumber numberWithBool:flag];
  objc_setAssociatedObject(self, &hasZoomButtonKey, hasZoomButtonNum, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSButton *) zoomButton
{
  return objc_getAssociatedObject(self, &zoomButtonKey);
}

- (void) setZoomButton:(NSButton *)button
{
  objc_setAssociatedObject(self, &zoomButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSRect) zoomButtonRect
{
  NSValue *rectValue = objc_getAssociatedObject(self, &zoomButtonRectKey);
  return rectValue ? [rectValue rectValue] : NSZeroRect;
}

- (void) EAUzoomButtonClicked:(id)sender
{
  NSDebugLog(@"*** ZOOM BUTTON CLICKED! sender: %@, window: %@", sender, window);
  NSDebugLog(@"*** Window isZoomed: %d", [window isZoomed]);

  if ([window isZoomed]) {
    // Window is zoomed, manually restore it to original frame
    NSDebugLog(@"*** Window is zoomed, attempting manual unzoom");

    NSValue *originalFrameValue = objc_getAssociatedObject(window, &originalFrameKey);
    if (originalFrameValue) {
      NSRect originalFrame = [originalFrameValue rectValue];
      NSDebugLog(@"*** Restoring window to original frame: %@", NSStringFromRect(originalFrame));
      [window setFrame:originalFrame display:YES animate:NO];

      // Clear the stored frame
      objc_setAssociatedObject(window, &originalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
      NSDebugLog(@"*** No original frame stored, falling back to performZoom");
      [window performZoom:sender];
    }
  } else {
    // Window is not zoomed, store current frame and zoom it
    NSDebugLog(@"*** Window is not zoomed, storing frame and zooming");

    // Store current frame before zooming
    NSRect currentFrame = [window frame];
    NSValue *frameValue = [NSValue valueWithRect:currentFrame];
    objc_setAssociatedObject(window, &originalFrameKey, frameValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDebugLog(@"*** Stored original frame: %@", NSStringFromRect(currentFrame));

    [window zoom:sender];
  }

  NSDebugLog(@"*** After zoom call - Window isZoomed: %d", [window isZoomed]);
}

#pragma mark - Title text truncation

// Helper: create a middle-truncated version of a string for window titles.
// Returns a string with "…" inserted in the middle when the gap between
// the centered title and the nearest button would be less than 24px.
static NSString *EAUTruncateTitleWithMiddleEllipsis(NSString *title,
                                                     CGFloat titleMaxWidth,
                                                     CGFloat interButtonWidth)
{
  if ([title length] == 0 || titleMaxWidth <= 0) return title;

  NSFont *font = [NSFont systemFontOfSize:0];
  NSDictionary *attrs = @{ NSFontAttributeName: font };

  CGFloat titleWidth = [title sizeWithAttributes:attrs].width;
  // Only truncate when gap between centered title and nearest button < 24px
  CGFloat gap = (interButtonWidth - titleWidth) / 2.0;
  if (gap >= 24.0) return title;

  // Need middle ellipsis — split the string into left/right parts.
  // Binary search for the maximum prefix+middle+suffix that fits.
  NSString *ellipsis = @"\xe2\x80\xa6"; // Unicode HORIZONTAL ELLIPSIS (…)

  NSUInteger len = [title length];
  NSUInteger lo = 0, hi = len - 1;

  while (lo < hi) {
    NSUInteger leftLen = (lo + hi + 1) / 2;
    NSUInteger rightLen = leftLen;
    if (leftLen + rightLen + 1 > len) rightLen = len - leftLen;
    if (leftLen + rightLen < 2) { hi = leftLen - 1; continue; }

    NSString *leftPart = [title substringToIndex:leftLen];
    NSString *rightPart = [title substringFromIndex:len - rightLen];
    NSString *candidate = [NSString stringWithFormat:@"%@%@%@",
                            leftPart, ellipsis, rightPart];
    CGFloat w = [candidate sizeWithAttributes:attrs].width;
    if (w <= titleMaxWidth) {
      lo = leftLen;
    } else {
      hi = leftLen - 1;
    }
  }

  // Build final truncated string
  NSUInteger bestLeft = lo;
  NSUInteger bestRight = lo;
  if (bestLeft + bestRight + 1 > len) bestRight = len - bestLeft;
  if (bestLeft < 1 || bestRight < 1) {
    // Fallback: show ellipsis with first and last character
    bestLeft = 1;
    bestRight = 1;
  }

  NSString *leftPart = [title substringToIndex:bestLeft];
  NSString *rightPart = [title substringFromIndex:len - bestRight];
  return [NSString stringWithFormat:@"%@%@%@", leftPart, ellipsis, rightPart];
}

@end

// Original setTitle: IMP saved before swizzling
static IMP _originalNSWindowSetTitle = NULL;

// Swizzled setTitle: implementation
static void EAU_newNSWindowSetTitle(id self, SEL _cmd, NSString *title)
{
  if (title != nil && [title length] > 0)
    {
      NSRect frame = [self frame];
      NSUInteger styleMask = [self styleMask];
      CGFloat availableWidth = frame.size.width;

      // Subtract left/right decoration offsets
      float leftOff = 0, rightOff = 0, topOff = 0, bottomOff = 0;
      id server = GSCurrentServer();
      if ([server respondsToSelector: NSSelectorFromString(@"styleoffsets::::")])
        {
          IMP imp = [server methodForSelector: NSSelectorFromString(@"styleoffsets::::")];
          if (imp)
            {
              ((void (*)(id, SEL, float*, float*, float*, float*))imp)
                (server, NSSelectorFromString(@"styleoffsets::::"),
                 &leftOff, &rightOff, &topOff, &bottomOff);
            }
        }
      availableWidth -= (leftOff + rightOff);

      // Subtract space for title bar buttons
      CGFloat buttonSpace = 0;
      if (styleMask & NSClosableWindowMask)
        buttonSpace += METRICS_TITLEBAR_HEIGHT;
      if (styleMask & NSMiniaturizableWindowMask)
        buttonSpace += METRICS_TITLEBAR_HEIGHT;
      if (styleMask & NSResizableWindowMask)
        buttonSpace += METRICS_TITLEBAR_HEIGHT;
      availableWidth -= buttonSpace + 36;

      if (availableWidth > 0)
        {
          // Calculate inter-button width for gap-based truncation decision
          CGFloat interButtonWidth = availableWidth + 36;
          // Let the truncated title fill the inter-button space minus 24px on each side
          CGFloat titleMaxWidth = interButtonWidth - 48.0;
          NSString *truncated = EAUTruncateTitleWithMiddleEllipsis(title,
                                                                    titleMaxWidth,
                                                                    interButtonWidth);
          if (truncated != title)
            {
              title = truncated;
            }
        }
    }

  // Call the original setTitle:
  ((void (*)(id, SEL, id))_originalNSWindowSetTitle)(self, @selector(setTitle:), title);
}

@implementation Eau(NSWindowTitle)

+ (void) EAUswizzleNSWindowSetTitle
{
  static BOOL swizzled = NO;
  if (swizzled) return;
  swizzled = YES;

  Method origMethod = class_getInstanceMethod([NSWindow class], @selector(setTitle:));
  if (origMethod)
    {
      _originalNSWindowSetTitle = method_getImplementation(origMethod);
      method_setImplementation(origMethod, (IMP)EAU_newNSWindowSetTitle);
    }
}

// Original +offsets:forStyleMask: IMP saved before swizzling
static IMP _originalGSStandardOffsets = NULL;

// Swizzled +offsets:forStyleMask: implementation.
// GNUstep's stock GSStandardWindowDecorationView reports a 1px frame border
// on every side for titled windows, but the Gershwin window manager frames
// clients flush (clientBorder 0 in compositor mode, _NET_FRAME_EXTENTS is
// {0,0,titleHeight,0}).  That 1px disagreement between GNUstep's frame math
// and the WM's real frame is why a saved window rect drifted by a pixel on
// every open/close cycle.  Zero the side/bottom borders so GNUstep's offsets
// match the WM's real frame exactly.
static void EAU_newGSStandardOffsets(id self, SEL _cmd, float *l, float *r,
                                     float *t, float *b, NSUInteger style)
{
  // Call the original (which sets the titlebar height for titled windows).
  ((void (*)(id, SEL, float*, float*, float*, float*, NSUInteger))_originalGSStandardOffsets)
    (self, _cmd, l, r, t, b, style);

  // Keep the titlebar height (top offset) from the theme; drop the 1px
  // border on the other three sides to match the WM's clientBorder of 0.
  *l = 0.0;
  *r = 0.0;
  *b = 0.0;
}

+ (void) EAUswizzleGSStandardOffsets
{
  static BOOL swizzled = NO;
  if (swizzled) return;
  swizzled = YES;

  // offsets:forStyleMask: is a CLASS method; swizzle the metaclass method.
  Method origMethod = class_getClassMethod([GSStandardWindowDecorationView class],
                                           @selector(offsets:forStyleMask:));
  if (origMethod)
    {
      _originalGSStandardOffsets = method_getImplementation(origMethod);
      method_setImplementation(origMethod, (IMP)EAU_newGSStandardOffsets);
    }
}

@end
