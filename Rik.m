#import "Rik.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSWindowDecorationView.h>

// add this declaration to quiet the compiler
@interface Rik(RikButton)
- (NSColor*) buttonColorInCell:(NSCell*) cell forState: (GSThemeControlState) state;
@end

// cache the DBusMenu bundle's principal class
static Class _menuRegistryClass;
  
@implementation Rik

- (Class)_findDBusMenuRegistryClass
{
  NSString   *path;
  NSBundle   *bundle;
  NSArray    *paths = NSSearchPathForDirectoriesInDomains(
                        NSLibraryDirectory, NSAllDomainsMask, YES);
  NSUInteger  count = [paths count];

  if (Nil != _menuRegistryClass)
    return _menuRegistryClass;

  while (count-- > 0)
    {
      path = [paths objectAtIndex:count];
      path = [path stringByAppendingPathComponent:@"Bundles"];
      path = [path stringByAppendingPathComponent:@"DBusMenu"];
      path = [path stringByAppendingPathExtension:@"bundle"];
      bundle = [NSBundle bundleWithPath:path];
      if (bundle)
        {
          if ((_menuRegistryClass = [bundle principalClass]) != Nil)
            break;
        }
    }
  return _menuRegistryClass;
}

- (id)initWithBundle:(NSBundle *)bundle
{
  if ((self = [super initWithBundle:bundle]) != nil)
    {
      // only D-Bus menu registry initialization here
      menuRegistry = [[self _findDBusMenuRegistryClass] new];
      
      // Panel service integration
      currentAppId = [[NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]] retain];
      [self connectToPanelService];
      
      // Add notification observer for menu changes
      [[NSNotificationCenter defaultCenter] 
        addObserver: self
           selector: @selector(macintoshMenuDidChange:)
               name: @"NSMacintoshMenuDidChangeNotification"
             object: nil];
             
      // Add notification observers for app activation
      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(applicationDidBecomeActive:)
               name: NSApplicationDidBecomeActiveNotification
             object: nil];
             
      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(applicationDidResignActive:)
               name: NSApplicationDidResignActiveNotification
             object: nil];
    }
  return self;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [self disconnectFromPanelService];
  [currentAppId release];
  if (connectionRetryTimer) {
    [connectionRetryTimer invalidate];
    [connectionRetryTimer release];
  }
  [super dealloc];
}

#pragma mark - Panel Service Connection

- (void)connectToPanelService
{
  @try {
    NSConnection *connection = [NSConnection connectionWithRegisteredName:@"GNUstepMenuPanel" host:nil];
    if (connection) {
      panelService = [connection rootProxy];
      [panelService setProtocolForProxy:@protocol(GSMenuPanelService)];
      
      [panelService registerApplication:currentAppId];
      
      NSLog(@"Rik theme connected to menu panel service for app %@", currentAppId);
      
      if (connectionRetryTimer) {
        [connectionRetryTimer invalidate];
        [connectionRetryTimer release];
        connectionRetryTimer = nil;
      }
      
      NSMenu *mainMenu = [NSApp mainMenu];
      if (mainMenu && [self shouldUseDistributedMenu:mainMenu]) {
        [panelService setMainMenu:mainMenu forApplication:currentAppId];
      }
    } else {
      panelService = nil;
      // Only log once to avoid spam
      if (!connectionRetryTimer) {
        NSLog(@"Panel service not available, will retry...");
      }
      
      if (!connectionRetryTimer) {
        connectionRetryTimer = [[NSTimer scheduledTimerWithTimeInterval:5.0
                                                                 target:self
                                                               selector:@selector(retryPanelConnection:)
                                                               userInfo:nil
                                                                repeats:YES] retain];
      }
    }
  }
  @catch (NSException *exception) {
    NSLog(@"Exception connecting to panel service: %@", exception);
    panelService = nil;
  }
}

- (void)retryPanelConnection:(NSTimer*)timer
{
  [self connectToPanelService];
}

- (void)disconnectFromPanelService
{
  @try {
    if (panelService) {
      [panelService unregisterApplication:currentAppId];
      panelService = nil;
    }
  }
  @catch (NSException *exception) {
    NSLog(@"Exception disconnecting from panel service: %@", exception);
  }
}

- (BOOL)shouldUseDistributedMenu:(NSMenu*)menu
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  return (panelService != nil && 
          [NSApp mainMenu] == menu && 
          style == NSMacintoshInterfaceStyle);
}

#pragma mark - Notification Handlers

- (void)applicationDidBecomeActive:(NSNotification*)notification
{
  @try {
    if (panelService) {
      [panelService applicationDidBecomeActive:currentAppId];
    }
  }
  @catch (NSException *exception) {
    NSLog(@"Exception notifying panel of app activation: %@", exception);
  }
}

- (void)applicationDidResignActive:(NSNotification*)notification
{
  @try {
    if (panelService) {
      [panelService applicationDidResignActive:currentAppId];
    }
  }
  @catch (NSException *exception) {
    NSLog(@"Exception notifying panel of app deactivation: %@", exception);
  }
}

- (void) macintoshMenuDidChange: (NSNotification*)notification
{
  NSMenu *menu = [notification object];
  
  if ([NSApp mainMenu] == menu) {
    // Check for distributed menu first
    if ([self shouldUseDistributedMenu:menu]) {
      @try {
        [panelService setMainMenu:menu forApplication:currentAppId];
        return;
      }
      @catch (NSException *exception) {
        NSLog(@"Exception sending menu to panel: %@", exception);
        // Fall through to existing logic
      }
    }
    
    // Existing DBus menu logic
    if (menuRegistry != nil) {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil) {
        [self setMenu: menu forWindow: keyWindow];
      }
    }
  }
}

+ (NSColor *) controlStrokeColor
{

  return RETAIN([NSColor colorWithCalibratedRed: 0.4
                                          green: 0.4
                                           blue: 0.4
                                          alpha: 1]);
}

- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state
{
  NSColor	*backgroundColor = [self buttonColorInCell: cell forState: state];
  NSColor* strokeColorButton = [Rik controlStrokeColor];
  NSGradient* buttonBackgroundGradient = [self _bezelGradientWithColor: backgroundColor];
  [buttonBackgroundGradient drawInBezierPath: path angle: -90];
  [strokeColorButton setStroke];
  [path setLineWidth: 1];
  [path stroke];
}

- (void)setMenu:(NSMenu*)m forWindow:(NSWindow*)w
{
  // Check for distributed menu first
  if ([self shouldUseDistributedMenu:m]) {
    return;
  }
  
  if (nil != menuRegistry && m != nil && [m numberOfItems] > 0)
    {
      @try 
        {
          [menuRegistry setMenu: m forWindow: w];
        }
      @catch (NSException *exception)
        {
        }
    }
  else if (nil == menuRegistry)
    {
      [super setMenu: m forWindow: w];
    }
}

- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  // Check for distributed menu first
  if ([self shouldUseDistributedMenu:menu]) {
    @try {
      if (panelService) {
        [panelService setMainMenu:menu forApplication:currentAppId];
      }
      return;
    }
    @catch (NSException *exception) {
      NSLog(@"Exception updating panel menu: %@", exception);
      // Fall through to existing logic
    }
  }
  
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  // Check for distributed menu first
  if ([self shouldUseDistributedMenu:menu]) {
    return NSZeroRect;
  }
  
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      return NSZeroRect;
    }
  
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  // Check for distributed menu first
  if ([self shouldUseDistributedMenu:menu]) {
    return NO;
  }
  
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      return NO;
    }
  
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
