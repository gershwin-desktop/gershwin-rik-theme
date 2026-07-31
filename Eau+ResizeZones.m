#include "Eau.h"
#include "AppearanceMetrics.h"

@interface Eau(EauResizeZones)

@end

@implementation Eau(EauResizeZones)

/**
 * Theme-driven resize zones protocol.
 *
 * These methods are queried by the window manager using respondsToSelector:
 * to configure invisible resize capture windows at window edges and corners.
 * The presence of resizeZoneCornerSize indicates the theme supports this protocol.
 */

/**
 * Returns the size (width and height) of corner resize zones.
 * Corner zones are square, positioned at the four corners of the window frame.
 */
- (CGFloat)resizeZoneCornerSize
{
  return METRICS_RESIZE_CORNER_SIZE;  // 11px - matches scrollbar width for visual consistency
}

/**
 * Returns the thickness of edge resize zones.
 * Edge zones are thin rectangles along the four edges of the window frame,
 * positioned between the corner zones.
 */
- (CGFloat)resizeZoneEdgeThickness
{
  return METRICS_RESIZE_EDGE_THICKNESS;  // 4px - thin but usable
}

/**
 * Returns whether a specific resize direction is enabled.
 * direction values correspond to EResizeDirection enum in the window manager.
 *
 * The Eau theme enables all 8 resize directions (4 corners + 4 edges).
 */
- (BOOL)resizeZoneEnabled:(NSInteger)direction
{
  // Enable all resize directions
  // Direction values: 1=N, 2=S, 3=E, 4=W, 5=NW, 6=NE, 7=SE, 8=SW
  return (direction >= 1 && direction <= 8);
}

/**
 * Returns whether the theme renders a visible resize visual (like a grow box).
 * If YES, the theme is responsible for drawing the visual feedback.
 * The window manager only creates invisible capture windows.
 *
 * The Eau theme renders a grow box at the SE corner via EauGrowBoxView.
 */
- (BOOL)themeRendersResizeVisual
{
  return YES;
}

#pragma mark - Grow Box Zone

/**
 * Returns whether the theme wants a separate grow box resize zone.
 * The grow box zone overlays the SE corner with a larger size,
 * matching the visible grow box element drawn by EauGrowBoxView.
 */
- (BOOL)resizeZoneHasGrowBox
{
  return YES;
}

/**
 * Returns the size of the grow box resize zone (square).
 * Slightly larger than visual grow box for easier grabbing.
 */
- (CGFloat)resizeZoneGrowBoxSize
{
  return METRICS_GROW_BOX_SIZE;
}

#pragma mark - Titlebar Corner Radius

/**
 * Returns the corner radius for rounded top corners of the window frame.
 * Returns 0 for square corners.
 * The window manager applies this via XCB shape mask.
 */
- (CGFloat)titlebarCornerRadius
{
  return METRICS_TITLEBAR_CORNER_RADIUS_PX;
}

/**
 * Returns the corner radius for rounded bottom corners of the window frame.
 * Returns 0 for square bottom corners (typical Aqua style).
 * Optional - if not implemented, window manager defaults to 0.
 */
- (CGFloat)windowBottomCornerRadius
{
  return METRICS_WINDOW_BOTTOM_CORNER_RADIUS;
}

@end
