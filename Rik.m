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
  if (panelConnection) {
    [panelConnection release];
  }
  [super dealloc];
}

#pragma mark - Panel Service Connection

- (void)connectToPanelService
{
  // Don't connect to ourselves if we're the panel app
  NSString *processName = [[[NSProcessInfo processInfo] processName] lowercaseString];
  if ([processName isEqualToString:@"panel"]) {
    NSLog(@"Rik: Skipping panel connection - we ARE the panel");
    return;
  }
  
  @try {
    NSConnection *connection = [NSConnection connectionWithRegisteredName:@"GNUstepMenuPanel" host:nil];
    if (connection) {
      NSLog(@"Rik: Got connection: %@", connection);
      
      // Store the connection separately to keep it alive
      if (panelConnection) {
        [panelConnection release];
      }
      panelConnection = [connection retain];
      
      // Get the root proxy
      id rootProxy = [connection rootProxy];
      NSLog(@"Rik: Got root proxy: %@ of class: %@", rootProxy, [rootProxy class]);
      
      if (rootProxy) {
        // Set protocol first
        [rootProxy setProtocolForProxy:@protocol(GSMenuPanelService)];
        
        // Test with a simple method call
        @try {
          if ([rootProxy respondsToSelector:@selector(registerApplication:)]) {
            NSLog(@"Rik: Proxy responds to registerApplication, testing...");
            [rootProxy registerApplication:currentAppId];
            
            // Only assign if test succeeds
            panelService = rootProxy;
            NSLog(@"Rik: Successfully connected to panel service for app %@", currentAppId);
            
            if (connectionRetryTimer) {
              [connectionRetryTimer invalidate];
              [connectionRetryTimer release];
              connectionRetryTimer = nil;
            }
            
            // DEBUG: Check initial menu state
            NSMenu *mainMenu = [NSApp mainMenu];
            NSLog(@"Rik: Initial menu check - mainMenu: %@", mainMenu);
            NSLog(@"Rik: shouldUseDistributedMenu: %@", [self shouldUseDistributedMenu:mainMenu] ? @"YES" : @"NO");
            
            if (mainMenu && [self shouldUseDistributedMenu:mainMenu]) {
              NSLog(@"Rik: Sending initial menu to panel");
              [self sendMenuToPanel:mainMenu];
            } else {
              NSLog(@"Rik: Not sending initial menu - will wait for macintoshMenuDidChange");
            }
            
            return; // Success!
          } else {
            NSLog(@"Rik: Proxy doesn't respond to registerApplication");
          }
        }
        @catch (NSException *testException) {
          NSLog(@"Rik: Test call failed: %@", testException);
        }
      }
    }
    
    // Connection failed - set up retry
    panelService = nil;
    if (!connectionRetryTimer) {
      NSLog(@"Rik: Panel connection failed, will retry in 3 seconds...");
      connectionRetryTimer = [[NSTimer scheduledTimerWithTimeInterval:3.0
                                                               target:self
                                                             selector:@selector(retryPanelConnection:)
                                                             userInfo:nil
                                                              repeats:YES] retain];
    }
  }
  @catch (NSException *exception) {
    NSLog(@"Rik: Exception connecting to panel service: %@", exception);
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
  
  if (panelConnection) {
    [panelConnection release];
    panelConnection = nil;
  }
}

- (BOOL)shouldUseDistributedMenu:(NSMenu*)menu
{
  // Don't use distributed menu if we're the panel app
  NSString *processName = [[[NSProcessInfo processInfo] processName] lowercaseString];
  if ([processName isEqualToString:@"panel"]) {
    NSLog(@"Rik: shouldUseDistributedMenu: NO - we are panel");
    return NO;
  }
  
  if (!panelConnection) {
    NSLog(@"Rik: shouldUseDistributedMenu: NO - no panel connection");
    return NO;
  }
  
  // Get a fresh proxy each time to avoid corruption
  id freshProxy = [panelConnection rootProxy];
  if (!freshProxy) {
    NSLog(@"Rik: shouldUseDistributedMenu: NO - can't get fresh proxy");
    return NO;
  }
  
  // Set protocol on the fresh proxy
  @try {
    [freshProxy setProtocolForProxy:@protocol(GSMenuPanelService)];
  }
  @catch (NSException *e) {
    NSLog(@"Rik: shouldUseDistributedMenu: NO - protocol setting failed: %@", e);
    return NO;
  }
  
  if (![freshProxy respondsToSelector:@selector(setMainMenu:forApplication:)]) {
    NSLog(@"Rik: shouldUseDistributedMenu: NO - fresh proxy doesn't respond to setMainMenu");
    return NO;
  }
  
  // Update our stored proxy with the fresh one
  panelService = freshProxy;
  
  if ([NSApp mainMenu] != menu) {
    NSLog(@"Rik: shouldUseDistributedMenu: NO - not main menu (is: %@, main: %@)", menu, [NSApp mainMenu]);
    return NO;
  }
  
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  if (style != NSMacintoshInterfaceStyle) {
    NSLog(@"Rik: shouldUseDistributedMenu: NO - not Macintosh style (is: %d)", style);
    return NO;
  }
  
  NSLog(@"Rik: shouldUseDistributedMenu: YES - all conditions met with fresh proxy");
  return YES;
}

- (void)sendMenuToPanel:(NSMenu*)menu
{
  @try {
    NSLog(@"Rik: *** SENDING MENU TO PANEL *** for app %@", currentAppId);
    NSLog(@"Rik: Menu title: '%@', items: %lu", [menu title], (unsigned long)[[menu itemArray] count]);
    
    // Get a fresh proxy to avoid corruption
    id freshProxy = [panelConnection rootProxy];
    if (!freshProxy) {
      NSLog(@"Rik: Failed to get fresh proxy for menu sending");
      return;
    }
    
    [freshProxy setProtocolForProxy:@protocol(GSMenuPanelService)];
    
    [freshProxy setMainMenu:menu forApplication:currentAppId];
    
    // Force hide all local menu display
    [self forceHideAllMenuViews:menu];
    
    NSLog(@"Rik: Menu sent and local views hidden");
  }
  @catch (NSException *menuException) {
    NSLog(@"Rik: Failed to send menu to panel: %@", menuException);
  }
}

- (void)forceHideAllMenuViews:(NSMenu*)menu
{
    if (!menu) return;
    
    // Hide the menu's window completely
    NSWindow *menuWindow = [menu window];
    if (menuWindow) {
        NSLog(@"Rik: Force hiding menu window: %@", menuWindow);
        [menuWindow orderOut:nil];
        [menuWindow setLevel:-1000]; // Send to back
    }
    
    // Hide the menu view
    NSMenuView *menuView = [menu menuRepresentation];
    if (menuView) {
        NSLog(@"Rik: Force hiding menu view: %@", menuView);
        [menuView setHidden:YES];
        [menuView removeFromSuperview];
    }
    
    // Hide submenu views recursively
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item hasSubmenu]) {
            [self forceHideAllMenuViews:[item submenu]];
        }
    }
}

#pragma mark - Notification Handlers

- (void)applicationDidBecomeActive:(NSNotification*)notification
{
  @try {
    if (panelService && [panelService respondsToSelector:@selector(applicationDidBecomeActive:)]) {
      [panelService applicationDidBecomeActive:currentAppId];
      
      // Force hide any menu windows when we become active
      NSMenu *mainMenu = [NSApp mainMenu];
      if (mainMenu && [self shouldUseDistributedMenu:mainMenu]) {
        [self forceHideAllMenuViews:mainMenu];
      }
    }
  }
  @catch (NSException *exception) {
    NSLog(@"Exception notifying panel of app activation: %@", exception);
  }
}

- (void)applicationDidResignActive:(NSNotification*)notification
{
  @try {
    if (panelService && [panelService respondsToSelector:@selector(applicationDidResignActive:)]) {
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
  
  NSLog(@"Rik: macintoshMenuDidChange called for menu: %@", menu);
  NSLog(@"Rik: Main menu is: %@", [NSApp mainMenu]);
  NSLog(@"Rik: Menu == main menu: %@", ([NSApp mainMenu] == menu) ? @"YES" : @"NO");
  
  if ([NSApp mainMenu] == menu) {
    // Check for distributed menu first
    if ([self shouldUseDistributedMenu:menu]) {
      NSLog(@"Rik: Calling sendMenuToPanel from macintoshMenuDidChange");
      [self sendMenuToPanel:menu];
      return;
    } else {
      NSLog(@"Rik: Not using distributed menu for this change");
    }
    
    // Existing DBus menu logic
    if (menuRegistry != nil) {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil) {
        [self setMenu: menu forWindow: keyWindow];
      }
    }
  } else {
    NSLog(@"Rik: Ignoring menu change - not main menu");
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
    [self sendMenuToPanel:m];
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
    NSLog(@"Rik: updateAllWindowsWithMenu - sending to panel, NOT updating windows");
    [self sendMenuToPanel:menu];
    return; // CRITICAL: Don't call super - prevent any local display
  }
  
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  // Check for distributed menu first
  if ([self shouldUseDistributedMenu:menu]) {
    NSLog(@"Rik: modifyRect returning NSZeroRect for distributed menu");
    return NSZeroRect; // Return zero rect to prevent window creation
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
    NSLog(@"Rik: proposedVisibility returning NO for distributed menu");
    return NO; // Absolutely no local visibility
  }
  
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      return NO;
    }
  
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
