//
// Eau+TitleBarButtons.m
// Eau Theme - Titlebar button rendering for window manager integration
//

#import "Eau+TitleBarButtons.h"
#import "AppearanceMetrics.h"

BOOL EauTitleBarButtonStyleIsOrb(void)
{
    static BOOL isOrb = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *style = [[NSUserDefaults standardUserDefaults]
                           stringForKey:@"EauTitleBarButtonStyle"];
        isOrb = [style isEqualToString:@"orb"];
    });
    return isOrb;
}

@implementation Eau (TitleBarButtons)

#pragma mark - Geometry Queries

- (CGFloat)titlebarHeight
{
    return METRICS_TITLEBAR_HEIGHT_PX;
}

- (NSRect)closeButtonRectForTitlebarWidth:(CGFloat)width
{
    if (EauTitleBarButtonStyleIsOrb()) {
        CGFloat buttonY = (METRICS_TITLEBAR_HEIGHT_PX - METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX) / 2.0;
        return NSMakeRect(METRICS_TITLEBAR_ORB_PADDING_LEFT_PX, buttonY,
                          METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX, METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX);
    }
    // Close button at left edge, square (width == height)
    return NSMakeRect(0, 0, METRICS_TITLEBAR_HEIGHT_PX, METRICS_TITLEBAR_HEIGHT_PX);
}

- (NSRect)minimizeButtonRectForTitlebarWidth:(CGFloat)width
{
    if (EauTitleBarButtonStyleIsOrb()) {
        CGFloat buttonY = (METRICS_TITLEBAR_HEIGHT_PX - METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX) / 2.0;
        CGFloat x = METRICS_TITLEBAR_ORB_PADDING_LEFT_PX + METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX + METRICS_TITLEBAR_ORB_BUTTON_SPACING_PX;
        return NSMakeRect(x, buttonY,
                          METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX, METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX);
    }
    // Minimize button - inner of two side-by-side square buttons on right
    CGFloat x = width - 2 * METRICS_TITLEBAR_HEIGHT_PX;
    return NSMakeRect(x, 0,
                      METRICS_TITLEBAR_HEIGHT_PX,
                      METRICS_TITLEBAR_HEIGHT_PX);
}

- (NSRect)maximizeButtonRectForTitlebarWidth:(CGFloat)width
{
    if (EauTitleBarButtonStyleIsOrb()) {
        CGFloat buttonY = (METRICS_TITLEBAR_HEIGHT_PX - METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX) / 2.0;
        CGFloat x = METRICS_TITLEBAR_ORB_PADDING_LEFT_PX
                    + (METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX + METRICS_TITLEBAR_ORB_BUTTON_SPACING_PX) * 2;
        return NSMakeRect(x, buttonY,
                          METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX, METRICS_TITLEBAR_ORB_BUTTON_SIZE_PX);
    }
    // Maximize button - outer (rightmost) of two side-by-side square buttons on right
    CGFloat x = width - METRICS_TITLEBAR_HEIGHT_PX;
    return NSMakeRect(x, 0,
                      METRICS_TITLEBAR_HEIGHT_PX,
                      METRICS_TITLEBAR_HEIGHT_PX);
}

- (NSRect)rightButtonRegionRectForTitlebarWidth:(CGFloat)width
{
    if (EauTitleBarButtonStyleIsOrb()) {
        return NSZeroRect;
    }
    return NSMakeRect(width - 2 * METRICS_TITLEBAR_HEIGHT_PX, 0,
                      2 * METRICS_TITLEBAR_HEIGHT_PX, METRICS_TITLEBAR_HEIGHT_PX);
}

#pragma mark - Drawing Methods

- (void)drawTitlebarInRect:(NSRect)rect withTitle:(NSString *)title active:(BOOL)active
{
    // Get button rects
    CGFloat width = NSWidth(rect);
    NSRect closeRect = [self closeButtonRectForTitlebarWidth:width];
    NSRect rightRegion = [self rightButtonRegionRectForTitlebarWidth:width];

    // Draw titlebar background (main area between buttons)
    NSRect titleRect;
    if (EauTitleBarButtonStyleIsOrb()) {
        // Orb style: all buttons on left, title area after orb region
        titleRect = NSMakeRect(METRICS_TITLEBAR_ORB_REGION_WIDTH_PX, 0,
                               width - METRICS_TITLEBAR_ORB_REGION_WIDTH_PX,
                               METRICS_TITLEBAR_HEIGHT_PX);
    } else {
        titleRect = NSMakeRect(NSMaxX(closeRect), 0,
                               NSMinX(rightRegion) - NSMaxX(closeRect),
                               METRICS_TITLEBAR_HEIGHT_PX);
    }

    // Draw titlebar background gradient — lighter for inactive windows
    NSColor *gradientColor1, *gradientColor2;
    if (active) {
        gradientColor1 = [NSColor colorWithCalibratedRed:0.83 green:0.83 blue:0.83 alpha:1];
        gradientColor2 = [NSColor colorWithCalibratedRed:0.63 green:0.63 blue:0.63 alpha:1];
    } else {
        gradientColor1 = [NSColor colorWithCalibratedRed:0.92 green:0.92 blue:0.92 alpha:1];
        gradientColor2 = [NSColor colorWithCalibratedRed:0.83 green:0.83 blue:0.83 alpha:1];
    }
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:gradientColor1
                                                         endingColor:gradientColor2];
    [gradient drawInRect:titleRect angle:-90];

    // Draw buttons
    GSThemeControlState state = GSThemeNormalState;
    [self drawCloseButtonInRect:closeRect state:state active:active];
    [self drawMinimizeButtonInRect:[self minimizeButtonRectForTitlebarWidth:width] state:state active:active];
    [self drawMaximizeButtonInRect:[self maximizeButtonRectForTitlebarWidth:width] state:state active:active];

    // Draw title text centered in title area
    if (title && [title length] > 0) {
        [self drawTitleText:title inRect:titleRect active:active];
    }
}

- (void)drawCloseButtonInRect:(NSRect)rect state:(GSThemeControlState)state active:(BOOL)active
{
    BOOL hovered = (state == GSThemeHighlightedState);
    if (EauTitleBarButtonStyleIsOrb()) {
        [self drawOrbInRect:rect
              withBaseColor:[NSColor colorWithCalibratedRed:0.97 green:0.26 blue:0.23 alpha:1]
                     active:active
                    hovered:hovered];
        if (hovered) {
            [self drawCloseIconInRect:NSInsetRect(rect, (3.0 * GSWScaleFactor()), (3.0 * GSWScaleFactor()))
                            withColor:[self iconColorForActive:active highlighted:hovered]];
        }
        return;
    }
    [self drawEdgeButtonInRect:rect
                      position:EauTitleBarButtonPositionLeft
                    buttonType:0
                        active:active
                       hovered:hovered];
    // Show icon on active, or when hovering this button on inactive
    if (active || hovered) {
        [self drawCloseIconInRect:NSInsetRect(rect, METRICS_TITLEBAR_ICON_INSET_PX, METRICS_TITLEBAR_ICON_INSET_PX)
                        withColor:[self iconColorForActive:active highlighted:hovered]];
    }
}

- (void)drawMinimizeButtonInRect:(NSRect)rect state:(GSThemeControlState)state active:(BOOL)active
{
    BOOL hovered = (state == GSThemeHighlightedState);
    if (EauTitleBarButtonStyleIsOrb()) {
        [self drawOrbInRect:rect
              withBaseColor:[NSColor colorWithCalibratedRed:0.9 green:0.7 blue:0.3 alpha:1]
                     active:active
                    hovered:hovered];
        if (hovered) {
            [self drawMinimizeIconInRect:NSInsetRect(rect, (3.0 * GSWScaleFactor()), (3.0 * GSWScaleFactor()))
                               withColor:[self iconColorForActive:active highlighted:hovered]];
        }
        return;
    }
    [self drawEdgeButtonInRect:rect
                      position:EauTitleBarButtonPositionRightInner
                    buttonType:1
                        active:active
                       hovered:hovered];
    // Show icon on active, or when hovering this button on inactive
    if (active || hovered) {
        [self drawMinimizeIconInRect:NSInsetRect(rect, METRICS_TITLEBAR_ICON_INSET_PX, METRICS_TITLEBAR_ICON_INSET_PX)
                           withColor:[self iconColorForActive:active highlighted:hovered]];
    }
}

- (void)drawMaximizeButtonInRect:(NSRect)rect state:(GSThemeControlState)state active:(BOOL)active
{
    BOOL hovered = (state == GSThemeHighlightedState);
    if (EauTitleBarButtonStyleIsOrb()) {
        [self drawOrbInRect:rect
              withBaseColor:[NSColor colorWithCalibratedRed:0.322 green:0.778 blue:0.244 alpha:1]
                     active:active
                    hovered:hovered];
        if (hovered) {
            [self drawMaximizeIconInRect:NSInsetRect(rect, (3.0 * GSWScaleFactor()), (3.0 * GSWScaleFactor()))
                               withColor:[self iconColorForActive:active highlighted:hovered]];
        }
        return;
    }
    [self drawEdgeButtonInRect:rect
                      position:EauTitleBarButtonPositionRightOuter
                    buttonType:2
                        active:active
                       hovered:hovered];
    // Show icon on active, or when hovering this button on inactive
    if (active || hovered) {
        [self drawMaximizeIconInRect:NSInsetRect(rect, METRICS_TITLEBAR_ICON_INSET_PX, METRICS_TITLEBAR_ICON_INSET_PX)
                           withColor:[self iconColorForActive:active highlighted:hovered]];
    }
}

#pragma mark - Icon Drawing

- (void)drawCloseIconInRect:(NSRect)rect withColor:(NSColor *)color
{
    if (!color) return;  // Don't draw on inactive windows

    // Make icon rect square by adding extra horizontal inset if needed
    CGFloat extraHInset = (NSWidth(rect) - NSHeight(rect)) / 2.0;
    if (extraHInset > 0) {
        rect = NSInsetRect(rect, extraHInset, 0);
    }

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:METRICS_TITLEBAR_ICON_STROKE_PX];
    [path setLineCapStyle:NSRoundLineCapStyle];

    // Lowercase x style - shorter strokes, more square
    CGFloat inset = NSWidth(rect) * 0.15;
    [path moveToPoint:NSMakePoint(NSMinX(rect) + inset, NSMinY(rect) + inset)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - inset, NSMaxY(rect) - inset)];
    [path moveToPoint:NSMakePoint(NSMaxX(rect) - inset, NSMinY(rect) + inset)];
    [path lineToPoint:NSMakePoint(NSMinX(rect) + inset, NSMaxY(rect) - inset)];

    [color setStroke];
    [path stroke];
}

- (void)drawMinimizeIconInRect:(NSRect)rect withColor:(NSColor *)color
{
    if (!color) return;

    CGFloat extraHInset = (NSWidth(rect) - NSHeight(rect)) / 2.0;
    if (extraHInset > 0) {
        rect = NSInsetRect(rect, extraHInset, 0);
    }

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:METRICS_TITLEBAR_ICON_STROKE_PX];
    [path setLineCapStyle:NSRoundLineCapStyle];

    // Horizontal line (minus symbol)
    CGFloat inset = NSWidth(rect) * 0.15;
    CGFloat midY = NSMidY(rect);
    [path moveToPoint:NSMakePoint(NSMinX(rect) + inset, midY)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - inset, midY)];

    [color setStroke];
    [path stroke];
}

- (void)drawMaximizeIconInRect:(NSRect)rect withColor:(NSColor *)color
{
    if (!color) return;

    CGFloat extraHInset = (NSWidth(rect) - NSHeight(rect)) / 2.0;
    if (extraHInset > 0) {
        rect = NSInsetRect(rect, extraHInset, 0);
    }

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:METRICS_TITLEBAR_ICON_STROKE_PX];
    [path setLineCapStyle:NSRoundLineCapStyle];

    // Plus symbol
    CGFloat inset = NSWidth(rect) * 0.15;
    CGFloat midX = NSMidX(rect);
    CGFloat midY = NSMidY(rect);

    // Horizontal line
    [path moveToPoint:NSMakePoint(NSMinX(rect) + inset, midY)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - inset, midY)];
    // Vertical line
    [path moveToPoint:NSMakePoint(midX, NSMinY(rect) + inset)];
    [path lineToPoint:NSMakePoint(midX, NSMaxY(rect) - inset)];

    [color setStroke];
    [path stroke];
}

#pragma mark - Private Helpers

- (void)drawOrbInRect:(NSRect)rect
        withBaseColor:(NSColor *)baseColor
               active:(BOOL)active
              hovered:(BOOL)hovered
{
    // Inactive windows get a gray orb
    NSColor *color;
    if (!active) {
        color = [NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1];
    } else if (hovered) {
        color = [baseColor shadowWithLevel:0.2];
    } else {
        color = baseColor;
    }

    // Draw the 3D ball using the same approach as EauWindowButtonCell
    CGFloat sf = GSWScaleFactor();
    NSRect frame = NSInsetRect(rect, 0.5 * sf, 0.5 * sf);
    float luminosity = hovered ? 0.3 : 0.5;

    NSColor *gradientDownColor1 = [color highlightWithLevel:luminosity];
    NSColor *gradientDownColor2 = [color colorWithAlphaComponent:0];
    NSColor *shadowColor1 = [color shadowWithLevel:0.4];
    NSColor *shadowColor2 = [color shadowWithLevel:0.6];
    NSColor *gradientStrokeColor2 = [shadowColor1 highlightWithLevel:luminosity];
    NSColor *gradientUpColor1 = [color highlightWithLevel:luminosity + 0.2];
    NSColor *gradientUpColor2 = [gradientUpColor1 colorWithAlphaComponent:0.5];
    NSColor *gradientUpColor3 = [gradientUpColor1 colorWithAlphaComponent:0];
    NSColor *light1 = [NSColor whiteColor];
    NSColor *light2 = [light1 colorWithAlphaComponent:0];

    NSGradient *gradientUp = [[NSGradient alloc] initWithColorsAndLocations:
        gradientUpColor1, 0.1, gradientUpColor2, 0.3, gradientUpColor3, 1.0, nil];
    NSGradient *gradientDown = [[NSGradient alloc] initWithColorsAndLocations:
        gradientDownColor1, 0.0, gradientDownColor2, 1.0, nil];
    NSGradient *baseGradient = [[NSGradient alloc] initWithColorsAndLocations:
        color, 0.0, shadowColor1, 0.80, nil];
    NSGradient *gradientStroke = [[NSGradient alloc] initWithColorsAndLocations:
        light1, 0.2, light2, 1.0, nil];
    NSGradient *gradientStroke2 = [[NSGradient alloc] initWithColorsAndLocations:
        shadowColor2, 0.47, gradientStrokeColor2, 1.0, nil];

    // Outer stroke rings
    NSBezierPath *outerRing = [NSBezierPath bezierPathWithOvalInRect:frame];
    [gradientStroke drawInBezierPath:outerRing angle:90];
    NSRect innerRingRect = NSInsetRect(frame, 0.5 * sf, 0.5 * sf);
    NSBezierPath *innerRing = [NSBezierPath bezierPathWithOvalInRect:innerRingRect];
    [gradientStroke2 drawInBezierPath:innerRing angle:-90];

    // Base circle
    NSRect baseRect = NSInsetRect(frame, 1.5 * sf, 1.5 * sf);
    NSBezierPath *basePath = [NSBezierPath bezierPathWithOvalInRect:baseRect];
    CGFloat resizeRatio = MIN(NSWidth(baseRect) / 13.0, NSHeight(baseRect) / 13.0);
    [NSGraphicsContext saveGraphicsState];
    [basePath addClip];
    [baseGradient drawFromCenter:NSMakePoint(NSMidX(baseRect), NSMidY(baseRect))
                          radius:2.85 * resizeRatio
                        toCenter:NSMakePoint(NSMidX(baseRect), NSMidY(baseRect))
                          radius:7.32 * resizeRatio
                         options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
    [NSGraphicsContext restoreGraphicsState];

    // Bottom highlight
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *basePath2 = [NSBezierPath bezierPathWithOvalInRect:baseRect];
    [basePath2 addClip];
    [gradientDown drawFromCenter:NSMakePoint(NSMidX(baseRect) - 0.98 * resizeRatio,
                                             NSMidY(baseRect) - 6.5 * resizeRatio)
                          radius:1.54 * resizeRatio
                        toCenter:NSMakePoint(NSMidX(baseRect) - 1.86 * resizeRatio,
                                             NSMidY(baseRect) - 8.73 * resizeRatio)
                          radius:8.65 * resizeRatio
                         options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
    [NSGraphicsContext restoreGraphicsState];

    // Top specular highlight (half-circle)
    NSBezierPath *halfcircle = [NSBezierPath bezierPath];
    NSRect f = frame;
    [halfcircle moveToPoint:NSMakePoint(NSMinX(f) + 0.93316 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))];
    [halfcircle curveToPoint:NSMakePoint(NSMinX(f) + 0.78652 * NSWidth(f), NSMinY(f) + 0.81548 * NSHeight(f))
               controlPoint1:NSMakePoint(NSMinX(f) + 0.93316 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))
               controlPoint2:NSMakePoint(NSMinX(f) + 0.94476 * NSWidth(f), NSMinY(f) + 0.66376 * NSHeight(f))];
    [halfcircle curveToPoint:NSMakePoint(NSMinX(f) + 0.21348 * NSWidth(f), NSMinY(f) + 0.81548 * NSHeight(f))
               controlPoint1:NSMakePoint(NSMinX(f) + 0.62828 * NSWidth(f), NSMinY(f) + 0.96721 * NSHeight(f))
               controlPoint2:NSMakePoint(NSMinX(f) + 0.37172 * NSWidth(f), NSMinY(f) + 0.96721 * NSHeight(f))];
    [halfcircle curveToPoint:NSMakePoint(NSMinX(f) + 0.06684 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))
               controlPoint1:NSMakePoint(NSMinX(f) + 0.05524 * NSWidth(f), NSMinY(f) + 0.66376 * NSHeight(f))
               controlPoint2:NSMakePoint(NSMinX(f) + 0.06684 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))];
    [halfcircle lineToPoint:NSMakePoint(NSMinX(f) + 0.93316 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))];
    [halfcircle closePath];
    [gradientUp drawInBezierPath:halfcircle angle:-90];
}

// buttonType: 0=close, 1=minimize, 2=maximize
- (void)drawEdgeButtonInRect:(NSRect)rect
                    position:(EauTitleBarButtonPosition)position
                  buttonType:(NSInteger)buttonType
                      active:(BOOL)active
                     hovered:(BOOL)hovered
{
    // Get button gradient colors
    NSColor *gradientColor1;
    NSColor *gradientColor2;

    if (hovered) {
        // Hover colors - traffic light colors (apply to ALL windows, active and inactive)
        switch (buttonType) {
            case 0:  // Close - Red
                gradientColor1 = [NSColor colorWithCalibratedRed:0.95 green:0.45 blue:0.42 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.85 green:0.30 blue:0.27 alpha:1];
                break;
            case 1:  // Minimize - Yellow
                gradientColor1 = [NSColor colorWithCalibratedRed:0.95 green:0.75 blue:0.25 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.85 green:0.65 blue:0.15 alpha:1];
                break;
            case 2:  // Maximize - Green
                gradientColor1 = [NSColor colorWithCalibratedRed:0.35 green:0.78 blue:0.35 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.25 green:0.68 blue:0.25 alpha:1];
                break;
            default:
                // Fallback to gray
                gradientColor1 = [NSColor colorWithCalibratedRed:0.65 green:0.65 blue:0.65 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.45 green:0.45 blue:0.45 alpha:1];
                break;
        }
    } else if (active) {
        // Match active titlebar gradient (0.83→0.63)
        gradientColor1 = [NSColor colorWithCalibratedRed:0.83 green:0.83 blue:0.83 alpha:1];
        gradientColor2 = [NSColor colorWithCalibratedRed:0.63 green:0.63 blue:0.63 alpha:1];
    } else {
        // Match inactive titlebar gradient (0.92→0.83)
        gradientColor1 = [NSColor colorWithCalibratedRed:0.92 green:0.92 blue:0.92 alpha:1];
        gradientColor2 = [NSColor colorWithCalibratedRed:0.83 green:0.83 blue:0.83 alpha:1];
    }

    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:gradientColor1
                                                         endingColor:gradientColor2];

    // Border colors — use lighter shade for inactive windows to match
    // the inactive title text color.
    NSColor *borderColor;
    NSColor *topBorderColor;
    if (active) {
      borderColor = [Eau controlStrokeColor];
      topBorderColor = [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    } else {
      borderColor = [NSColor colorWithCalibratedRed:0.92 green:0.92 blue:0.92 alpha:0.5];
      topBorderColor = borderColor;
    }

    // Create path with appropriate corner rounding
    NSBezierPath *path = [self buttonPathForRect:rect position:position];

    // Fill with gradient
    [gradient drawInBezierPath:path angle:-90];

    // Stroke border
    [borderColor setStroke];
    [path setLineWidth:(1.0 * GSWScaleFactor())];
    [path stroke];

    // Draw top border line (replicates titlebar top edge on buttons)
    NSBezierPath *topLine = [NSBezierPath bezierPath];
    CGFloat radius = METRICS_TITLEBAR_BUTTON_INNER_RADIUS_PX;
    if (position == EauTitleBarButtonPositionLeft) {
        // Close button: line from after top-left arc to right edge
        [topLine moveToPoint:NSMakePoint(NSMinX(rect) + radius, NSMaxY(rect) - 0.5)];
        [topLine lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect) - 0.5)];
        [topBorderColor setStroke];
        [topLine setLineWidth:(1.0 * GSWScaleFactor())];
        [topLine stroke];
    } else if (position == EauTitleBarButtonPositionRightOuter) {
        // Maximize button (right outer): line from left edge to before top-right arc
        [topLine moveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect) - 0.5)];
        [topLine lineToPoint:NSMakePoint(NSMaxX(rect) - radius, NSMaxY(rect) - 0.5)];
        [topBorderColor setStroke];
        [topLine setLineWidth:(1.0 * GSWScaleFactor())];
        [topLine stroke];
    } else if (position == EauTitleBarButtonPositionRightInner) {
        // Minimize button (right inner): full width top border line, no arc
        [topLine moveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect) - 0.5)];
        [topLine lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect) - 0.5)];
        [topBorderColor setStroke];
        [topLine setLineWidth:(1.0 * GSWScaleFactor())];
        [topLine stroke];
    }

    // Draw outer edge borders (1px darker outline on far left/right of titlebar)
    [borderColor setStroke];

    if (position == EauTitleBarButtonPositionLeft) {
        // Close button: draw left edge border (far left of titlebar)
        // Draw at x=0.5 so the 1px line is fully visible at the left edge
        NSBezierPath *leftEdge = [NSBezierPath bezierPath];
        [leftEdge moveToPoint:NSMakePoint(0.5, NSMinY(rect))];
        [leftEdge lineToPoint:NSMakePoint(0.5, NSMaxY(rect))];
        [leftEdge setLineWidth:(1.0 * GSWScaleFactor())];
        [leftEdge stroke];
    }

    // Right edge border - only on the outermost button
    if (position == EauTitleBarButtonPositionRightOuter) {
        NSBezierPath *rightEdge = [NSBezierPath bezierPath];
        [rightEdge moveToPoint:NSMakePoint(NSMaxX(rect) - 0.5, NSMinY(rect))];
        [rightEdge lineToPoint:NSMakePoint(NSMaxX(rect) - 0.5, NSMaxY(rect))];
        [rightEdge setLineWidth:(1.0 * GSWScaleFactor())];
        [rightEdge stroke];
    }
}

- (NSBezierPath *)buttonPathForRect:(NSRect)frame position:(EauTitleBarButtonPosition)position
{
    CGFloat radius = METRICS_TITLEBAR_BUTTON_INNER_RADIUS_PX;
    NSBezierPath *path = [NSBezierPath bezierPath];

    switch (position) {
        case EauTitleBarButtonPositionLeft:
            // Close button: ONLY top-left corner rounded, inner edge (right) is straight
            [path moveToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame))];  // bottom-left
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame))];  // bottom-right (straight)
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame))];  // top-right (straight inner edge)
            [path lineToPoint:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame))];  // to top-left arc start
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:90
                                           endAngle:180];  // top-left corner
            [path closePath];
            break;

        case EauTitleBarButtonPositionRightOuter:
            // Maximize button (right outer edge): ONLY top-right corner rounded
            [path moveToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame))];  // bottom-left
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame))];  // bottom-right
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame) - radius)];  // up right edge to arc
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(frame) - radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:0
                                           endAngle:90];  // top-right corner
            [path lineToPoint:NSMakePoint(NSMinX(frame), NSMaxY(frame))];  // straight left edge
            [path closePath];
            break;

        case EauTitleBarButtonPositionRightInner:
            // Minimize button (right inner): no rounding (interior button)
            [path appendBezierPathWithRect:frame];
            break;
    }

    return path;
}

- (NSColor *)iconColorForActive:(BOOL)active highlighted:(BOOL)highlighted
{
    NSColor *color;
    if (!active) {
        color = [NSColor colorWithCalibratedRed:0.55 green:0.55 blue:0.55 alpha:1.0];
    } else {
        color = [NSColor colorWithCalibratedRed:0.20 green:0.20 blue:0.20 alpha:1.0];
    }

    if (highlighted) {
        color = [color shadowWithLevel:0.2];
    }

    return color;
}

- (void)drawTitleText:(NSString *)title inRect:(NSRect)rect active:(BOOL)active
{
    static NSFont *titleFont = nil;
    static NSColor *activeColor = nil;
    static NSColor *inactiveColor = nil;
    static NSParagraphStyle *centerStyle = nil;

    if (!titleFont) {
        titleFont = [NSFont systemFontOfSize:(13.0 * GSWScaleFactor())];
        activeColor = [NSColor colorWithCalibratedRed:0.05 green:0.05 blue:0.05 alpha:1];
        inactiveColor = [NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1];

        NSMutableParagraphStyle *p = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        [p setAlignment:NSCenterTextAlignment];
        centerStyle = [p copy];
    }

    NSColor *textColor = active ? activeColor : inactiveColor;

    // Measure unconstrained text width to decide on truncation
    NSDictionary *measureAttrs = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: textColor,
        NSParagraphStyleAttributeName: centerStyle
    };
    NSSize titleSize = [title sizeWithAttributes:measureAttrs];

    // Calculate gap between centered title and nearest button edge
    CGFloat centeredX = rect.origin.x + rect.size.width / 2.0 - titleSize.width / 2.0;
    CGFloat minX = rect.origin.x;
    CGFloat maxX = NSMaxX(rect) - titleSize.width;
    CGFloat titleLeft = MAX(minX, MIN(centeredX, maxX));
    CGFloat leftGap = titleLeft - rect.origin.x;
    CGFloat rightGap = NSMaxX(rect) - (titleLeft + titleSize.width);

    // Create paragraph style with appropriate truncation
    NSMutableParagraphStyle *p = [centerStyle mutableCopy];
    CGFloat minGap = 24.0 * GSWScaleFactor();
    if (leftGap < minGap || rightGap < minGap) {
        // Use middle ellipsis when gap to nearest button is less than 24px (scaled)
        [p setLineBreakMode:NSLineBreakByTruncatingMiddle];
    } else {
        // No truncation needed when there's enough breathing room
        [p setLineBreakMode:NSLineBreakByClipping];
    }

    NSDictionary *drawAttrs = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: textColor,
        NSParagraphStyleAttributeName: p
    };

    // Center vertically
    NSRect drawRect = rect;
    drawRect.origin.y = NSMidY(rect) - titleSize.height / 2.0;
    drawRect.size.height = titleSize.height;

    [title drawInRect:drawRect withAttributes:drawAttrs];
}

@end
