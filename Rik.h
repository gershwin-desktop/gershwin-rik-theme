#import <AppKit/AppKit.h>
#import <Foundation/NSUserDefaults.h>
#import <GNUstepGUI/GSTheme.h>

// To enable debugging messages in the _overrideClassMethod_foo mechanism
#if 0
#define RIKLOG(args...) NSLog(args)
#else
#define RIKLOG(args...) 
#endif

// Embedded protocol for panel integration - no external dependency needed
@protocol GSMenuPanelService
- (void)registerApplication:(NSString *)appId;
- (void)unregisterApplication:(NSString *)appId;
- (void)setMainMenu:(in bycopy NSMenu *)menu forApplication:(NSString *)appId;
- (void)applicationDidBecomeActive:(NSString *)appId;
- (void)applicationDidResignActive:(NSString *)appId;
@end

@interface Rik: GSTheme
{
    id menuRegistry;                          // existing DBusMenu registry
    id<GSMenuPanelService> panelService;      // Panel service connection
    NSString *currentAppId;                   // current app identifier
    NSTimer *connectionRetryTimer;            // timer for panel connection retries
}

+ (NSColor *) controlStrokeColor;
- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state;

// Panel integration methods
- (void)connectToPanelService;
- (void)disconnectFromPanelService;
- (BOOL)shouldUseDistributedMenu:(NSMenu*)menu;
- (void)retryPanelConnection:(NSTimer*)timer;

@end

#import "Rik+Drawings.h"
