/**
* Copyright (C) 2013 Alessandro Sangiuliano
* Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
* Date: 31 December 2013
*/

#import "Rik.h"
#import "NSTextFieldCell+Rik.h"

/* Problems just with the first click in the textbox
 * then all works as should works.
 * The Cell and the text box are not aligned on the first click.
 */

@implementation NSTextFieldCell (RikTheme)

- (void) drawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
	NSRect titleRect;
	cellFrame.origin.y -= 1;
	cellFrame.size.height += 2;
	//cellFrame.size.width -= 1;
	[self _drawEditorWithFrame: cellFrame inView: controlView];
  if (_cell.in_editing)
  {
	cellFrame.origin.y -= 1;
	cellFrame.size.height += 2;
	//cellFrame.size.width -=10 ;

	[self _drawEditorWithFrame: cellFrame inView: controlView];
	//titleRect = [self titleRectForBounds: cellFrame];
	//titleRect.origin.y -= 10;
  }
  else
    {
      //NSRect titleRect;
	cellFrame.origin.y-= 1;
	cellFrame.size.height += 2;
	//cellFrame.size.width -= 10;
	//[self _drawEditorWithFrame: cellFrame inView: controlView];

       /*Make sure we are a text cell; titleRect might return an incorrect
         rectangle otherwise. Note that the type could be different if the
         user has set an image on us, which we just ignore (OS X does so as
         well).*/ 
      _cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
	//titleRect.origin.y -= 1;
	//titleRect.size.height += 2;
      [[self _drawAttributedString] drawInRect: titleRect];
	//[self _drawEditorWithFrame: cellFrame inView: controlView];

    }
/*_cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
titleRect.origin.y -= 1;
titleRect.size.height += 2;
 [[self _drawAttributedString] drawInRect: titleRect];*/

}


@end


