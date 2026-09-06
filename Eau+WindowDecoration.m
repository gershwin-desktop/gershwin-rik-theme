#import "Eau.h"
#import "Eau+TitleBarButtons.h"
#import "AppearanceMetrics.h"

@interface Eau(EauWindowDecoration)

/* Drop the cached title-text attributes so the next render re-prepares them
 * with the current GSScaleFactor. */
- (void)invalidateTitleTextAttributes;

@end

#define RESIZE_HEIGHT 9.0

/* Cached title text attributes for each theme control state (0=active, 1=inactive, 2=main). */
static NSDictionary *titleTextAttributes[3] = {nil, nil, nil};

@implementation Eau(EauWindowDecoration)

- (float) resizebarHeight {
    return 0.0;  // No resize bar
}

- (float) titlebarHeight {
    return METRICS_TITLEBAR_HEIGHT_PX;
}

- (void) drawWindowBackground: (NSRect) frame view: (NSView*) view
{
  NSColor* backgroundColor = [[view window] backgroundColor];
  [backgroundColor setFill];
  NSRectFill(frame);
}

- (void) drawWindowBorder: (NSRect)rect
                withFrame: (NSRect)frame
             forStyleMask: (unsigned int)styleMask
                    state: (int)inputState
                 andTitle: (NSString*)title
{
  if (styleMask & (NSTitledWindowMask | NSClosableWindowMask
                  | NSMiniaturizableWindowMask))
    {
      NSRect titleRect;

      titleRect = NSMakeRect(0.0, frame.size.height - METRICS_TITLEBAR_HEIGHT_PX,
                                frame.size.width, METRICS_TITLEBAR_HEIGHT_PX);

      if (NSIntersectsRect(rect, titleRect))
        [self drawtitleRect: titleRect
              forStyleMask: styleMask
              state: inputState
              andTitle: title];

    }
}


- (void) drawtitleRect: (NSRect)titleRect
             forStyleMask: (unsigned int)styleMask
                    state: (int)inputState
                 andTitle: (NSString*)title
{

  if (!titleTextAttributes[0])
    {
      [self prepareTitleTextAttributes];
    }

  // Map GSThemeControlState to titleTextAttributes index (0=active, 1=inactive, 2=main)
  // GSThemeNormalState=0 → active, GSThemeSelectedState=6 → inactive, anything else → inactive
  int attrIndex = (inputState == 0) ? 0 : 1;

  NSRect workRect;
  CGFloat titlebarWidth = titleRect.size.width;
  BOOL isActive = (inputState == 0);  // 0 = key window (active)

  workRect = titleRect;
  [self drawTitleBarBackground:workRect active:isActive];

  // Draw edge buttons
  if (styleMask & NSClosableWindowMask)
    {
      NSRect closeRect = [self closeButtonRectForTitlebarWidth:titlebarWidth];
      closeRect.origin.y += titleRect.origin.y;
      [self drawCloseButtonInRect:closeRect state:GSThemeNormalState active:isActive];
    }

  if (styleMask & NSMiniaturizableWindowMask)
    {
      NSRect minRect;
      if (EauTitleBarButtonStyleIsOrb() || (styleMask & NSResizableWindowMask)) {
        minRect = [self minimizeButtonRectForTitlebarWidth:titlebarWidth];
      } else {
        // Solo minimize: position at right edge
        minRect = NSMakeRect(titlebarWidth - METRICS_TITLEBAR_HEIGHT_PX, 0,
                             METRICS_TITLEBAR_HEIGHT_PX, METRICS_TITLEBAR_HEIGHT_PX);
      }
      minRect.origin.y += titleRect.origin.y;
      [self drawMinimizeButtonInRect:minRect state:GSThemeNormalState active:isActive];
    }

  if (styleMask & NSResizableWindowMask)
    {
      NSRect zoomRect = [self maximizeButtonRectForTitlebarWidth:titlebarWidth];
      zoomRect.origin.y += titleRect.origin.y;
      [self drawMaximizeButtonInRect:zoomRect state:GSThemeNormalState active:isActive];
    }

  // Draw the title.
  if (styleMask & NSTitledWindowMask)
    {
      NSSize titleSize;
      workRect = titleRect;

      if (EauTitleBarButtonStyleIsOrb()) {
        // Orb style: all buttons on left, reserve orb region
        workRect.origin.x += METRICS_TITLEBAR_ORB_REGION_WIDTH_PX;
        workRect.size.width -= METRICS_TITLEBAR_ORB_REGION_WIDTH_PX;
      } else {
        // Edge style: close on left, minimize+maximize on right
        if (styleMask & NSClosableWindowMask)
          {
            workRect.origin.x += METRICS_TITLEBAR_HEIGHT_PX;
            workRect.size.width -= METRICS_TITLEBAR_HEIGHT_PX;
          }
        if ((styleMask & NSMiniaturizableWindowMask) && (styleMask & NSResizableWindowMask))
          {
            workRect.size.width -= 2 * METRICS_TITLEBAR_HEIGHT_PX;  // two buttons
          }
        else if ((styleMask & NSMiniaturizableWindowMask) || (styleMask & NSResizableWindowMask))
          {
            workRect.size.width -= METRICS_TITLEBAR_HEIGHT_PX;   // one button
          }
      }

      titleSize = [title sizeWithAttributes: titleTextAttributes[attrIndex]];

      // Calculate gap between centered title and nearest button edge
      CGFloat centeredX = titleRect.origin.x + titleRect.size.width / 2.0 - titleSize.width / 2.0;
      CGFloat minX = workRect.origin.x;
      CGFloat maxX = NSMaxX(workRect) - titleSize.width;
      CGFloat titleLeft = MAX(minX, MIN(centeredX, maxX));
      CGFloat leftGap = titleLeft - workRect.origin.x;
      CGFloat rightGap = NSMaxX(workRect) - (titleLeft + titleSize.width);

      // Only use middle ellipsis when gap to nearest button is less than 24px (scaled)
      CGFloat minGap = 24.0 * GSWScaleFactor();
      BOOL useMiddleEllipsis = (leftGap < minGap || rightGap < minGap);

      if (useMiddleEllipsis) {
        // Draw with middle ellipsis — no centering, just fill the available rect
        NSMutableParagraphStyle *p = [[titleTextAttributes[attrIndex] objectForKey:NSParagraphStyleAttributeName] mutableCopy];
        [p setLineBreakMode:NSLineBreakByTruncatingMiddle];
        [p setAlignment:NSCenterTextAlignment];

        NSMutableDictionary *truncAttrs = [titleTextAttributes[attrIndex] mutableCopy];
        [truncAttrs setObject:p forKey:NSParagraphStyleAttributeName];

        workRect.origin.y = NSMidY(workRect) - titleSize.height / 2;
        workRect.size.height = titleSize.height;
        [title drawInRect:workRect withAttributes:truncAttrs];
      } else {
        if (titleSize.width <= workRect.size.width)
          {
            if (EauTitleBarButtonStyleIsOrb()) {
              // Center in full titlebar width, clamp to not overlap orb region
              CGFloat centeredX = titleRect.origin.x + titleRect.size.width / 2.0 - titleSize.width / 2.0;
              workRect.origin.x = MAX(centeredX, titleRect.origin.x + METRICS_TITLEBAR_ORB_REGION_WIDTH_PX);
            } else {
              CGFloat centeredX = titleRect.origin.x + titleRect.size.width / 2.0 - titleSize.width / 2.0;
              CGFloat minX = workRect.origin.x;
              CGFloat maxX = NSMaxX(workRect) - titleSize.width;
              workRect.origin.x = MAX(minX, MIN(centeredX, maxX));
            }
          }
        workRect.origin.y = NSMidY(workRect) - titleSize.height / 2;
        workRect.size.height = titleSize.height;
        [title drawInRect: workRect
            withAttributes: titleTextAttributes[attrIndex]];
      }
    }
}

- (void) drawTitleBarBackground: (NSRect)rect active:(BOOL)isActive {

  NSGradient* gradient;
  CGFloat bottomRowGray;
  NSColor *borderColor;
  if (isActive) {
    gradient = [self _windowTitlebarGradient];
    bottomRowGray = 0.63;
    borderColor = [Eau controlStrokeColor];
  } else {
    gradient = [self _windowTitlebarGradientInactive];
    bottomRowGray = 0.83;
    borderColor = [NSColor colorWithCalibratedRed:0.85 green:0.85 blue:0.85 alpha:1.0];
  }

  CGFloat titleBarCornerRadius = METRICS_TITLEBAR_CORNER_RADIUS_PX;
  NSRect titleRect = rect;
  NSRectFillUsingOperation(titleRect, NSCompositeClear);

  // Simple rect-based gradient fill — no path boundaries that could
  // create aliased edge artifacts.
  [gradient drawInRect:titleRect angle:-90];

  // Top edge highlight — 1px white line matching the button top highlights.
  [[NSColor colorWithCalibratedWhite:1.0 alpha:0.35] setFill];
  NSRectFill(NSMakeRect(NSMinX(titleRect), NSMaxY(titleRect) - 0.5,
                        NSWidth(titleRect), 1));

  // Ensure bottom pixel row is solidly filled with the gradient's end
  // color to prevent any aliasing gap between the gradient and the
  // URSThemeIntegration bottom edge drawn on top.
  [[NSColor colorWithCalibratedRed:bottomRowGray green:bottomRowGray blue:bottomRowGray alpha:1] set];
  NSRectFill(NSMakeRect(NSMinX(titleRect), NSMinY(titleRect),
                        NSWidth(titleRect), 1));

  // Top rounded corner arcs only — no left/right vertical edges, no bottom lines.
  // URSThemeIntegration draws the bottom edge and buttons on top.
  [borderColor setStroke];
  NSBezierPath *arcPath = [NSBezierPath bezierPath];
  CGFloat r = titleBarCornerRadius;
  // Top-right corner arc: from (width-r, MaxY) → (width, MaxY-r) sweeps clockwise
  [arcPath moveToPoint: NSMakePoint(NSMaxX(titleRect), NSMaxY(titleRect) - r)];
  [arcPath appendBezierPathWithArcWithCenter: NSMakePoint(NSMaxX(titleRect) - r, NSMaxY(titleRect) - r)
                                      radius: r
                                  startAngle: 0
                                    endAngle: 90];
  // Top-left corner arc: from (MinX+r, MaxY) → (MinX, MaxY-r) sweeps clockwise
  [arcPath moveToPoint: NSMakePoint(NSMinX(titleRect) + r, NSMaxY(titleRect))];
  [arcPath appendBezierPathWithArcWithCenter: NSMakePoint(NSMinX(titleRect) + r, NSMaxY(titleRect) - r)
                                      radius: r
                                  startAngle: 90
                                    endAngle: 180];
  [arcPath setLineWidth: (1.0 * GSWScaleFactor())];
  [arcPath stroke];
}

- (NSColor *) windowFrameBorderColor
{
  // The window manager uses this as the X11 back_pixel for window frames,
  // which is what is visible while a window is still incomplete (before the
  // client has drawn its content).  Match the window background so those
  // frames do not flash dark grey.
  return [NSColor windowBackgroundColor];
}

- (void) drawResizeBarRect: (NSRect)resizeBarRect
{
  //I don't want to draw the resize bar
  //TODO change the mouse cursor on hover
}

- (void)prepareTitleTextAttributes
{

  NSMutableParagraphStyle *p;
  NSColor *keyColor, *normalColor, *mainColor;

  p = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
  [p setLineBreakMode: NSLineBreakByClipping];


  keyColor = [NSColor colorWithCalibratedRed: 0.05 green: 0.05 blue: 0.05 alpha: 1];
  normalColor = [NSColor colorWithCalibratedRed: 0.70 green: 0.70 blue: 0.70 alpha: 1];  // Lighter for unfocused
  mainColor = keyColor;

  CGFloat titleFontSize = 13.0 * GSWScaleFactor();

  titleTextAttributes[0] = [[NSMutableDictionary alloc]
    initWithObjectsAndKeys:
      [NSFont systemFontOfSize: titleFontSize], NSFontAttributeName,
      keyColor, NSForegroundColorAttributeName,
      p, NSParagraphStyleAttributeName,
      nil];

  titleTextAttributes[1] = [[NSMutableDictionary alloc]
    initWithObjectsAndKeys:
    [NSFont systemFontOfSize: titleFontSize], NSFontAttributeName,
    normalColor, NSForegroundColorAttributeName,
    p, NSParagraphStyleAttributeName,
    nil];

  titleTextAttributes[2] = [[NSMutableDictionary alloc]
    initWithObjectsAndKeys:
    [NSFont systemFontOfSize: titleFontSize], NSFontAttributeName,
    mainColor, NSForegroundColorAttributeName,
    p, NSParagraphStyleAttributeName,
    nil];
}

/* Drop the cached title-text attributes so they are re-prepared with the
 * current GSScaleFactor on the next titlebar render. */
- (void)invalidateTitleTextAttributes
{
  NSUInteger i;
  for (i = 0; i < 3; i++)
    {
      DESTROY(titleTextAttributes[i]);
    }
}


@end
