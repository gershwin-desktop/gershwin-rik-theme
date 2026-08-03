/**
* Copyright (C) 2013 Alessandro Sangiuliano
* Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
* Date: 31 December 2013
*/

#import "Eau.h"
#import "NSSearchFieldCell+Eau.h"

#define ICON_WIDTH	16

@interface NSSearchFieldCell (EauTheme)
- (void) EAUdrawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView;
- (NSRect) EAUsearchTextRectForBounds: (NSRect)rect;
- (void) _EAUdrawBorderAndBackgroundWithFrame: (NSRect)cellFrame
				       inView: (NSView*)controlView;
- (void) EAUdrawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView;
- (void) _EAUdrawEditorWithFrame: (NSRect)cellFrame
			  inView: (NSView *)controlView;
- (NSRect) EAUtitleRectForBounds: (NSRect)theRect;
- (NSRect) EAUsearchButtonRectForBounds: (NSRect)rect;
- (NSRect) EAUcancelButtonRectForBounds: (NSRect)rect;
- (void) EAUresetCursorRect: (NSRect)cellFrame inView: (NSView*)controlView;
- (BOOL) EAUtrackMouse: (NSEvent*)theEvent inRect: (NSRect)cellFrame ofView: (NSView*)controlView untilMouseUp: (BOOL)flag;
@end

@implementation Eau(NSSearchFieldCell)
- (void) _overrideNSSearchFieldCellMethod_drawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_drawWithFrame:inView");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  [xself EAUdrawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView];
}

- (NSRect) _overrideNSSearchFieldCellMethod_searchTextRectForBounds: (NSRect)rect {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_searchTextRectForBounds:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  return [xself EAUsearchTextRectForBounds:rect];
}

- (void) _overrideNSSearchFieldCellMethod__drawBorderAndBackgroundWithFrame: (NSRect)cellFrame
								     inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod__drawBorderAndBackgroundWithFrame:inView:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  [xself _EAUdrawBorderAndBackgroundWithFrame:cellFrame inView:controlView];
}

- (void) _overrideNSSearchFieldCellMethod_drawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_drawInteriorWithFrame:inView:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  [xself EAUdrawInteriorWithFrame:cellFrame inView:controlView];
}

- (void) _overrideNSSearchFieldCellMethod__drawEditorWithFrame: (NSRect)cellFrame
							inView: (NSView *)controlView {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod__drawEditorWithFrame:inView:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  [xself _EAUdrawEditorWithFrame:cellFrame inView:controlView];
}

- (NSRect) _overrideNSSearchFieldCellMethod_titleRectForBounds: (NSRect)theRect {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_titleRectForBounds:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  return [xself EAUtitleRectForBounds:theRect];
}

- (NSRect) _overrideNSSearchFieldCellMethod_searchButtonRectForBounds: (NSRect)rect {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_searchButtonRectForBounds:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  return [xself EAUsearchButtonRectForBounds:rect];  
}

- (NSRect) _overrideNSSearchFieldCellMethod_cancelButtonRectForBounds: (NSRect)rect {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_cancelButtonRectForBounds:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  return [xself EAUcancelButtonRectForBounds:rect];
}

- (void) _overrideNSSearchFieldCellMethod_resetCursorRect: (NSRect)cellFrame inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_resetCursorRect:inView:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  [xself EAUresetCursorRect:cellFrame inView:controlView];
}

- (BOOL) _overrideNSSearchFieldCellMethod_trackMouse: (NSEvent*)theEvent inRect: (NSRect)cellFrame ofView: (NSView*)controlView untilMouseUp: (BOOL)flag {
  NSDebugLog(@"_overrideNSSearchFieldCellMethod_trackMouse:inRect:ofView:untilMouseUp:");
  NSSearchFieldCell *xself = (NSSearchFieldCell*)self;
  return [xself EAUtrackMouse: theEvent inRect: cellFrame ofView: controlView untilMouseUp: flag];
}

@end

@implementation NSSearchFieldCell (EauTheme)

- (void) EAUdrawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  [self setDrawsBackground: NO];
  [self setBackgroundColor: [NSColor clearColor]];

  // Draw the Eau search bezel + the text interior directly. We must NOT call
  // [super drawWithFrame:] here: Eau's theme-override mechanism re-dispatches
  // drawWithFrame: dynamically back into THIS method (super does not escape the
  // override), so the original code recursed until the stack overflowed and the
  // app crashed (SIGSEGV) on first draw of any NSSearchField.
  // Calling the EAU* helpers directly reproduces what NSCell's drawWithFrame:
  // would have done (border/background + interior) without re-dispatching.
  [self _EAUdrawBorderAndBackgroundWithFrame: cellFrame inView: controlView];
  [self EAUdrawInteriorWithFrame: cellFrame inView: controlView];

  if (_search_button_cell != nil)
    {
      [_search_button_cell drawWithFrame: [self searchButtonRectForBounds: cellFrame]
                                  inView: controlView];
    }
  else
    {
      /* Draw magnifying glass directly if search button cell is not available */
      NSRect sr = [self searchButtonRectForBounds: cellFrame];
      CGFloat cx = NSMidX(sr);
      CGFloat cy = NSMidY(sr);
      CGFloat r = NSWidth(sr) * 0.3;
      CGFloat handle = r * 0.6;

      [[NSColor colorWithCalibratedWhite: 0.4 alpha: 0.6] setStroke];
      [NSBezierPath setDefaultLineWidth: 1.5];

      NSBezierPath *glass = [NSBezierPath bezierPath];
      [glass appendBezierPathWithArcWithCenter: NSMakePoint(cx, cy)
                                        radius: r
                                    startAngle: 0 endAngle: 360];
      [glass stroke];

      [NSBezierPath strokeLineFromPoint: NSMakePoint(cx + r * 0.7, cy + r * 0.7)
                                toPoint: NSMakePoint(cx + r + handle, cy + r + handle)];
    }
  if ([[self stringValue] length] > 0)
    {
      if (_cancel_button_cell != nil)
        {
          [_cancel_button_cell drawWithFrame: [self cancelButtonRectForBounds: cellFrame]
                                      inView: controlView];
        }
      else
        {
          /* Draw clear-button circle with X */
          NSRect xr = [self cancelButtonRectForBounds: cellFrame];
          CGFloat cx = NSMidX(xr);
          CGFloat cy = NSMidY(xr);

          /* Gray circle background */
          NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect: NSInsetRect(xr, 3, 3)];
          [[NSColor colorWithCalibratedWhite: 0.5 alpha: 0.5] setStroke];
          [NSBezierPath setDefaultLineWidth: 1.0];
          [circle stroke];

          /* White X inside */
          CGFloat xi = NSWidth(xr) * 0.28;
          [[NSColor colorWithCalibratedWhite: 0.5 alpha: 0.8] setStroke];
          [NSBezierPath setDefaultLineWidth: 1.8];
          NSBezierPath *xPath = [NSBezierPath bezierPath];
          [xPath moveToPoint: NSMakePoint(cx - xi, cy - xi)];
          [xPath lineToPoint: NSMakePoint(cx + xi, cy + xi)];
          [xPath moveToPoint: NSMakePoint(cx + xi, cy - xi)];
          [xPath lineToPoint: NSMakePoint(cx - xi, cy + xi)];
          [xPath stroke];
        }
    }
}

/* This method put the "x" cell inside the Text cell */

/* Icon occupies [4, 20] (16px wide at x=4 per searchButtonRectForBounds:);
 * 4px gap between the icon and its label text. */
#define TEXT_LEFT_OFFSET	(4 + ICON_WIDTH + 4)

- (NSRect) EAUsearchTextRectForBounds: (NSRect)rect
{
	NSRect search, part;

	/* Always leave room for the search button/magnifier on the left, whether
	 * the button cell exists or not, so the text never starts under the icon.
	 * searchButtonRectForBounds: places the icon in [0, ICON_WIDTH] (plus a
	 * small offset); start the text after it with the HIG gap. */
	NSDivideRect(rect, &search, &part, ICON_WIDTH, NSMinXEdge);
	part.origin.x += TEXT_LEFT_OFFSET - ICON_WIDTH;
	part.size.width -= (TEXT_LEFT_OFFSET - ICON_WIDTH);

	return part;
}

- (void) _EAUdrawBorderAndBackgroundWithFrame: (NSRect)cellFrame
                                    inView: (NSView*)controlView
{

  NSColor* whiteColor = [NSColor colorWithCalibratedRed: 1
                                                  green: 1
                                                   blue: 1
                                                  alpha: 0.8];
  NSColor* clearColor = [NSColor colorWithCalibratedRed: 1
                                                  green: 1
                                                   blue: 1
                                                  alpha: 0];
  NSColor * strokeBaseColor = [Eau controlStrokeColor];
  NSColor * strokeLightColor = [strokeBaseColor highlightWithLevel: 0.3];

  NSGradient* lightGradient = [[NSGradient alloc] initWithColorsAndLocations:
      clearColor, 0.0,
      whiteColor, 0.97, nil];
  NSGradient* bezelBorderGradient = [[NSGradient alloc] initWithColorsAndLocations:
      strokeBaseColor, 1.0,
      strokeLightColor, 0.5, nil];
  NSGradient* fillGradient = [[NSGradient alloc] initWithColorsAndLocations:
      [strokeBaseColor highlightWithLevel: 0.7], 0.0,
      [NSColor whiteColor], 0.2, nil];

	NSRect rect = cellFrame;
	CGFloat radius = rect.size.height / 2.0;
	NSBezierPath* lightPath = [NSBezierPath bezierPathWithRoundedRect: rect
                                                                       xRadius: radius
                                                                       yRadius: radius];

	NSBezierPath* bezelPath = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(rect, 1, 1)
                                                                       xRadius: radius-2
                                                                       yRadius: radius-2];
	NSBezierPath* fillPath = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(rect, 2, 2)
                                                                       xRadius: radius-2
                                                                       yRadius: radius-2];
  [lightGradient drawInBezierPath: lightPath angle: 90];
  [bezelBorderGradient drawInBezierPath: bezelPath angle: -90];

  [fillGradient drawInBezierPath: fillPath angle: 90];
}

- (void) EAUdrawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  if (_cell.in_editing)
   [self _drawEditorWithFrame: cellFrame inView: controlView];
  else
    {
      NSRect titleRect;

      /* Make sure we are a text cell; titleRect might return an incorrect
         rectangle otherwise. Note that the type could be different if the
         user has set an image on us, which we just ignore (OS X does so as
         well). */
      _cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
      [[self _drawAttributedString] drawInRect: titleRect];
    }
}

- (void) _EAUdrawEditorWithFrame: (NSRect)cellFrame
		       inView: (NSView *)controlView
{
  if ([controlView isKindOfClass: [NSControl class]])
    {
      /* Position the editor in the search field's text area (after the
       * magnifier icon), matching how -editWithFrame:inView:... places the
       * editor.  Using -titleRectForBounds: here would silently return the
       * full cell frame while editing and put the text back under the icon. */
      NSRect titleRect = [self searchTextRectForBounds: cellFrame];
      NSText *textObject = [(NSControl*)controlView currentEditor];
      NSView *clipView = [textObject superview];

      /* Make the editor background transparent so the rounded bezel shows through */
      [textObject setDrawsBackground: NO];
      [textObject setBackgroundColor: [NSColor clearColor]];
      if ([(id)clipView respondsToSelector: @selector(setDrawsBackground:)])
        {
          [(id)clipView setDrawsBackground: NO];
        }

      if ([clipView isKindOfClass: [NSClipView class]])
	{
	  [clipView setFrame: titleRect];
	}
      else
	{
	  [textObject setFrame: titleRect];
	}
    }
}

- (NSRect) EAUtitleRectForBounds: (NSRect)theRect
{
  if (_cell.type == NSTextCellType)
    {
      NSRect frame = [self drawingRectForBounds: theRect];
      if (_cell.is_bordered || _cell.is_bezeled)
        {
          frame.origin.x += TEXT_LEFT_OFFSET;
          frame.size.width -= (TEXT_LEFT_OFFSET + 14);

          /* Vertically centre the text within the search field */
          CGFloat fontHeight = [[self font] boundingRectForFont].size.height;
          if (fontHeight > 0 && fontHeight < NSHeight(frame))
            {
              CGFloat yShift = (NSHeight(frame) - fontHeight) / 2.0;
              frame.origin.y += yShift;
              frame.size.height = fontHeight;
            }
        }
      return frame;
    }
  else
    {
      return theRect;
    }
}

- (NSRect) EAUsearchButtonRectForBounds: (NSRect)rect
{
  NSRect search, part;
  NSDivideRect(rect, &search, &part, ICON_WIDTH, NSMinXEdge);
  search.origin.x += 4;
  search.origin.y += 0;
  return search;
}


- (NSRect) EAUcancelButtonRectForBounds: (NSRect)rect
{
  NSRect part, clear;

  NSDivideRect(rect, &clear, &part, ICON_WIDTH, NSMaxXEdge);
  clear.origin.x -= 5; //This set the position inside the textsearch box
  return clear;
}

- (void) EAUresetCursorRect: (NSRect)cellFrame inView: (NSView*)controlView
{
  /* Let the NSSearchFieldCell's standard cursor rects be set first */
  [super resetCursorRect: cellFrame inView: controlView];

  /* If the cancel button is visible, change cursor to pointing hand */
  if ([[self stringValue] length] > 0)
    {
      NSRect cancelRect = [self cancelButtonRectForBounds: cellFrame];
      [controlView addCursorRect: cancelRect cursor: [NSCursor pointingHandCursor]];
    }
}

- (BOOL) EAUtrackMouse: (NSEvent*)theEvent inRect: (NSRect)cellFrame ofView: (NSView*)controlView untilMouseUp: (BOOL)flag
{
  if ([[self stringValue] length] > 0)
    {
      NSPoint mouseLoc = [controlView convertPoint: [theEvent locationInWindow] fromView: nil];
      NSRect cancelRect = [self cancelButtonRectForBounds: cellFrame];

      if (NSMouseInRect(mouseLoc, cancelRect, [controlView isFlipped]))
        {
          /* Click on the cancel button — clear the search */
          [self setStringValue: @""];
          if ([controlView respondsToSelector: @selector(sendAction:)])
            {
              [(NSControl*)controlView sendAction: [self action] to: [self target]];
            }
          return YES;
        }
    }

  return [super trackMouse: theEvent inRect: cellFrame ofView: controlView untilMouseUp: flag];
}

@end
