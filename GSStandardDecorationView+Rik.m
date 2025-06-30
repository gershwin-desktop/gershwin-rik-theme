#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSTheme.h>
#import "Rik.h"
#import <objc/runtime.h>

#define TITLEBAR_BUTTON_SIZE 15
#define TITLEBAR_PADDING_LEFT 10.5
#define TITLEBAR_PADDING_RIGHT 10.5
#define TITLEBAR_PADDING_TOP 5.5

// Association keys
static const char *ZoomButtonKey = "RikZoomButton";

@interface GSStandardWindowDecorationView(RikTheme)
- (void) RIKupdateRects;
@end

@implementation Rik(GSStandardWindowDecorationView)
- (void) _overrideGSStandardWindowDecorationViewMethod_updateRects {
    GSStandardWindowDecorationView* xself = (GSStandardWindowDecorationView*)self;
    RIKLOG(@"GSStandardDecorationView+Rik updateRects");
    [xself RIKupdateRects];
}
@end

@implementation GSStandardWindowDecorationView(RikTheme)

- (void) RIKupdateRects
{
    GSTheme *theme = [GSTheme theme];

    if (hasTitleBar) {
        CGFloat titleHeight = [theme titlebarHeight];
        titleBarRect = NSMakeRect(0.0, [self bounds].size.height - titleHeight,
                                   [self bounds].size.width, titleHeight);
    }
    if (hasResizeBar) {
        resizeBarRect = NSMakeRect(0.0, 0.0, [self bounds].size.width, [theme resizebarHeight]);
    }
    if (hasCloseButton) {
        closeButtonRect = NSMakeRect(
            TITLEBAR_PADDING_LEFT,
            [self bounds].size.height - TITLEBAR_BUTTON_SIZE - TITLEBAR_PADDING_TOP,
            TITLEBAR_BUTTON_SIZE, TITLEBAR_BUTTON_SIZE);
        [closeButton setFrame: closeButtonRect];
    }
    if (hasMiniaturizeButton) {
        miniaturizeButtonRect = NSMakeRect(
            TITLEBAR_PADDING_LEFT + TITLEBAR_BUTTON_SIZE + 4,
            [self bounds].size.height - TITLEBAR_BUTTON_SIZE - TITLEBAR_PADDING_TOP,
            TITLEBAR_BUTTON_SIZE, TITLEBAR_BUTTON_SIZE);
        [miniaturizeButton setFrame: miniaturizeButtonRect];
    }

    NSButton *zoomButton = objc_getAssociatedObject(self, ZoomButtonKey);
    if (!zoomButton) {
        zoomButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        [zoomButton setButtonType:NSMomentaryChangeButton];
        [zoomButton setBezelStyle:NSCircularBezelStyle];
        [zoomButton setBordered:YES];
        [zoomButton setImage:[NSImage imageNamed:@"common_Miniaturize"]]; // Replace with "common_Zoom" when ready
        [zoomButton setTarget:[self window]];
        [zoomButton setAction:@selector(zoom:)];
        [self addSubview:zoomButton];

        objc_setAssociatedObject(self, ZoomButtonKey, zoomButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Position the zoom button
    NSRect zoomButtonRect = NSMakeRect(
        TITLEBAR_PADDING_LEFT + TITLEBAR_BUTTON_SIZE * 2 + 8,
        [self bounds].size.height - TITLEBAR_BUTTON_SIZE - TITLEBAR_PADDING_TOP,
        TITLEBAR_BUTTON_SIZE, TITLEBAR_BUTTON_SIZE);
    [zoomButton setFrame:zoomButtonRect];
}

@end
