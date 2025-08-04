#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface Rik(NSButtonCell)
- (NSImage *) _overrideNSButtonCellMethod_image;
- (NSImage *) _overrideNSButtonCellMethod_alternateImage;
@end

@interface NSButtonCell(RikTheme)
- (NSImage *) RIKimage;
- (NSImage *) RIKalternateImage;
@end
