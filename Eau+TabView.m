#import "Eau.h"
#import "Eau+Drawings.h"
#import <objc/runtime.h>

// Forward declare private GSTheme method to avoid compiler warnings
@interface GSTheme (PrivateTabMethods)
- (void) drawTabFillInRect: (NSRect)aRect forPart: (GSTabPart)part type: (NSTabViewType)type;
@end

// Enabled state for tab items; GNUstep lacks it.  Default YES so existing
// apps are unaffected.  Implemented at the end of this file.
@interface NSTabViewItem (EauEnabled)
- (void)setEnabled:(BOOL)flag;
- (BOOL)isEnabled;
@end

@interface Eau(EauTabView)
@end

@implementation Eau(EauTabView)

- (void) drawTabViewRect: (NSRect)rect
                  inView: (NSView *)view
               withItems: (NSArray *)items
            selectedItem: (NSTabViewItem *)selected
{
  NSGraphicsContext *ctxt = GSCurrentContext();
  const NSUInteger howMany = [items count];
  NSUInteger i;
  int previousState = 0;
  const NSTabViewType type = [(NSTabView *)view tabViewType];
  const NSRect bounds = [view bounds];
  NSRect aRect = [self tabViewBackgroundRectForBounds: bounds tabViewType: type];

  const BOOL truncate = [(NSTabView *)view allowsTruncatedLabels];
  const CGFloat tabHeight = [self tabHeightForType: type];
  
  DPSgsave(ctxt);
  
  [self drawTabViewBezelRect: aRect
                  tabViewType: type
                       inView: view];

  if (type == NSBottomTabsBezelBorder
      || type == NSTopTabsBezelBorder)
    {
      // Calculate total width of all tabs to center them
      CGFloat totalTabsWidth = 0;
      for (i = 0; i < howMany; i++)
        {
          NSTabViewItem *anItem = [items objectAtIndex: i];
          const NSSize s = [anItem sizeOfLabel: truncate];
          
          // Add left junction/edge width
          if (i == 0)
            {
              NSImage *leftPart = [self imageForTabPart: GSTabSelectedLeft type: type];
              if (leftPart != nil)
                totalTabsWidth += [leftPart size].width;
            }
          else
            {
              NSImage *junctionPart = [self imageForTabPart: GSTabUnSelectedJunction type: type];
              if (junctionPart != nil)
                totalTabsWidth += [junctionPart size].width;
            }
          
          // Add label width
          totalTabsWidth += s.width;
          
          // Add right edge width for last tab
          if (i == howMany - 1)
            {
              NSImage *rightPart = [self imageForTabPart: GSTabSelectedRight type: type];
              if (rightPart != nil)
                totalTabsWidth += [rightPart size].width;
            }
        }
      
      // Calculate starting X position to center tabs
      CGFloat startX;
      if (totalTabsWidth < bounds.size.width)
        {
          startX = bounds.origin.x + (bounds.size.width - totalTabsWidth) / 2.0;
        }
      else
        {
          // If tabs are wider than view, start from left
          startX = bounds.origin.x;
        }
      
      NSPoint iP;
      if (type == NSTopTabsBezelBorder)
        iP = NSMakePoint(startX, bounds.origin.y);
      else
        iP = NSMakePoint(startX, NSMaxY(aRect));

      for (i = 0; i < howMany; i++) 
        {
          NSRect r;
          NSTabViewItem *anItem = [items objectAtIndex: i];
          const NSTabState itemState = [anItem tabState];
          const NSSize s = [anItem sizeOfLabel: truncate];

          // Draw the left image

          if (i == 0)
            {	    
              NSImage *part = nil;
              if (itemState == NSSelectedTab)
                {
                  part = [self imageForTabPart: GSTabSelectedLeft type: type];
                }
              else if (itemState == NSBackgroundTab)
                {
                  part = [self imageForTabPart: GSTabUnSelectedLeft type: type];
                }
              else
                NSLog(@"Not finished yet. Luff ya.\n");

              [part drawInRect: NSMakeRect(iP.x, iP.y, [part size].width, [part size].height)
                      fromRect: NSZeroRect
                     operation: NSCompositeSourceOver
                      fraction: 1.0
                respectFlipped: YES
                         hints: nil];

              iP.x += [part size].width;
            }
          else
            {
              NSImage *part = nil;
              if (itemState == NSSelectedTab)
                {
                  part = [self imageForTabPart: GSTabUnSelectedToSelectedJunction type: type];
                }
              else if (itemState == NSBackgroundTab)
                {
                  if (previousState == NSSelectedTab)
                    {
                      part = [self imageForTabPart: GSTabSelectedToUnSelectedJunction type: type];
                    }
                  else
                    {
                      part = [self imageForTabPart: GSTabUnSelectedJunction type: type];
                    }
                }
              else
                NSLog(@"Not finished yet. Luff ya.\n");

              [part drawInRect: NSMakeRect(iP.x, iP.y, [part size].width, [part size].height)
                      fromRect: NSZeroRect
                     operation: NSCompositeSourceOver
                      fraction: 1.0
                respectFlipped: YES
                         hints: nil];

              iP.x += [part size].width;
            }

          // Draw the middle fill part of the tab

          r.origin = iP;
          r.size.width = s.width;
          r.size.height = tabHeight;

          if (itemState == NSSelectedTab)
            {
              [self drawTabFillInRect: r forPart: GSTabSelectedFill type: type];
            }
          else if (itemState == NSBackgroundTab)
            {
              [self drawTabFillInRect: r forPart: GSTabUnSelectedFill type: type];
            }
          else
            NSLog(@"Not finished yet. Luff ya.\n");

          // Label: a disabled tab must differ from an enabled one ONLY by
          // color. So we replicate GNUstep's exact label layout
          // (systemFontOfSize:11, centered on NSMidX/NSMidY) and swap
          // controlTextColor for the disabled shade. This keeps the font and
          // the positioning bit-for-bit identical to the enabled path below,
          // which calls -[NSTabViewItem drawLabel:inRect:].
          if ([anItem respondsToSelector: @selector(isEnabled)] &&
              ![anItem isEnabled])
            {
              NSString *text = [anItem label];
              NSDictionary *attrs = @{
                NSFontAttributeName : [NSFont systemFontOfSize: 11],
                NSForegroundColorAttributeName :
                  [NSColor disabledControlTextColor]
              };
              NSSize titleSize = [text sizeWithAttributes: attrs];
              NSPoint p = NSMakePoint(NSMidX(r) - titleSize.width / 2.0,
                                      NSMidY(r) - titleSize.height / 2.0);
              [text drawAtPoint: p withAttributes: attrs];
            }
          else
            {
              [anItem drawLabel: truncate inRect: r];
            }

          iP.x += s.width;
          previousState = itemState;

          // For the rightmost tab, draw the right side

          if (i == howMany - 1)
            {
              NSImage *part = nil;
              if ([anItem tabState] == NSSelectedTab)
                {              
                  part = [self imageForTabPart: GSTabSelectedRight type: type];
                }  
              else if ([anItem tabState] == NSBackgroundTab)
                {
                  part = [self imageForTabPart: GSTabUnSelectedRight type: type];
                }
              else
                NSLog(@"Not finished yet. Luff ya.\n");

              [part drawInRect: NSMakeRect(iP.x, iP.y, [part size].width, [part size].height)
                      fromRect: NSZeroRect
                     operation: NSCompositeSourceOver
                      fraction: 1.0
                respectFlipped: YES
                         hints: nil];

              iP.x += [part size].width;

              // Draw the background fill on both sides of centered tabs
              // Left side
              if (startX > bounds.origin.x)
                {
                  NSRect leftFillRect;
                  if (type == NSTopTabsBezelBorder)
                    leftFillRect = NSMakeRect(bounds.origin.x, bounds.origin.y, startX - bounds.origin.x, tabHeight);
                  else
                    leftFillRect = NSMakeRect(bounds.origin.x, NSMaxY(aRect), startX - bounds.origin.x, tabHeight);
                  
                  [self drawTabFillInRect: leftFillRect forPart: GSTabBackgroundFill type: type];
                }
              
              // Right side
              if (iP.x < NSMaxX(bounds))
                {
                  r.origin = iP;
                  r.size.width = NSMaxX(bounds) - iP.x;
                  r.size.height = tabHeight;

                  [self drawTabFillInRect: r forPart: GSTabBackgroundFill type: type];
                }
            }
        }
    }
  // For other tab types (left/right tabs), use default behavior
  else
    {
      [super drawTabViewRect: rect inView: view withItems: items selectedItem: selected];
    }

  DPSgrestore(ctxt);
}

@end

// GNUstep's NSTabViewItem has no enabled state, which Disk Utility needs to
// disable tabs whose operation is unavailable for the current selection.
// Default is enabled so existing apps are unaffected.
@implementation NSTabViewItem (EauEnabled)
static const char kEauTabEnabledKey;
- (void)setEnabled:(BOOL)flag
{
  objc_setAssociatedObject(self, &kEauTabEnabledKey, @(flag),
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isEnabled
{
  NSNumber *flag = objc_getAssociatedObject(self, &kEauTabEnabledKey);
  return flag != nil ? [flag boolValue] : YES;
}
@end
