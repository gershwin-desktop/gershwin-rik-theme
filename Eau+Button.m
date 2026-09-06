#import "Eau.h"
#import "Eau+Button.h"
#import "AppearanceMetrics.h"


NSString * const kEauIsDefaultButton = @"kEauIsDefaultButton";
NSString * const kEauPulseProgressKey = @"kEauPulseProgressKey";

@implementation NSButtonCell(EauDefaultButtonAnimation)
- (void)setIsDefaultButton:(NSNumber*) val
{
  objc_setAssociatedObject(self, (__bridge const void *)(kEauIsDefaultButton), val, OBJC_ASSOCIATION_COPY);
}

- (NSNumber *) isDefaultButton
{
  return objc_getAssociatedObject(self, (__bridge const void *)(kEauIsDefaultButton));
}
- (BOOL)defaultButton
{
	return [[self isDefaultButton] boolValue];
}
- (void)setPulseProgress:(NSNumber *)pulseProgress
{
  objc_setAssociatedObject(self, (__bridge const void *)(kEauPulseProgressKey), pulseProgress, OBJC_ASSOCIATION_COPY);
}

- (NSNumber*)pulseProgress
{
  return objc_getAssociatedObject(self, (__bridge const void *)(kEauPulseProgressKey));
}
@end

@implementation Eau(EauButton)
- (NSColor*) pulseColorInCell:(NSButtonCell*) bc
{
  BOOL isEnabled = YES;
  if ([bc respondsToSelector:@selector(isEnabled)]) {
    isEnabled = [bc isEnabled];
  }
  if (isEnabled && [bc controlView] && [[bc controlView] isKindOfClass:[NSControl class]]) {
    NSControl *control = (NSControl *)[bc controlView];
    isEnabled = [control isEnabled];
  }
  if (!isEnabled) {
    return [EauSafeCalibratedRGB([NSColor controlBackgroundColor]) shadowWithLevel: 0.1];
  }
  
  // Compute pulse from current time — no timer/animation dependency
  static NSTimeInterval pulseStart = 0;
  if (pulseStart == 0) pulseStart = [NSDate timeIntervalSinceReferenceDate];
  NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - pulseStart;
  double phase = fmod(elapsed, METRICS_PULSE_DURATION) / METRICS_PULSE_DURATION;
  double pulse = sin(M_PI * phase);
  
  NSColor * color;
  color = [NSColor colorWithCalibratedRed: 0.62 green: 0.82 blue: 0.965 alpha: 1];
  color = [NSColor colorWithCalibratedHue: [color hueComponent] saturation: 1.0 - pulse*0.6 brightness: 0.9 + pulse*0.1 alpha: [color alphaComponent]];
  return color;
}
- (NSColor*) buttonColorInCell:(NSCell*) cell forState: (GSThemeControlState) state
{

  NSColor	*color = nil;
  NSString	*name = [super nameForElement: cell];
  color = [self colorNamed: name state: state];
  if (color == nil)
    {
      if (state == GSThemeNormalState)
        {
          color = [EauSafeCalibratedRGB([NSColor controlBackgroundColor]) shadowWithLevel: 0.1];
        }
      else if (state == GSThemeHighlightedState
	       || state == GSThemeHighlightedFirstResponderState)
        {
          color = [NSColor selectedControlColor];
        }
      else if (state == GSThemeSelectedState
	       || state == GSThemeSelectedFirstResponderState)
        {
          color = [NSColor selectedControlColor];
        }
      else
        {
          color = [EauSafeCalibratedRGB([NSColor controlBackgroundColor]) shadowWithLevel: 0.1];
        }
    }
    //PULSE ANIMATION COLOR IF IS PRESSED DONT ANIMATE..
    if([cell class] == [NSButtonCell class] && state != GSThemeSelectedState)
    {
      NSButtonCell * bc = (NSButtonCell *)cell;
      if(bc.isDefaultButton)
        {
          // Only apply pulse color if the button is enabled
          BOOL isEnabled = YES;
          if ([bc respondsToSelector:@selector(isEnabled)]) {
            isEnabled = [bc isEnabled];
          }
          
          if (isEnabled) {
            color = [self pulseColorInCell: bc];
          }
          // If disabled, keep the normal color already set above
        }
    }
  return color;
}
- (NSBezierPath *) _roundBezierPath: (NSRect) frame
                withRadius:(CGFloat) radius
{
  frame = NSInsetRect(frame, 0.5, 0.5);
  NSBezierPath* roundedRectanglePath = [NSBezierPath bezierPathWithRoundedRect: frame
                                                                       xRadius: radius
                                                                       yRadius: radius];
  return roundedRectanglePath;
}
- (void) _drawRoundBezel: (NSRect)cellFrame
               withColor: (NSColor*)backgroundColor
               andRadius: (CGFloat) radius
{

  NSColor* strokeColorButton = [Eau controlStrokeColor];

  NSGradient* buttonBackgroundGradient = [self _bezelGradientWithColor: backgroundColor];

  NSBezierPath* roundedRectanglePath = [self _roundBezierPath: cellFrame withRadius: radius];
  [buttonBackgroundGradient drawInBezierPath: roundedRectanglePath angle: -90];
  [strokeColorButton setStroke];
  [roundedRectanglePath setLineWidth: 1];
  [roundedRectanglePath stroke];
}

- (void) _drawRoundBezel: (NSRect)cellFrame withColor: (NSColor*)backgroundColor
{
  // Default round bezel uses radius 4.  This is used by the shared theme
  // drawing paths (including NSPopUpButtonCell, NSTableView corner views,
  // etc.) — keep at 4 to avoid affecting non-button controls.
  [self _drawRoundBezel: cellFrame withColor: backgroundColor andRadius: 4];
}
- (void) _drawRoundedBezel: (NSRect)cellFrame withColor: (NSColor*)backgroundColor
{
  [self _drawRoundedBezel: cellFrame withColor: backgroundColor inCell: nil];
}

/* Build a rounded-rect path with an independent radius per corner, so a
 * button can keep its outer corners rounded while squaring the side that
 * touches a neighbour in a button bar. */
- (NSBezierPath *) _eau_roundedPath: (NSRect)frame
                            topLeft: (CGFloat)tl
                           topRight: (CGFloat)tr
                          bottomLeft: (CGFloat)bl
                         bottomRight: (CGFloat)br
{
  frame = NSInsetRect(frame, 0.5, 0.5);
  CGFloat maxR = MIN(NSWidth(frame), NSHeight(frame)) / 2.0;
  tl = MAX(0.0, MIN(tl, maxR));
  tr = MAX(0.0, MIN(tr, maxR));
  bl = MAX(0.0, MIN(bl, maxR));
  br = MAX(0.0, MIN(br, maxR));

  NSBezierPath *path = [NSBezierPath bezierPath];
  [path moveToPoint: NSMakePoint(NSMinX(frame) + tl, NSMaxY(frame))];
  if (tr > 0)
    [path appendBezierPathWithArcWithCenter: NSMakePoint(NSMaxX(frame) - tr,
                                                         NSMaxY(frame) - tr)
                                       radius: tr startAngle: 90 endAngle: 0
                                    clockwise: YES];
  else
    [path lineToPoint: NSMakePoint(NSMaxX(frame), NSMaxY(frame))];
  [path lineToPoint: NSMakePoint(NSMaxX(frame), NSMinY(frame) + br)];
  if (br > 0)
    [path appendBezierPathWithArcWithCenter: NSMakePoint(NSMaxX(frame) - br,
                                                         NSMinY(frame) + br)
                                       radius: br startAngle: 0 endAngle: -90
                                    clockwise: YES];
  else
    [path lineToPoint: NSMakePoint(NSMaxX(frame), NSMinY(frame))];
  [path lineToPoint: NSMakePoint(NSMinX(frame) + bl, NSMinY(frame))];
  if (bl > 0)
    [path appendBezierPathWithArcWithCenter: NSMakePoint(NSMinX(frame) + bl,
                                                         NSMinY(frame) + bl)
                                       radius: bl startAngle: -90 endAngle: -180
                                    clockwise: YES];
  else
    [path lineToPoint: NSMakePoint(NSMinX(frame), NSMinY(frame))];
  [path lineToPoint: NSMakePoint(NSMinX(frame), NSMaxY(frame) - tl)];
  if (tl > 0)
    [path appendBezierPathWithArcWithCenter: NSMakePoint(NSMinX(frame) + tl,
                                                         NSMaxY(frame) - tl)
                                       radius: tl startAngle: 180 endAngle: 90
                                    clockwise: YES];
  else
    [path lineToPoint: NSMakePoint(NSMinX(frame), NSMaxY(frame))];
  [path closePath];
  return path;
}

- (void) _drawRoundBezel: (NSRect)cellFrame
                 withColor: (NSColor *)backgroundColor
                  topLeft: (CGFloat)tl
                 topRight: (CGFloat)tr
                bottomLeft: (CGFloat)bl
               bottomRight: (CGFloat)br
{
  NSColor *strokeColorButton = [Eau controlStrokeColor];
  NSGradient *buttonBackgroundGradient = [self _bezelGradientWithColor: backgroundColor];
  NSBezierPath *path = [self _eau_roundedPath: cellFrame
                                     topLeft: tl topRight: tr
                                   bottomLeft: bl bottomRight: br];
  [buttonBackgroundGradient drawInBezierPath: path angle: -90];

  /* Stroke the outline, but only once per touching edge: a squared left or
   * right corner means the button touches a neighbour in the bar, so that
   * vertical edge must not be stroked here - the neighbour draws the single
   * divider.  The top and bottom edges are always stroked, and rounded
   * corners keep their arc.  When a corner is squared we simply omit the
   * straight vertical segment instead of closing the path there, so the seam
   * between two adjacent buttons ends up as exactly one line. */
  BOOL drawLeft = (tl > 0.0) || (bl > 0.0);
  NSRect f = NSInsetRect(cellFrame, 0.5, 0.5);
  CGFloat minX = NSMinX(f), maxX = NSMaxX(f), minY = NSMinY(f), maxY = NSMaxY(f);
  NSBezierPath *sp = [NSBezierPath bezierPath];
  if (tl > 0.0)
    [sp moveToPoint: NSMakePoint(minX + tl, maxY)];
  else
    [sp moveToPoint: NSMakePoint(minX, maxY)];
  [sp lineToPoint: NSMakePoint(maxX - tr, maxY)];
  if (tr > 0.0)
    [sp appendBezierPathWithArcWithCenter: NSMakePoint(maxX - tr, maxY - tr)
                                    radius: tr startAngle: 90 endAngle: 0
                                 clockwise: YES];
  else
    [sp lineToPoint: NSMakePoint(maxX, maxY)];
  [sp lineToPoint: NSMakePoint(maxX, minY + br)];
  if (br > 0.0)
    [sp appendBezierPathWithArcWithCenter: NSMakePoint(maxX - br, minY + br)
                                    radius: br startAngle: 0 endAngle: -90
                                 clockwise: YES];
  else
    [sp lineToPoint: NSMakePoint(maxX, minY)];
  [sp lineToPoint: NSMakePoint(minX + bl, minY)];
  if (bl > 0.0)
    [sp appendBezierPathWithArcWithCenter: NSMakePoint(minX + bl, minY + bl)
                                    radius: bl startAngle: -90 endAngle: -180
                                 clockwise: YES];
  else
    [sp lineToPoint: NSMakePoint(minX, minY)];
  if (drawLeft)
    {
      [sp lineToPoint: NSMakePoint(minX, maxY - tl)];
      if (tl > 0.0)
        [sp appendBezierPathWithArcWithCenter: NSMakePoint(minX + tl, maxY - tl)
                                        radius: tl startAngle: 180 endAngle: 90
                                     clockwise: YES];
    }
  [strokeColorButton setStroke];
  [sp setLineWidth: 1];
  [sp stroke];
}

/* Default rounded radius for a frame: a pill when short, else slightly
 * rounded.  Mirrors _drawRoundedBezel:withColor:inCell:. */
- (CGFloat) _eau_radiusForFrame: (NSRect)frame
{
  if (frame.size.height <= 25.0)
    return MIN(frame.size.width, frame.size.height) / 2.0;
  return 4;
}

/* Square a button's left/right corners when it visually touches or overlaps
 * another button on that side, i.e. a horizontal button bar.  Only other
 * buttons count, and only same-row neighbours (vertical overlap), so a button
 * beside a text field or on a different row stays fully rounded. */
- (void) _eau_adjacencyRadiiForView: (NSView *)view
                          baseRadius: (CGFloat)r
                          leftRadius: (CGFloat *)leftR
                         rightRadius: (CGFloat *)rightR
{
  *leftR = r;
  *rightR = r;
  if (view == nil)
    return;
  NSView *superview = [view superview];
  if (superview == nil)
    return;
  NSRect myFrame = [view frame];
  CGFloat eps = 1.5;
  for (NSView *sib in [superview subviews])
    {
      if (sib == view)
        continue;
      BOOL isButton = [sib isKindOfClass: [NSButton class]];
      if (!isButton && [sib respondsToSelector: @selector(cell)])
        {
          id c = [(id)sib cell];
          if ([c isKindOfClass: [NSButtonCell class]])
            isButton = YES;
        }
      if (!isButton)
        continue;
      NSRect sf = [sib frame];
      if (NSMaxY(sf) <= NSMinY(myFrame) + eps
          || NSMinY(sf) >= NSMaxY(myFrame) - eps)
        continue;
      if (fabs(NSMaxX(sf) - NSMinX(myFrame)) <= eps)
        *leftR = 0;
      if (fabs(NSMinX(sf) - NSMaxX(myFrame)) <= eps)
        *rightR = 0;
    }
}

/* Draw a rounded bezel, squaring the left/right corners that touch another
 * button. */
- (void) _eau_drawRoundBezel: (NSRect)frame
                    withColor: (NSColor *)color
                        radius: (CGFloat)r
                          view: (NSView *)view
{
  CGFloat leftR = r, rightR = r;
  [self _eau_adjacencyRadiiForView: view baseRadius: r
                         leftRadius: &leftR rightRadius: &rightR];
  [self _drawRoundBezel: frame withColor: color
                topLeft: leftR topRight: rightR
              bottomLeft: leftR bottomRight: rightR];
}
- (void) _drawRoundedBezel: (NSRect)cellFrame withColor: (NSColor*)backgroundColor inCell: (NSCell*)cell
{
  float r;
  if (cellFrame.size.height <= 25.0)
    r = MIN(cellFrame.size.width, cellFrame.size.height) / 2.0; // pill
  else
    r = 4; // tall buttons: slightly rounded
  [self _drawRoundBezel: cellFrame withColor: backgroundColor andRadius: r];
}
- (void) drawCircularBezel: (NSRect)cellFrame withColor: (NSColor*)backgroundColor
{
  CGFloat circle_radius = MIN(NSWidth(cellFrame), NSHeight(cellFrame)) / 2;
  CGFloat x = cellFrame.origin.x + cellFrame.size.width/2.0 - circle_radius;
  cellFrame = NSMakeRect( x,
                          cellFrame.origin.y,
                          circle_radius*2,
                          circle_radius*2);

  [self _drawRoundBezel: cellFrame withColor: backgroundColor
              andRadius: circle_radius];
}


- (NSRect) drawButton: (NSRect)border withClip: (NSRect)clip
{
  NSColor * c = [NSColor controlBackgroundColor];
  CGFloat r;
  if (border.size.height <= 25.0)
    r = MIN(border.size.width, border.size.height) / 2.0;
  else
    r = 4;
  [self _eau_drawRoundBezel: border withColor: c radius: r view: [NSView focusView]];
  return border;
}

- (NSBezierPath*) buttonBezierPathWithRect: (NSRect)frame andStyle: (int) style
{
  return [self buttonBezierPathWithRect: frame andStyle: style inCell: nil];
}
- (NSBezierPath*) buttonBezierPathWithRect: (NSRect)frame andStyle: (int) style inCell: (NSCell*)cell
{
  NSBezierPath* bezierPath;
  CGFloat r;
  CGFloat x;

  switch (style)
    {
      case NSRoundRectBezelStyle:
        if (cell && [cell isKindOfClass: [NSPopUpButtonCell class]])
          r = 4;
        else if (frame.size.height <= 25.0)
          r = MIN(frame.size.width, frame.size.height) / 2.0;
        else
          r = 4;
        bezierPath = [self _roundBezierPath: frame
                                 withRadius: r];
        break;
      case NSTexturedRoundedBezelStyle:
      case NSRoundedBezelStyle:
      case 0:
        if (cell && [cell isKindOfClass: [NSPopUpButtonCell class]])
          r = 4;
        else if (frame.size.height <= 25.0)
          r = MIN(frame.size.width, frame.size.height) / 2.0;
        else
          r = 4;
        bezierPath = [self _roundBezierPath: frame
                                 withRadius: r];
        break;
      case NSTexturedSquareBezelStyle:
        frame = NSInsetRect(frame, 0, 1);
      case NSSmallSquareBezelStyle:
      case NSRegularSquareBezelStyle:
      case NSShadowlessSquareBezelStyle:
      case NSThickSquareBezelStyle:
      case NSThickerSquareBezelStyle:
        bezierPath = [NSBezierPath bezierPathWithRect: frame];
        break;
      case NSCircularBezelStyle:
      case NSHelpButtonBezelStyle:
        r = MIN(NSWidth(frame), NSHeight(frame)) / 2;
        x = frame.origin.x + frame.size.width/2.0 - r;

        frame = NSMakeRect( x,
                            frame.origin.y,
                            r*2,
                            r*2);
        bezierPath = [self _roundBezierPath: frame
                                 withRadius: r];
        break;
      case NSDisclosureBezelStyle:
      case NSRoundedDisclosureBezelStyle:
      case NSRecessedBezelStyle:
        r = 4;
        bezierPath = [self _roundBezierPath: frame
                                  withRadius: r];
        break;
      default:
        r = 4;
        bezierPath = [self _roundBezierPath: frame
                                  withRadius: r];
    }
  return bezierPath;
}
- (void) drawButton: (NSRect) frame
				 in: (NSCell*) cell
			   view: (NSView*) view
			  style: (int) style
			  state: (GSThemeControlState) state
{
  NSColor	*color = [self buttonColorInCell: cell forState: state];

  switch (style)
    {
      case NSRoundRectBezelStyle:
        if ([cell isKindOfClass: [NSPopUpButtonCell class]])
          [self _eau_drawRoundBezel: frame withColor: color radius: 4 view: view];
        else
          [self _eau_drawRoundBezel: frame withColor: color
                              radius: [self _eau_radiusForFrame: frame] view: view];
        break;
      case NSTexturedRoundedBezelStyle:
      case NSRoundedBezelStyle:
      case 0:
        if ([cell isKindOfClass: [NSPopUpButtonCell class]])
          [self _eau_drawRoundBezel: frame withColor: color radius: 4 view: view];
        else
          [self _eau_drawRoundBezel: frame withColor: color
                              radius: [self _eau_radiusForFrame: frame] view: view];
        break;
      case NSTexturedSquareBezelStyle:
        frame = NSInsetRect(frame, 0, 1);
      case NSSmallSquareBezelStyle:
      case NSRegularSquareBezelStyle:
      case NSShadowlessSquareBezelStyle:
        [color set];
        NSRectFill(frame);
        [[Eau controlStrokeColor] set];
        NSFrameRectWithWidth(frame, 1);
        break;
      case NSThickSquareBezelStyle:
        [color set];
        NSRectFill(frame);
        [[Eau controlStrokeColor] set];
        NSFrameRectWithWidth(frame, 1.5);
        break;
      case NSThickerSquareBezelStyle:
        [color set];
        NSRectFill(frame);
        [[NSColor controlShadowColor] set];
        NSFrameRectWithWidth(frame, 2);
        break;
      case NSCircularBezelStyle:
        [self drawCircularBezel: frame withColor: color];
        break;
      case NSHelpButtonBezelStyle:
        [self drawCircularBezel: frame withColor: color];
        {
          NSDictionary *attributes = [NSDictionary dictionaryWithObject: [NSFont controlContentFontOfSize: 0]
                      forKey: NSFontAttributeName];
          NSAttributedString *questionMark = [[NSAttributedString alloc]
                  initWithString: _(@"?")
                attributes: attributes];

          NSRect textRect;
          textRect.size = [questionMark size];
          textRect.origin.x = NSMidX(frame) - (textRect.size.width / 2);
          textRect.origin.y = NSMidY(frame) - (textRect.size.height / 2);

          [questionMark drawInRect: textRect];
        }
        break;
      case NSDisclosureBezelStyle:
      case NSRoundedDisclosureBezelStyle:
      case NSRecessedBezelStyle:
        [self _eau_drawRoundBezel: frame withColor: color radius: 4 view: view];
        break;
      default:
        [self _eau_drawRoundBezel: frame withColor: color radius: 4 view: view];
    }
}

// currently not used
- (void) _drawButtonMetal:(NSRect) rect
{
  NSColor* strokeColorButton = [Eau controlStrokeColor];
  NSColor* baseColor = [NSColor colorWithCalibratedRed: 0.75
                                                 green: 0.75
                                                  blue: 0.75
                                                 alpha: 1];

  NSColor* baseColorLight = [baseColor highlightWithLevel: 0.6];

  NSGradient* buttonBackgroundGradient = [[NSGradient alloc] initWithColorsAndLocations:
      baseColorLight, 1.0,
      baseColor, 0.0, nil];
  CGFloat roundedRectangleStrokeWidth = 1;
  NSBezierPath* roundedRectanglePath = [NSBezierPath bezierPathWithRoundedRect: rect xRadius: 3 yRadius: 3];
  [buttonBackgroundGradient drawInBezierPath: roundedRectanglePath angle: -90];
  [strokeColorButton setStroke];
  [roundedRectanglePath setLineWidth: roundedRectangleStrokeWidth];
  [roundedRectanglePath stroke];
}

- (NSRect) drawDarkButton: (NSRect)border withClip: (NSRect)clip
{
  NSColor* strokeColorButton = [Eau controlStrokeColor];
  NSColor* baseColor = [NSColor colorWithCalibratedRed: 0.75
                                                 green: 0.75
                                                  blue: 0.75
                                                 alpha: 1];

  NSColor* baseColorLight = [baseColor highlightWithLevel: 0.6];

  NSGradient* buttonBackgroundGradient = [[NSGradient alloc] initWithColorsAndLocations:
      baseColorLight, 1.0,
      baseColor, 0.0, nil];
  CGFloat roundedRectangleStrokeWidth = 1;
  NSBezierPath* roundedRectanglePath = [NSBezierPath bezierPathWithRect: border];
  [buttonBackgroundGradient drawInBezierPath: roundedRectanglePath angle: -90];
  [strokeColorButton setStroke];
  [roundedRectanglePath setLineWidth: roundedRectangleStrokeWidth];
//  [roundedRectanglePath stroke];
  return border;

}
@end
