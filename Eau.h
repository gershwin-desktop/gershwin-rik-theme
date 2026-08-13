#import <AppKit/AppKit.h>
#import <Foundation/NSUserDefaults.h>
#import <GNUstepGUI/GSTheme.h>
#import "NSTableView+Eau.h"

// Menu item horizontal padding in pixels. This value is the total horizontal
// padding applied to a menu item and is split equally between the left and
// right sides (e.g. 10.0 => 5 px on the left, 5 px on the right). The
// default of 10.0 was chosen to visually match typical GNUstep menu metrics
// on FreeBSD; in normal use this should remain a small, non-negative even
// number of pixels, usually in the range [4.0, 16.0].
#define EAU_MENU_ITEM_PADDING 10.0

@protocol GSGNUstepMenuClient <NSObject>
- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath
                            forWindow:(NSNumber *)windowId;
// Async push: Menu.app asks the client to send its current menu.
- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId;
// Sync pull: Menu.app asks for fresh enabled/state data right before a submenu opens.
- (bycopy id)validateMenuStateForWindow:(NSNumber *)windowId;
@end

@protocol GSGNUstepMenuServer <NSObject>
- (oneway void)updateMenuForWindow:(bycopy NSNumber *)windowId
                          menuData:(bycopy NSDictionary *)menuData
                        clientName:(bycopy NSString *)clientName;
- (oneway void)unregisterWindow:(bycopy NSNumber *)windowId
                       clientName:(bycopy NSString *)clientName;
// Lightweight: patches only enabled/state on the existing NSMenu without rebuilding.
- (oneway void)updateMenuEnabledStatesForWindow:(bycopy NSNumber *)windowId
                                       menuData:(bycopy NSDictionary *)menuData
                                     clientName:(bycopy NSString *)clientName;
@end

@interface Eau: GSTheme <GSGNUstepMenuClient>
{
    NSMutableDictionary *menuByWindowId;
    NSString *menuClientName;
    NSConnection *menuClientConnection;
    NSPort *menuClientReceivePort;
    NSConnection *menuServerConnection;
    id menuServerProxy;
    BOOL menuServerAvailable;
    BOOL menuServerConnected;
}
+ (NSColor *) controlStrokeColor;
- (void) invalidateScaleFactorCache;
- (void) invalidateTitleTextAttributes;
- (CGFloat) menuItemIconSize;
- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state;

/* Safely convert colors to calibrated RGB. Use this where code previously used
   colorUsingColorSpaceName: NSCalibratedRGBColorSpace to avoid exceptions when
   colors are in non-RGB color spaces (pattern, device, etc.). */
NSColor *EauSafeCalibratedRGB(NSColor *c);

@end

/* Drawing helpers — declared in Eau+Drawings.h category interface,
   implemented in Eau+Drawings.m and Eau+Button.m */
#import "Eau+Drawings.h"

