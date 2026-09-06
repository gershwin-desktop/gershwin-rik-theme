#import "Eau.h"
#include <AppKit/AppKit.h>
#import <Foundation/NSUserDefaults.h>
@interface Eau(EauMenu)

@end

@implementation Eau(EauMenu)

- (NSColor *) menuBorderColor
{
  return [Eau controlStrokeColor];
}
- (NSColor *) menuBackgroundColor
{
  NSColor *color = [NSColor colorWithCalibratedRed: 0.992 green: 0.992 blue: 0.992 alpha: 0.66];
  return color;
}
- (NSColor *) menuItemBackgroundColor
{
  NSColor *color = [NSColor colorWithCalibratedRed: 0.992 green: 0.992 blue: 0.992 alpha: 0.95];
  return color;
}
- (CGFloat) menuSubmenuHorizontalOverlap
{
  // Set to 0 so submenu just touches the parent menu without overlapping
  return 0;
}
-(CGFloat) menuSubmenuVerticalOverlap
{
  return 0;
}
- (CGFloat) menuBarHeight
{
  return 22; // Menus and menu items shall be 22px high
}

- (CGFloat) menuItemHeight
{
  return 22; // Menus and menu items shall be 22px high
}

/* Maximum size for the icon shown in front of a menu item (the image column,
   used for application and preference-pane icons).  Icons are scaled down to
   fit this box, never up, so a large app bundle icon renders small. */
- (CGFloat) menuSeparatorHeight
{
  return 1.0;
}

- (BOOL) menuShouldShowIcon
{
  NSUserDefaults *theme_defaults = [NSUserDefaults standardUserDefaults];
  BOOL MenuShouldShowIcon =   [theme_defaults boolForKey:@"MenuShouldShowIcon"]; 
  return MenuShouldShowIcon;
}

// Returns the left border offset for menu items.
// This is used by the theme system to calculate horizontal spacing and positioning
// of menu item content. The value is half of EAU_MENU_ITEM_PADDING to provide
// equal padding on both sides of the menu item.
- (CGFloat) menuItemLeftBorderOffset
{
  return EAU_MENU_ITEM_PADDING / 2.0;
}

// Returns the right border offset for menu items.
// This is used by the theme system to calculate horizontal spacing and positioning
// of menu item content. The value is half of EAU_MENU_ITEM_PADDING to provide
// equal padding on both sides of the menu item.
- (CGFloat) menuItemRightBorderOffset
{
  return EAU_MENU_ITEM_PADDING / 2.0;
}

// Draw title for menu item cell. When the menu item has an image and
// an empty title, draws the image centered in the title rect.
- (void) drawTitleForMenuItemCell: (NSMenuItemCell *)cell
                        withFrame: (NSRect)cellFrame
                           inView: (NSView *)controlView
                            state: (GSThemeControlState)state
                     isHorizontal: (BOOL)isHorizontal
{
  NSMenuItem *item = [cell menuItem];
  NSImage *image = [item image];
  NSString *title = [item title];
  if (image && (!title || [title length] == 0))
    {
      NSRect titleRect = [cell titleRectForBounds: cellFrame];
      NSSize imgSize = [image size];
      CGFloat scale = MIN(titleRect.size.width / imgSize.width,
                          titleRect.size.height / imgSize.height);
      if (scale > 1.0) scale = 1.0;
      NSSize drawSize = NSMakeSize(imgSize.width * scale,
                                   imgSize.height * scale);
      NSPoint drawPoint = NSMakePoint(NSMidX(titleRect) - drawSize.width / 2,
                                      NSMidY(titleRect) - drawSize.height / 2);
      [image drawInRect: NSMakeRect(drawPoint.x, drawPoint.y,
                                    drawSize.width, drawSize.height)
               fromRect: NSZeroRect
              operation: NSCompositeSourceOver
               fraction: 1.0];
      return;
    }
  [super drawTitleForMenuItemCell: cell
                       withFrame: cellFrame
                          inView: controlView
                           state: state
                    isHorizontal: isHorizontal];
}

- (void) drawMenuRect: (NSRect)rect
         inView: (NSView *)view
   isHorizontal: (BOOL)horizontal
      itemCells: (NSArray *)itemCells
{
  int         i = 0;
  int         howMany = [itemCells count];
  NSMenuView *menuView = (NSMenuView *)view;
  NSRect      bounds = [view bounds];

  // TS: unused
  // NSRect r = NSIntersectionRect(bounds, rect);
  NSRectFillUsingOperation(bounds, NSCompositeClear);
  NSColor *borderColor = [self menuBorderColor];
  [borderColor setStroke];
  if(horizontal == YES)
    {
      // here the semitrasparent status bar...
      NSColor* brightGrey = [NSColor colorWithCalibratedRed: 0.95 green: 0.95 blue: 0.95 alpha: 0.80];
      NSColor* midGrey = [NSColor colorWithCalibratedRed: 0.85 green: 0.85 blue: 0.85 alpha: 0.70];
      NSGradient* menuGradient = [[NSGradient alloc] initWithStartingColor: brightGrey endingColor: midGrey];
      [menuGradient drawInRect: bounds angle: -90];
      // Draw bright line at top of menu bar
      NSBezierPath* linePath = [NSBezierPath bezierPath];
      [linePath moveToPoint: NSMakePoint(bounds.origin.x, bounds.origin.y + bounds.size.height)];
      [linePath lineToPoint: NSMakePoint(bounds.origin.x+ bounds.size.width, bounds.origin.y + bounds.size.height)];
      [linePath setLineWidth: 1];
      NSColor* topLineColor = [NSColor colorWithCalibratedRed: 1.0 green: 1.0 blue: 1.0 alpha: 0.8];
      [topLineColor setStroke];
      [linePath stroke];
    }
  else
    {
      // here the vertical menus
      NSColor* brightGrey = [NSColor colorWithCalibratedRed: 0.85 green: 0.85 blue: 0.85 alpha: 0.66];
      NSColor* midGrey = [NSColor colorWithCalibratedRed: 0.65 green: 0.65 blue: 0.65 alpha: 0.66];
      NSGradient* menuGradient = [[NSGradient alloc] initWithStartingColor: brightGrey endingColor: midGrey];
      [menuGradient drawInRect: bounds angle: -90];

    }
  // Draw the menu cells.
  for (i = 0; i < howMany; i++)
    {
      NSRect aRect;
      NSMenuItemCell *aCell;
      aRect = [menuView rectOfItemAtIndex: i];
      if (NSIntersectsRect(rect, aRect) == YES)
        {
          aCell = [menuView menuItemCellForItemAtIndex: i];
          [aCell drawWithFrame: aRect inView: menuView];
        }
    }
  // Draw the border on top of cells for vertical (dropdown/context) menus
  if (!horizontal)
    {
      NSBezierPath * strokemenuPath = [NSBezierPath bezierPathWithRect: NSInsetRect(bounds, 0.5, 0.5)];
      [borderColor setStroke];
      [strokemenuPath stroke];
    }
}

- (void) drawBackgroundForMenuView: (NSMenuView*)menuView
                         withFrame: (NSRect)bounds
                         dirtyRect: (NSRect)dirtyRect
                        horizontal: (BOOL)horizontal
{
  // TS: unused
  // NSString  *name = horizontal ? GSMenuHorizontalBackground :
  //   GSMenuVerticalBackground;

  // TS: unused
  // NSRectEdge sides[4] = { NSMinXEdge, NSMaxYEdge, NSMaxXEdge, NSMinYEdge };

  NSRect r = NSIntersectionRect(bounds, dirtyRect);
  NSRectFillUsingOperation(r, NSCompositeClear);
  NSColor* brightGrey = [NSColor colorWithCalibratedRed: 0.85 green: 0.85 blue: 0.85 alpha: 0.66];
  NSColor* midGrey = [NSColor colorWithCalibratedRed: 0.65 green: 0.65 blue: 0.65 alpha: 0.66];
  NSGradient* menuGradient = [[NSGradient alloc] initWithStartingColor: brightGrey endingColor: midGrey];
  [menuGradient drawInRect: r angle: -90];
}

- (void) drawBorderAndBackgroundForMenuItemCell: (NSMenuItemCell *)cell
                                      withFrame: (NSRect)cellFrame
                                         inView: (NSView *)controlView
                                          state: (GSThemeControlState)state
                                   isHorizontal: (BOOL)isHorizontal
{


  // TS: unused
  // NSColor * backgroundColor = [self menuItemBackgroundColor];
  NSColor* selectedBackgroundColor1 = [NSColor colorWithCalibratedRed: 0.392 green: 0.533 blue: 0.953 alpha: 1];
  NSColor* selectedBackgroundColor2 = [NSColor colorWithCalibratedRed: 0.165 green: 0.373 blue: 0.929 alpha: 1];

  NSColor* menuItemBackground = [self menuItemBackgroundColor];
  NSGradient* menuitemgradient = [[NSGradient alloc] initWithStartingColor: selectedBackgroundColor1
                                                               endingColor: selectedBackgroundColor2];
  NSColor * c;
  [cell setBordered:NO];

  if (state == GSThemeSelectedState || state == GSThemeHighlightedState)
    {
      // Draw highlight on full cell frame (including padding)
      NSRectFillUsingOperation(cellFrame, NSCompositeClear);
      [menuitemgradient drawInRect:cellFrame angle: -90];
      return;
    }
  else
    {
      if(isHorizontal)
        {
          return;
        }
      else
        {
          c = menuItemBackground;
        }
    }

  // Set cell's background color
  [c setFill];
  NSRectFillUsingOperation(cellFrame, NSCompositeClear);
  NSRectFill(cellFrame);

}

- (void) drawSeparatorItemForMenuItemCell: (NSMenuItemCell *)cell
                                withFrame: (NSRect)cellFrame
                                   inView: (NSView *)controlView
                             isHorizontal: (BOOL)isHorizontal
{
  // Draw a thin 1px separator line in light grey
  NSColor *separatorColor = [NSColor colorWithCalibratedRed: 0.8 green: 0.8 blue: 0.8 alpha: 1.0];
  [separatorColor set];
  
  // Draw a single pixel line in the middle of the cell frame
  CGFloat y = cellFrame.origin.y + cellFrame.size.height / 2.0;
  NSBezierPath *path = [NSBezierPath bezierPath];
  [path setLineWidth: 1.0];
  [path moveToPoint: NSMakePoint(cellFrame.origin.x + [self menuSeparatorInset], y)];
  [path lineToPoint: NSMakePoint(cellFrame.origin.x + cellFrame.size.width - [self menuSeparatorInset], y)];
  [path stroke];
}
@end