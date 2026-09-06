#import "Eau.h"

void NSRoundRectDraw(NSRect r, float radius);
void NSRoundRectFill(NSRect r, float radius);

@interface Eau(EauDrawings)

- (NSGradient *) _bezelGradientWithColor:(NSColor*) baseColor;
- (NSGradient *) _buttonGradientWithColor:(NSColor*) baseColor;
- (NSGradient *) _windowTitlebarGradient;
- (NSGradient *) _windowTitlebarGradientInactive;
- (NSRect) drawInnerGrayBezel: (NSRect)border withClip: (NSRect)clip;
- (NSBezierPath*) buttonBezierPathWithRect: (NSRect)frame andStyle: (int) style;
- (NSBezierPath*) buttonBezierPathWithRect: (NSRect)frame andStyle: (int) style inCell: (NSCell*)cell;

/* Per-corner rounding helpers used so a control's outline (and its focus
 * ring) can keep its outer corners round while squaring the side that
 * touches a neighbour in a bar. */
- (CGFloat) _eau_radiusForFrame: (NSRect)frame;
- (void) _eau_adjacencyRadiiForView: (NSView *)view
                         baseRadius: (CGFloat)r
                          leftRadius: (CGFloat *)leftR
                         rightRadius: (CGFloat *)rightR;
- (NSBezierPath *) _eau_roundedPath: (NSRect)frame
                             topLeft: (CGFloat)tl
                            topRight: (CGFloat)tr
                           bottomLeft: (CGFloat)bl
                          bottomRight: (CGFloat)br;
@end
