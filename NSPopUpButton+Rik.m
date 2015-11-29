#import "Rik.h"
#import <AppKit/NSPopUpButton.h>

@implementation NSPopUpButton (RikTheme)

- (void) mouseDown: (NSEvent*)theEvent
{ 
  [_cell trackMouse: theEvent 
	     inRect: [self bounds] 
	     ofView: self 
       untilMouseUp: NO];
}

@end

