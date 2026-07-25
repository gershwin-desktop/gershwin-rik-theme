#import "Eau.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSPortNameServer.h>
#import "NSMenuItemCell+Eau.h"
#import "Eau+Button.h"
#import "EauMenuRelaunchManager.h"

@interface NSApplication (EauStepTalk)
+ (void)setupStepTalkScripting;
@end

@interface Eau (StepTalkRegistration)
- (void)eau_setupStepTalkOnLaunch:(NSNotification *)note;
@end

@interface Eau (NSWindowTitle)
+ (void)EAUswizzleNSWindowSetTitle;
@end

static BOOL gForceExternalMenuByEnv = NO;
static BOOL gPendingMenuUpdate = NO;
static NSWindow *gPendingMenuWindow = nil;

static BOOL EauEnvironmentContainsAppMenuToken(void)
{
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  for (NSString *value in [env allValues])
    {
      if ([value rangeOfString:@"appmenu" options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
          return YES;
        }
    }
  return NO;
}

// Expose UIBridge-friendly API from theme so the UIBridge server can talk to the
// theme process directly (avoids needing to inject an agent into each app).
#import "UIBridgeProtocol.h"
#import "Eau+DragTool.h"

// Implementation of safe color conversion helper
NSColor *EauSafeCalibratedRGB(NSColor *c)
{
  if (!c) return nil;

  @try {
    if ([c respondsToSelector:@selector(colorUsingColorSpaceName:)]) {
      NSColor *rgb = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
      if (rgb) return rgb;
    }
  } @catch (NSException *ex) {
    NSLog(@"EauSafeCalibratedRGB: conversion threw: %@, falling back", ex);
  }

  // Try grayscale fallback
  @try {
    if ([c respondsToSelector:@selector(whiteComponent)]) {
      CGFloat w = [c whiteComponent];
      CGFloat a = ([c respondsToSelector:@selector(alphaComponent)] ? [c alphaComponent] : 1.0);
      return [NSColor colorWithCalibratedWhite:w alpha:a];
    }
  } @catch (NSException *ex) {
    NSLog(@"EauSafeCalibratedRGB: whiteComponent threw: %@, falling back", ex);
  }

  // Final fallback: light control background
  return [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
}

// Dedicated UIBridge proxy object to expose the Eau theme's UIBridgeProtocol methods
// This is needed because Distributed Objects requires explicit protocol conformance
@interface EauUIBridgeProxy : NSObject <UIBridgeProtocol>
{
  Eau *theme;
}
- (id)initWithTheme:(Eau *)t;
@end

@interface Eau () <UIBridgeProtocol>
@end

@implementation EauUIBridgeProxy

- (id)initWithTheme:(Eau *)t
{
  if ((self = [super init]) != nil) {
    theme = t;
  }
  return self;
}

// Forward all protocol methods to the Eau theme
- (bycopy NSString *)rootObjectsJSON {
  return [theme rootObjectsJSON];
}

- (bycopy NSString *)detailsForObjectJSON:(NSString *)objID {
  return [theme detailsForObjectJSON:objID];
}

- (bycopy NSString *)fullTreeForObjectJSON:(NSString *)objID {
  return [theme fullTreeForObjectJSON:objID];
}

- (bycopy NSString *)invokeSelectorJSON:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
  return [theme invokeSelectorJSON:selectorName onObject:objID withArgs:args];
}

- (bycopy id)rootObjects {
  return [theme rootObjects];
}

- (bycopy id)detailsForObject:(NSString *)objID {
  return [theme detailsForObject:objID];
}

- (bycopy id)fullTreeForObject:(NSString *)objID {
  return [theme fullTreeForObject:objID];
}

- (bycopy id)invokeSelector:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
  return [theme invokeSelector:selectorName onObject:objID withArgs:args];
}

- (bycopy NSArray *)listMenus {
  return [theme listMenus];
}

- (bycopy NSString *)listMenusJSON {
  return [theme listMenusJSON];
}

- (BOOL)invokeMenuItem:(NSString *)objID {
  return [theme invokeMenuItem:objID];
}

- (void)enableDragMode { [theme enableDragMode]; }
- (void)disableDragMode { [theme disableDragMode]; }
- (BOOL)isDragModeEnabled { return [theme isDragModeEnabled]; }
- (bycopy NSString *)dragDeltaFilePath { return [theme dragDeltaFilePath]; }

@end


// Connection delegate to enable multi-threading on child connections
@interface EauConnectionDelegate : NSObject
@end

@implementation EauConnectionDelegate
- (NSConnection *)connection:(NSConnection *)parentConnection didConnect:(NSConnection *)newConnection
{
    // Enable multi-threading on all child connections immediately
    [newConnection enableMultipleThreads];
    [newConnection setIndependentConversationQueueing:YES];
    // NSLog(@"Eau: [Delegate] Enabled multi-threading on new connection: %@ (parent: %@)", newConnection, parentConnection);
    return newConnection;
}

- (BOOL)connection:(NSConnection *)parentConnection shouldMakeNewConnection:(NSConnection *)newConnection
{
    // Enable multi-threading before the connection becomes active
    [newConnection enableMultipleThreads];
    [newConnection setIndependentConversationQueueing:YES];
    // NSLog(@"Eau: [Delegate] shouldMakeNewConnection - enabled multi-threading on: %@", newConnection);
    return YES;
}
@end

static EauConnectionDelegate *gUIBridgeConnectionDelegate = nil;

// Connection used to expose UIBridgeProtocol methods from theme (per-PID service)
static NSConnection *gUIBridgeThemeConnection = nil;
static EauUIBridgeProxy *gUIBridgeProxy = nil;

@implementation Eau

+ (void)load
{
  // Swizzle NSWindow setTitle: to add middle-ellipsis truncation for long titles
  [self EAUswizzleNSWindowSetTitle];

  gForceExternalMenuByEnv = EauEnvironmentContainsAppMenuToken();
  if (gForceExternalMenuByEnv)
    {
      NSDebugLog(@"Eau: appmenu token detected in environment, forcing external menu mode");
    }
  // NSLog(@"Eau: +load called");
  // Schedule UIBridge service registration after a delay to ensure run loop is active
  // Using dispatch_after ensures this runs even if performSelector isn't processed
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self _registerUIBridgeService:nil];
  });
}

+ (void)_handleNewConnection:(NSNotification *)notification
{
  NSConnection *conn = [notification object];
  // Enable multi-threading on all new connections to handle cross-process requests
  [conn enableMultipleThreads];
  [conn setIndependentConversationQueueing:YES];
  // NSLog(@"Eau: Enabled multi-threading on new connection: %@", conn);
}

// Static variable to hold the shared Eau instance for UIBridge
static Eau *gSharedEauInstance = nil;

+ (void)_registerUIBridgeService:(id)unused
{
  // Allow apps to opt out via environment variable.  Set
  // EAU_DISABLE_UIBRIDGE=1 before the Eau bundle loads to skip
  // UIBridge registration entirely, avoiding the NSMessagePort
  // socket polling that burns CPU on every runloop iteration.
  {
    const char *val = getenv("EAU_DISABLE_UIBRIDGE");
    if (val != NULL && strcmp(val, "1") == 0) {
      NSDebugLog(@"Eau: UIBridge disabled via EAU_DISABLE_UIBRIDGE");
      return;
    }
  }

  // Check if we have a valid Eau instance
  if (!gSharedEauInstance) {
    // Try to get from GSTheme
    id themeObj = (id)[GSTheme theme];
    if ([themeObj isKindOfClass:[Eau class]]) {
      gSharedEauInstance = (Eau *)themeObj;
    } else {
      NSLog(@"Eau: _registerUIBridgeService called but no Eau instance available yet (got %@)", [themeObj class]);
      return;
    }
  }
  
  // Already registered?
  if (gUIBridgeThemeConnection) {
    // NSLog(@"Eau: UIBridge service already registered, skipping");
    return;
  }
  
  pid_t pid = [[NSProcessInfo processInfo] processIdentifier];
  // Register per-PID service so each app has its own unique UIBridge service
  NSString *name = [NSString stringWithFormat:@"org.gershwin.Gershwin.Theme.UIBridge.%d", pid];
  // NSLog(@"Eau: Registering per-PID UIBridge theme service: %@", name);
  
  @try {
    // NSLog(@"Eau: Theme object class: %@, responds to listMenus: %d",
    //       [gSharedEauInstance class],
    //       (int)[gSharedEauInstance respondsToSelector:@selector(listMenus)]);
    
    // Create a proxy object that explicitly implements UIBridgeProtocol
    gUIBridgeProxy = [[EauUIBridgeProxy alloc] initWithTheme:gSharedEauInstance];
    // NSLog(@"Eau: Created UIBridge proxy: %@", gUIBridgeProxy);
    
    // Create connection delegate to handle child connections
    gUIBridgeConnectionDelegate = [[EauConnectionDelegate alloc] init];
    
    gUIBridgeThemeConnection = [[NSConnection alloc] init];
    // NSLog(@"Eau: Connection created - receivePort: %@, sendPort: %@",
    //       [gUIBridgeThemeConnection receivePort],
    //       [gUIBridgeThemeConnection sendPort]);
    [gUIBridgeThemeConnection setRootObject:gUIBridgeProxy];
    // Set delegate to enable multi-threading on child connections BEFORE they process messages
    [gUIBridgeThemeConnection setDelegate:gUIBridgeConnectionDelegate];
    // Allow independent request handling for thread safety
    [gUIBridgeThemeConnection setIndependentConversationQueueing:YES];
    // Enable multiple threads to allow handling requests from external processes
    [gUIBridgeThemeConnection enableMultipleThreads];
    
    // Also keep notification handler as backup
    [[NSNotificationCenter defaultCenter] addObserver:[self class]
                                             selector:@selector(_handleNewConnection:)
                                                 name:NSConnectionDidInitializeNotification
                                               object:nil];
    
    // Don't manually add ports to the runloop here - [registerName:] adds the
    // receive port in the standard modes.  The send port is for outgoing data
    // only and must NOT be polled.  Adding it to the runloop causes redundant
    // poll/recvmsg cycles on its socket fds, burning CPU on every event loop
    // iteration when no data is available.
    
    // NSLog(@"Eau: Ports will be registered via registerName:");
    
    BOOL ok = [gUIBridgeThemeConnection registerName:name];
    //NSLog(@"Eau: registerName returned: %d", ok);
    if (ok) {
      // NSLog(@"Eau: Successfully registered per-PID UIBridge theme service: %@", name);
    } else {
      NSLog(@"Eau: Failed to register per-PID UIBridge service as %@", name);
      gUIBridgeThemeConnection = nil;
    }
  } @catch (NSException *e) {
    NSLog(@"Eau: Exception during UIBridge registration: %@", e);
    gUIBridgeThemeConnection = nil;
  }
}

- (NSString *)_menuClientName
{
  if (menuClientName == nil)
    {
      pid_t pid = [[NSProcessInfo processInfo] processIdentifier];
      menuClientName = [[NSString alloc] initWithFormat:@"org.gnustep.Gershwin.MenuClient.%d", pid];
    }
  return menuClientName;
}

- (BOOL)_ensureMenuClientRegistered
{
  if (menuClientConnection != nil)
    {
      return YES;
    }

  menuClientConnection = [[NSConnection alloc] init];
  [menuClientConnection setRootObject:self];
  menuClientReceivePort = [menuClientConnection receivePort];
  
  // Don't manually add the port to the runloop - [registerName:] handles this.
  // Manual addPort: creates redundant socket fd polling on every event loop
  // iteration, wasting CPU.

  NSString *clientName = [self _menuClientName];
  BOOL registered = [menuClientConnection registerName:clientName];
  if (!registered)
    {
      NSDebugLog(@"Eau: Failed to register GNUstep menu client name: %@", clientName);
      if (menuClientReceivePort != nil)
        {
          menuClientReceivePort = nil;
        }
      menuClientConnection = nil;
      return NO;
    }

  // NSDebugLog(@"Eau: Registered GNUstep menu client as %@ with receive port %@", clientName, [menuClientConnection receivePort]);
  // NSDebugLog(@"Eau: Registered GNUstep menu client as %@ with receive port added to run loop", clientName);
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:menuClientConnection];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_menuClientConnectionDidDie:)
                                               name:NSConnectionDidDieNotification
                                             object:menuClientConnection];
  return YES;
}

- (BOOL)_ensureMenuServerConnection
{
  if (menuServerConnection != nil && ![menuServerConnection isValid])
    {
      menuServerConnection = nil;
      menuServerProxy = nil;
      menuServerConnected = NO;
    }

  if (menuServerProxy != nil)
    {
      return menuServerAvailable;
    }

  NSConnection *connection = [NSConnection connectionWithRegisteredName:@"org.gnustep.Gershwin.MenuServer"
                                                                   host:nil];
  if (connection == nil)
    {
      menuServerConnected = NO;
      return NO;
    }

  menuServerConnection = connection;

  id proxy = [menuServerConnection rootProxy];
  if (proxy != nil)
    {
      [proxy setProtocolForProxy:@protocol(GSGNUstepMenuServer)];
      menuServerProxy = proxy;
      menuServerConnected = YES;
      if (!menuServerAvailable)
        menuServerAvailable = YES;
      [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:menuServerConnection];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(_menuServerConnectionDidDie:)
                                                   name:NSConnectionDidDieNotification
                                                 object:menuServerConnection];
      // NSDebugLog(@"Eau: Connected to GNUstep menu server");
      return YES;
    }

  menuServerConnection = nil;
  menuServerConnected = NO;
  return NO;
}

- (NSNumber *)_windowIdentifierForWindow:(NSWindow *)window
{
  GSDisplayServer *server = GSServerForWindow(window);
  if (server == nil)
    {
      return nil;
    }

  int internalNumber = [window windowNumber];
  uint32_t deviceId = (uint32_t)(uintptr_t)[server windowDevice:internalNumber];

  return [NSNumber numberWithUnsignedInt:deviceId];
}

- (NSDictionary *)_serializeMenuItem:(NSMenuItem *)item
{
  if (item == nil)
    {
      return nil;
    }

  if ([item isSeparatorItem])
    {
      return [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                         forKey:@"isSeparator"];
    }

  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  [dict setObject:([item title] ?: @"") forKey:@"title"];
  [dict setObject:[NSNumber numberWithBool:[item isEnabled]] forKey:@"enabled"];
  [dict setObject:[NSNumber numberWithInteger:[item state]] forKey:@"state"];
  [dict setObject:([item keyEquivalent] ?: @"") forKey:@"keyEquivalent"];
  [dict setObject:[NSNumber numberWithUnsignedInteger:[item keyEquivalentModifierMask]]
           forKey:@"keyEquivalentModifierMask"];

  if ([item hasSubmenu])
    {
      NSDictionary *submenu = [self _serializeMenu:[item submenu]];
      if (submenu != nil)
        {
          [dict setObject:submenu forKey:@"submenu"];
        }
    }

  return dict;
}

- (NSDictionary *)_serializeMenu:(NSMenu *)menu
{
  if (menu == nil)
    {
      return nil;
    }

  // Recursively validate ALL items before serializing
  [self _recursiveMenuUpdate:menu];

  NSMutableArray *items = [NSMutableArray array];
  NSArray *itemArray = [menu itemArray];
  NSUInteger count = [itemArray count];

  for (NSUInteger i = 0; i < count; i++)
    {
      NSMenuItem *item = [itemArray objectAtIndex:i];
      NSDictionary *serialized = [self _serializeMenuItem:item];
      if (serialized != nil)
        {
          [items addObject:serialized];
        }
    }

  return [NSDictionary dictionaryWithObjectsAndKeys:
                      ([menu title] ?: @""), @"title",
                      items, @"items",
                      nil];
}

// Helper: serialize menu with index-paths so remote clients can refer to specific
// menu items deterministically.
- (NSDictionary *)_serializeMenuWithIndexPaths:(NSMenu *)menu
{
  if (menu == nil) return nil;
  NSMutableArray *items = [NSMutableArray array];
  NSArray *itemArray = [menu itemArray];
  for (NSUInteger i = 0; i < [itemArray count]; i++) {
    NSMenuItem *item = itemArray[i];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"title"] = ([item title] ?: @"");
    d[@"enabled"] = @([item isEnabled]);
    d[@"state"] = @([item state]);
    d[@"isSeparator"] = @([item isSeparatorItem]);
    d[@"indexPath"] = @[@(i)];
    if ([item hasSubmenu]) {
      d[@"submenu"] = [self _serializeMenuWithIndexPaths:[item submenu]];
    }
    [items addObject:d];
  }
  return @{ @"title": ([menu title] ?: @""), @"items": items };
}

// Helper: walk a serialized menu item tree and generate a unique ID for each
// item. Format: menuitem:<windowId>:<idx0>.<idx1>...
- (NSString *)_menuItemIDForWindow:(NSNumber *)windowId indexPath:(NSArray *)indexPath
{
  NSMutableArray *parts = [NSMutableArray array];
  for (NSNumber *n in indexPath) [parts addObject:[n stringValue]];
  NSString *path = [parts componentsJoinedByString:@"."];
  return [NSString stringWithFormat:@"menuitem:%@:%@", windowId ?: @0, path ?: @"0"];
}

- (NSMenuItem *)_menuItemForIndexPath:(NSArray *)indexPath inMenu:(NSMenu *)menu
{
  if (menu == nil || indexPath == nil || [indexPath count] == 0)
    {
      return nil;
    }

  NSMenu *currentMenu = menu;
  NSMenuItem *currentItem = nil;

  for (NSUInteger i = 0; i < [indexPath count]; i++)
    {
      NSNumber *indexNumber = [indexPath objectAtIndex:i];
      NSInteger index = [indexNumber integerValue];
      if (index < 0 || index >= [currentMenu numberOfItems])
        {
          return nil;
        }

      currentItem = [currentMenu itemAtIndex:index];
      if (i < [indexPath count] - 1)
        {
          if (![currentItem hasSubmenu])
            {
              return nil;
            }
          currentMenu = [currentItem submenu];
        }
    }

  return currentItem;
}

- (id)initWithBundle:(NSBundle *)bundle
{
  NSDebugLog(@"Eau: >>> initWithBundle ENTRY (before super init)");
  if ((self = [super initWithBundle:bundle]) != nil)
    {
      NSDebugLog(@"Eau: >>> initWithBundle after super init, self=%p", self);
      NSDebugLog(@"Eau: Initializing theme with bundle: %@", bundle);
      
      // Set shared instance for UIBridge service
      gSharedEauInstance = self;
      
      menuByWindowId = [[NSMutableDictionary alloc] init];
      menuServerAvailable = NO;
      menuServerConnected = NO;

      // Snapshot the current Menu process launch details so restarts can match.
      [[EauMenuRelaunchManager sharedManager] captureMenuProcessSnapshotIfAvailable];

      // Register as a GNUstep menu client so Menu.app can call back for actions
      [self _ensureMenuClientRegistered];

      // Try to connect to Menu.app's GNUstep menu server (may not be running yet)
      [self _ensureMenuServerConnection];
      
      // Register UIBridge service so server can query menus from theme
      // NSLog(@"Eau: Registering UIBridge service from initWithBundle");
      [[self class] _registerUIBridgeService:nil];

      // Observe menu changes so Menu.app can stay in sync
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(macintoshMenuDidChange:)
               name:@"NSMacintoshMenuDidChangeNotification"
             object:nil];

      // Observe window activation so Menu.app gets menus for newly active windows
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidBecomeKey:)
               name:@"NSWindowDidBecomeKeyNotification"
             object:nil];

      // After any menu selection finishes, push updated enabled/state values
      // to Menu.app so items like Copy/Paste reflect the new app state without
      // requiring the user to open a submenu first.
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(menuDidEndTracking:)
               name:NSMenuDidEndTrackingNotification
             object:nil];

      NSDebugLog(@"Eau: GNUstep menu IPC initialized (Menu.app %@)",
             menuServerAvailable ? @"available" : @"unavailable");

      // Ensure alternating row background color is visible in Eau theme
      // Note: System color list may be read-only, so we wrap in try-catch
      NSDebugLog(@"Eau: >>> About to check system color list");
      @try
        {
          NSColorList *systemColors = [NSColorList colorListNamed: @"System"];
          NSDebugLog(@"Eau: >>> System color list: %p, isEditable: %d",
                 systemColors, systemColors ? [systemColors isEditable] : -1);
          if (systemColors != nil && [systemColors isEditable])
            {
              NSDebugLog(@"Eau: >>> Setting alternateRowBackgroundColor");
              // Light gray with a touch of blue
              [systemColors setColor: [NSColor colorWithCalibratedRed: 0.94
                                                                 green: 0.95
                                                                  blue: 0.97
                                                                 alpha: 1.0]
                               forKey: @"alternateRowBackgroundColor"];
              NSDebugLog(@"Eau: >>> alternateRowBackgroundColor set successfully");
            }
          else
            {
              NSDebugLog(@"Eau: >>> Skipping color list modification (nil or not editable)");
            }
        }
      @catch (NSException *exception)
        {
          NSDebugLog(@"Eau: Could not set alternating row color: %@", [exception reason]);
        }
      // After ANY action is sent through a menu item (including keyboard
      // shortcuts matched to menu items), push updated enabled/state values
      // to Menu.app.  This is more efficient than a timer — we only push
      // when something might have changed.
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(menuDidSendAction:)
               name:NSMenuDidSendActionNotification
             object:nil];

      // Set up StepTalk scripting environment after app finishes
      // launching (safe: no +load or init-time hazards).
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(eau_setupStepTalkOnLaunch:)
               name:NSApplicationDidFinishLaunchingNotification
             object:nil];

      NSDebugLog(@"Eau: >>> initWithBundle EXIT");
    }
  return self;
}    

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  if (menuClientReceivePort != nil)
    {
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSDefaultRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSModalPanelRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSEventTrackingRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSRunLoopCommonModes];
      menuClientReceivePort = nil;
    }
}

- (void)_menuClientConnectionDidDie:(NSNotification *)notification
{
  NSDebugLog(@"Eau: Menu client connection died");
  NSDebugLog(@"Eau: Menu client connection died");
  if (menuClientReceivePort != nil)
    {
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSDefaultRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSModalPanelRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSEventTrackingRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSRunLoopCommonModes];
      menuClientReceivePort = nil;
    }
  menuClientConnection = nil;
}

- (void)_menuServerConnectionDidDie:(NSNotification *)notification
{
  NSDebugLog(@"Eau: Menu server connection died");
  NSDebugLog(@"Eau: Menu server connection died");
  menuServerConnection = nil;
  menuServerProxy = nil;
  menuServerConnected = NO;
  // Automatic Menu.app restart disabled.
  // [[EauMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
}

- (void) macintoshMenuDidChange: (NSNotification*)notification
{
  NSMenu *menu = [notification object];
  
  if ([NSApp mainMenu] == menu)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil)
        {
          NSDebugLog(@"Eau: Syncing GNUstep menu for key window: %@", keyWindow);
          [self setMenu: menu forWindow: keyWindow];
        }
      else
        {
          NSDebugLog(@"Eau: No key window available for menu change notification");
        }
    }
}

- (void) windowDidBecomeKey: (NSNotification*)notification
{
  NSWindow *window = [notification object];
  
  // When a window becomes key, send its menu to Menu.app
  // This ensures menus are available when the Menu component scans after window activation
  NSMenu *mainMenu = [NSApp mainMenu];

  if (mainMenu != nil && [mainMenu numberOfItems] > 0)
    {
      NSDebugLog(@"Eau: Window became key, syncing GNUstep menu: %@", window);
      [self setMenu: mainMenu forWindow: window];
    }
  else
    {
      NSDebugLog(@"Eau: Window became key but no main menu available: %@", window);
    }
}

+ (NSColor *) controlStrokeColor
{

  return [NSColor colorWithCalibratedRed: 0.4
                                   green: 0.4
                                    blue: 0.4
                                   alpha: 1];
}

- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state
{
  NSColor	*backgroundColor = [self buttonColorInCell: cell forState: state];
  NSColor* strokeColorButton = [Eau controlStrokeColor];
  NSGradient* buttonBackgroundGradient = [self _bezelGradientWithColor: backgroundColor];
  [buttonBackgroundGradient drawInBezierPath: path angle: -90];
  [strokeColorButton setStroke];
  [path setLineWidth: 1];
  [path stroke];
}

- (void) sendMenu:(NSWindow*)w {

  NSNumber *windowId = [self _windowIdentifierForWindow:w];
  NSDebugLog(@"Eau: sendMenu");
  NSMenu *m = [menuByWindowId objectForKey:windowId];

  @try
    {
      // NSDebugLog(@"Eau: Calling updateMenuForWindow on Menu.app server proxy");
      NSDictionary *menuData = [self _serializeMenu:m];

      [(id<GSGNUstepMenuServer>)menuServerProxy updateMenuForWindow:windowId
							   menuData:menuData
							 clientName:[self _menuClientName]];
      NSDebugLog(@"Eau: Successfully sent menu update to Menu.app");
      NSDebugLog(@"Eau: Updated GNUstep menu for window %@", windowId);
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"Eau: Exception sending GNUstep menu: %@, falling back to standard menu", exception);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
    }
  

}

#pragma mark - Menu state push

// Push only the enabled/state values for the current key window's menu to
// Menu.app without a full menu rebuild.  This is called after menu tracking
// ends so that PostScript/Paste/Select All etc. immediately update the menu
// bar when the user next looks at it.
- (void)_pushMenuEnabledStates
{
  if (!menuServerProxy) return;

  NSWindow *keyWindow = [NSApp keyWindow];
  if (!keyWindow) return;

  NSNumber *windowId = [self _windowIdentifierForWindow:keyWindow];
  if (!windowId) return;

  NSMenu *menu = [menuByWindowId objectForKey:windowId];
  if (!menu) return;

  @try
    {
      // Recursively validate ALL items (visible and hidden) before we push
      // states to Menu.app.  Without this, submenu items retain stale
      // enabled/state values.
      [self _recursiveMenuUpdate:menu];

      // Serialize with index paths — includes fresh enabled/state after [menu update]
      NSDictionary *menuData = [self _serializeMenuWithIndexPaths:menu];
      if (menuData)
        {
          [(id<GSGNUstepMenuServer>)menuServerProxy
            updateMenuEnabledStatesForWindow:windowId
                                    menuData:menuData
                                  clientName:[self _menuClientName]];
          NSDebugLog(@"Eau: Pushed enabled states for window %@", windowId);
        }
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"Eau: Exception pushing enabled states: %@", exception);
    }
}

// Recursively call [menu update] on the given menu and ALL its submenus,
// regardless of visibility.  GNUstep's built-in [NSMenu update] only calls
// _autoenableItem: on items in visible menus (via _updateSubmenu); hidden
// submenus keep stale enabled states.  This helper ensures every item in the
// tree gets fresh validation before we push states to Menu.app.
- (void)_recursiveMenuUpdate:(NSMenu *)menu
{
  if (!menu) return;
  [menu update];
  for (NSMenuItem *item in [menu itemArray])
    {
      if ([item hasSubmenu])
        {
          [self _recursiveMenuUpdate:[item submenu]];
        }
    }
}

// NSMenuDidSendActionNotification — fired after ANY action is sent through a
// menu item, including keyboard shortcuts that match menu items.  We push
// updated enabled/state to Menu.app so the menu bar is always current.
// This is more efficient than a polling timer — we only push when something
// might have changed.
- (void)menuDidSendAction:(NSNotification *)note
{
  (void)note;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self _pushMenuEnabledStates];
  });
}

// NSMenuDidEndTrackingNotification — fired after any menu tracking session
// finishes.  Extra safety net for cases where the action is sent outside
// the menu item path.
- (void)menuDidEndTracking:(NSNotification *)note
{
  (void)note;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self _pushMenuEnabledStates];
  });
}

- (void) eau_setupStepTalkOnLaunch:(NSNotification *)note
{
  (void)note;
  [NSApplication setupStepTalkScripting];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSApplicationDidFinishLaunchingNotification
                                                object:nil];
}

- (void) setMenu:(NSMenu*)m forWindow:(NSWindow*)w
{
  NSNumber *windowId = [self _windowIdentifierForWindow:w];
  if (windowId == nil)
    {
      NSDebugLog(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      NSDebugLog(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  if (m == nil || [m numberOfItems] == 0)
    {
      NSDebugLog(@"Eau: Menu is nil or empty (items=%ld)", (long)[m numberOfItems]);
      BOOL hadMenu = ([menuByWindowId objectForKey:windowId] != nil);
      [menuByWindowId removeObjectForKey:windowId];

      if (hadMenu && [self _ensureMenuServerConnection])
        {
          @try
            {
              NSDebugLog(@"Eau: Unregistering window %@ from Menu.app", windowId);
              [(id<GSGNUstepMenuServer>)menuServerProxy unregisterWindow:windowId
                                                                clientName:[self _menuClientName]];
            }
          @catch (NSException *exception)
            {
              NSDebugLog(@"Eau: Exception unregistering window %@: %@", windowId, exception);
              NSDebugLog(@"Eau: Exception unregistering window %@: %@", windowId, exception);
            }
        }

      NSDebugLog(@"Eau: Menu is nil or empty, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  // NSDebugLog(@"Eau: Storing menu in cache for windowId=%@, menu has %ld items", windowId, (long)[m numberOfItems]);
  // TOM: i believe this is redundant
  // [m update];

  [menuByWindowId setObject:m forKey:windowId];

  if (![self _ensureMenuClientRegistered])
    {
      NSDebugLog(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      NSDebugLog(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  if (![self _ensureMenuServerConnection])
    {
      NSDebugLog(@"Eau: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      NSDebugLog(@"Eau: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      // [[EauMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
      return;
    }

  // Rate-limited menu updating (coalesced to avoid messaging freed objects)
  gPendingMenuWindow = w;
  if (!gPendingMenuUpdate)
    {
      gPendingMenuUpdate = YES;
      [self performSelector: @selector(eau_sendPendingMenu)
                 withObject: nil
                 afterDelay: 0.1];
    }
}

- (void) eau_sendPendingMenu
{
  gPendingMenuUpdate = NO;
  NSWindow *win = gPendingMenuWindow;
  gPendingMenuWindow = nil;
  if (win)
    {
      [self sendMenu: win];
    }
}

- (void)_performMenuActionFromIPC:(NSDictionary *)info
{
  NSNumber *windowId = [info objectForKey:@"windowId"];
  NSArray *indexPath = [info objectForKey:@"indexPath"];

  if (windowId == nil || indexPath == nil)
    {
      return;
    }

  NSMenu *menu = [menuByWindowId objectForKey:windowId];
  if (menu == nil)
    {
      if ([menuByWindowId count] == 1)
        {
          menu = [[menuByWindowId allValues] firstObject];
        }
      else if ([menuByWindowId count] > 0)
        {
          menu = [[menuByWindowId allValues] firstObject];
        }

      if (menu == nil)
        {
          menu = [NSApp mainMenu];
        }

      if (menu == nil)
        {
          return;
        }
    }

  NSMenuItem *menuItem = [self _menuItemForIndexPath:indexPath inMenu:menu];
  if (menuItem == nil)
    {
      return;
    }

  if (![menuItem isEnabled])
    {
      return;
    }

  SEL action = [menuItem action];
  id target = [menuItem target];

  if (action == NULL)
    {
      return;
    }

  [NSApp sendAction:action to:target from:menuItem];
}

#pragma mark - UIBridgeProtocol (exposes only the frontmost/active window)

- (bycopy NSArray *)listMenus
{
  __block NSMutableArray *result = nil;
  
  void (^block)(void) = ^{
    result = [NSMutableArray array];
    
    // Get the key (frontmost) window
    NSWindow *keyWindow = [NSApp keyWindow];
    if (!keyWindow && [NSApp windows] && [[NSApp windows] count] > 0) {
      // Fallback to first window if no key window
      keyWindow = [[NSApp windows] objectAtIndex:0];
    }
    
    if (keyWindow) {
      NSNumber *winId = [self _windowIdentifierForWindow:keyWindow];
      if (winId) {
        NSMenu *m = [menuByWindowId objectForKey:winId];
        if (!m && [menuByWindowId count] > 0) {
          // Fallback: use the first cached menu
          m = [[menuByWindowId allValues] firstObject];
        }
        if (m) {
          NSDictionary *menuData = [self _serializeMenuWithIndexPaths:m];
          [result addObject:@{ @"windowId": winId, @"menu": menuData }];
        }
      }
    }

    // Also include the application's main menu (Application menu) as a global fallback
    NSMenu *appMainMenu = [NSApp mainMenu];
    if (appMainMenu) {
      // NSLog(@"Eau: Including application mainMenu as fallback");
      NSDictionary *appMenuData = [self _serializeMenuWithIndexPaths:appMainMenu];
      // Use nil windowId to indicate it's the global app menu
      [result addObject:@{ @"windowId": [NSNull null], @"menu": appMenuData }];
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSArray array];
}

- (bycopy NSString *)listMenusJSON
{
  NSArray *menus = [self listMenus];
  NSData *d = [NSJSONSerialization dataWithJSONObject:menus options:0 error:nil];
  if (!d) return @"null";
  return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

- (BOOL)invokeMenuItem:(NSString *)objID
{
  if (!objID || ![objID hasPrefix:@"menuitem:"]) return NO;
  
  // Expected format: menuitem:<windowId>:<idx0>.<idx1>...
  NSArray *parts = [objID componentsSeparatedByString:@":"];
  if ([parts count] < 3) return NO;
  NSString *windowStr = parts[1];
  NSString *pathStr = parts[2];
  NSNumber *windowId = @([windowStr longLongValue]);
  NSArray *components = [pathStr componentsSeparatedByString:@"."];
  NSMutableArray *indexPath = [NSMutableArray array];
  for (NSString *c in components) { [indexPath addObject:@([c integerValue])]; }
  
  // Call into existing menu activation code from main thread
  __block BOOL handled = NO;
  if ([NSThread isMainThread]) {
    @try {
      [self activateMenuItemAtPath:indexPath forWindow:windowId];
      handled = YES;
    } @catch (NSException *e) {
      NSLog(@"Eau: Exception in invokeMenuItem %@: %@", objID, e);
      handled = NO;
    }
  } else {
    dispatch_sync(dispatch_get_main_queue(), ^{
      @try {
        [self activateMenuItemAtPath:indexPath forWindow:windowId];
        handled = YES;
      } @catch (NSException *e) {
        NSLog(@"Eau: Exception in invokeMenuItem %@: %@", objID, e);
        handled = NO;
      }
    });
  }
  
  return handled;
}

- (bycopy id)rootObjects
{
  __block NSDictionary *result = nil;
  
  void (^block)(void) = ^{
    NSMutableArray *wins = [NSMutableArray array];
    for (NSWindow *w in [NSApp windows]) {
      NSMutableDictionary *d = [NSMutableDictionary dictionary];
      d[@"object_id"] = [self _objectIDForObject:w];
      d[@"class"] = NSStringFromClass([w class]);
      d[@"title"] = [w title] ?: @"";
      d[@"frame"] = NSStringFromRect([w frame]);
      d[@"windowNumber"] = @([w windowNumber]);
      d[@"hidden"] = @(![w isVisible]);
      [wins addObject:d];
    }
    result = @{
      @"NSApp": [self _objectIDForObject:NSApp],
      @"windows": wins
    };
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: @{ @"NSApp": @"", @"windows": @[] };
}

#pragma mark - UIBridge Object Serialization Helpers

- (NSString *)_objectIDForObject:(id)obj
{
  if (!obj) return @"";
  return [NSString stringWithFormat:@"objc:%p", obj];
}

- (id)_objectForID:(NSString *)objID
{
  if (![objID hasPrefix:@"objc:"]) return nil;
  unsigned long long ptrVal;
  NSScanner *scanner = [NSScanner scannerWithString:[objID substringFromIndex:5]];
  if ([scanner scanHexLongLong:&ptrVal]) {
    return (__bridge id)(void *)ptrVal;
  }
  return nil;
}

- (id)_serializeObject:(id)obj detailed:(BOOL)detailed depth:(int)depth
{
  if (!obj || obj == [NSNull null] || depth < 0) return [NSNull null];
  if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) return obj;
  
  NSString *className = @"Unknown";
  @try { className = NSStringFromClass([obj class]); } @catch (NSException *e) { }
  
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  dict[@"object_id"] = [self _objectIDForObject:obj];
  dict[@"class"] = className;
  
  // Handle NSView
  if ([obj isKindOfClass:[NSView class]]) {
    NSView *view = (NSView *)obj;
    NSRect frame = [view frame];
    dict[@"frame"] = NSStringFromRect(frame);
    dict[@"hidden"] = @([view isHidden]);
    
    // Get title for buttons
    if ([view respondsToSelector:@selector(title)]) {
      id title = [view performSelector:@selector(title)];
      if (title && ![title isEqual:@""]) dict[@"title"] = title;
    }
    // Get string value for text fields
    if ([view isKindOfClass:[NSTextField class]]) {
      NSTextField *tf = (NSTextField *)view;
      dict[@"stringValue"] = [tf stringValue] ?: @"";
      dict[@"string"] = [tf stringValue] ?: @"";
    }
    
    // Computed screen coordinates
    @try {
      if ([view window]) {
        NSRect winRect = [view convertRect:[view bounds] toView:nil];
        dict[@"window_frame"] = NSStringFromRect(winRect);
        
        NSRect screenRect = [[view window] convertRectToScreen:winRect];
        dict[@"screen_frame"] = NSStringFromRect(screenRect);
      }
    } @catch (NSException *e) { }
    
    // Control-specific properties
    if ([view isKindOfClass:[NSControl class]]) {
      NSControl *control = (NSControl *)view;
      dict[@"enabled"] = @([control isEnabled]);
      dict[@"tag"] = @([control tag]);
    }
    
    // Button-specific properties
    if ([view isKindOfClass:[NSButton class]]) {
      NSButton *button = (NSButton *)view;
      dict[@"keyEquivalent"] = [button keyEquivalent] ?: @"";
      dict[@"keyModifiers"] = @([button keyEquivalentModifierMask]);
    }
    
    // Recurse subviews if detailed
    if (detailed && depth > 0) {
      NSMutableArray *subviews = [NSMutableArray array];
      for (NSView *sub in [view subviews]) {
        [subviews addObject:[self _serializeObject:sub detailed:YES depth:depth - 1]];
      }
      dict[@"subviews"] = subviews;
    }
  }
  
  // Handle NSWindow
  if ([obj isKindOfClass:[NSWindow class]]) {
    NSWindow *win = (NSWindow *)obj;
    dict[@"title"] = [win title] ?: @"";
    dict[@"frame"] = NSStringFromRect([win frame]);
    dict[@"hidden"] = @(![win isVisible]);
    
    if (detailed && depth > 0) {
      dict[@"contentView"] = [self _serializeObject:[win contentView] detailed:YES depth:depth - 1];
    }
  }
  
  // Handle NSApplication
  if ([obj isKindOfClass:[NSApplication class]]) {
    NSApplication *app = (NSApplication *)obj;
    if (detailed && depth > 0) {
      NSMutableArray *wins = [NSMutableArray array];
      for (NSWindow *win in [app windows]) {
        [wins addObject:[self _serializeObject:win detailed:YES depth:depth - 1]];
      }
      dict[@"windows"] = wins;
    }
  }
  
  // Handle NSMenu
  if ([obj isKindOfClass:[NSMenu class]]) {
    NSMenu *menu = (NSMenu *)obj;
    dict[@"title"] = [menu title] ?: @"";
    if (detailed && depth > 0) {
      NSMutableArray *items = [NSMutableArray array];
      for (NSMenuItem *item in [menu itemArray]) {
        [items addObject:[self _serializeObject:item detailed:YES depth:depth - 1]];
      }
      dict[@"items"] = items;
    }
  }
  
  // Handle NSMenuItem
  if ([obj isKindOfClass:[NSMenuItem class]]) {
    NSMenuItem *item = (NSMenuItem *)obj;
    dict[@"title"] = [item title] ?: @"";
    dict[@"enabled"] = @([item isEnabled]);
    dict[@"hasSubmenu"] = @([item hasSubmenu]);
    dict[@"isSeparator"] = @([item isSeparatorItem]);
    if ([item action]) dict[@"action"] = NSStringFromSelector([item action]);
    if ([item keyEquivalent]) dict[@"keyEquivalent"] = [item keyEquivalent];
    dict[@"keyModifiers"] = @([item keyEquivalentModifierMask]);
    dict[@"tag"] = @([item tag]);
    dict[@"state"] = @([item state]);
    if ([item hasSubmenu] && detailed && depth > 0) {
      dict[@"submenu"] = [self _serializeObject:[item submenu] detailed:YES depth:depth - 1];
    }
  }
  
  return dict;
}

- (bycopy id)detailsForObject:(NSString *)objID
{
  __block id result = nil;
  
  void (^block)(void) = ^{
    // Handle menuitem: IDs
    if (objID && [objID hasPrefix:@"menuitem:"]) {
      NSArray *parts = [objID componentsSeparatedByString:@":"];
      if ([parts count] >= 3) {
        NSNumber *windowId = @([parts[1] longLongValue]);
        NSString *pathStr = parts[2];
        NSArray *components = [pathStr componentsSeparatedByString:@"."];
        NSMutableArray *indexPath = [NSMutableArray array];
        for (NSString *c in components) [indexPath addObject:@([c integerValue])];
        NSMenu *menu = [menuByWindowId objectForKey:windowId];
        if (!menu && [menuByWindowId count] > 0) menu = [[menuByWindowId allValues] firstObject];
        NSMenuItem *it = [self _menuItemForIndexPath:indexPath inMenu:menu];
        if (it) {
          result = [self _serializeObject:it detailed:YES depth:2];
          return;
        }
      }
    }
    
    // Handle objc: IDs
    id obj = [self _objectForID:objID];
    if (obj) {
      result = [self _serializeObject:obj detailed:YES depth:2];
    } else {
      result = [NSNull null];
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSNull null];
}

- (bycopy id)fullTreeForObject:(NSString *)objID
{
  __block id result = nil;
  
  void (^block)(void) = ^{
    id obj = nil;
    if (!objID || [objID length] == 0 || [objID isEqualToString:@"NSApp"]) {
      obj = NSApp;
    } else {
      obj = [self _objectForID:objID];
    }
    
    if (obj) {
      result = [self _serializeObject:obj detailed:YES depth:15];
    } else {
      // Fallback to menu tree for backwards compatibility
      result = @{ @"menus": [self listMenus] };
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSNull null];
}

- (bycopy id)invokeSelector:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args
{
  __block id result = nil;
  
  void (^block)(void) = ^{
    // Handle invokeMenuItemByID: special case
    if (selectorName && [selectorName isEqualToString:@"invokeMenuItemByID:"] && args && [args count] > 0) {
      NSString *menuId = args[0];
      BOOL ok = [self invokeMenuItem:menuId];
      result = ok ? @YES : @NO;
      return;
    }
    
    // General selector invocation
    id obj = [self _objectForID:objID];
    if (!obj) {
      result = @{ @"error": @{ @"code": @-32000, @"message": @"Object not found" } };
      return;
    }
    
    SEL sel = NSSelectorFromString(selectorName);
    if (![obj respondsToSelector:sel]) {
      result = @{ @"error": @{ @"code": @-32601, @"message": @"Selector not found" } };
      return;
    }
    
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];
    
    if (args && [args isKindOfClass:[NSArray class]]) {
      for (NSUInteger i = 0; i < [args count]; i++) {
        if (i + 2 >= [sig numberOfArguments]) break;
        id arg = args[i];
        if (arg == [NSNull null]) arg = nil;
        [inv setArgument:&arg atIndex:i + 2];
      }
    }
    
    @try {
      [inv invoke];
      
      if ([sig methodReturnLength] > 0) {
        const char *retType = [sig methodReturnType];
        if (retType[0] == '@' || retType[0] == '#') {
          id retVal = nil;
          [inv getReturnValue:&retVal];
          result = [self _serializeObject:retVal detailed:NO depth:1];
        } else {
          result = @"OK";
        }
      } else {
        result = @"OK";
      }
    } @catch (NSException *e) {
      result = @{ @"error": @{ @"code": @-32001, @"message": [e description] } };
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSNull null];
}

// JSON variants for compatibility
- (bycopy NSString *)rootObjectsJSON { NSData *d = [NSJSONSerialization dataWithJSONObject:[self rootObjects] options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }
- (bycopy NSString *)detailsForObjectJSON:(NSString *)objID { NSData *d = [NSJSONSerialization dataWithJSONObject:[self detailsForObject:objID] options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }
- (bycopy NSString *)fullTreeForObjectJSON:(NSString *)objID { NSData *d = [NSJSONSerialization dataWithJSONObject:[self fullTreeForObject:objID] options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }
- (bycopy NSString *)invokeSelectorJSON:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args { id r = [self invokeSelector:selectorName onObject:objID withArgs:args]; NSData *d = [NSJSONSerialization dataWithJSONObject:r options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }


- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath forWindow:(NSNumber *)windowId
{
  NSDebugLog(@"Eau: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  NSDebugLog(@"Eau: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  
  NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                           indexPath ?: [NSArray array], @"indexPath",
                           windowId ?: [NSNumber numberWithUnsignedInt:0], @"windowId",
                           nil];

  if (![NSThread isMainThread])
    {
      NSDebugLog(@"Eau: Not on main thread, dispatching to main thread");
      dispatch_async(dispatch_get_main_queue(), ^{
        [self _performMenuActionFromIPC:payload];
      });
      return;
    }

  NSDebugLog(@"Eau: On main thread, calling _performMenuActionFromIPC directly");
  [self _performMenuActionFromIPC:payload];
}

// Recursively collect @[title, enabled, state] triples from a menu tree.
// Returns a flat NSArray — no nested dictionaries — so it copies over DO
// in a single batch regardless of bycopy support.
- (NSArray *)_collectFlatStates:(NSMenu *)menu
{
  NSMutableArray *result = [NSMutableArray array];
  for (NSMenuItem *item in [menu itemArray]) {
    if ([item isSeparatorItem]) continue;
    NSString *title = [item title];
    if (!title || [title length] == 0) continue;
    [result addObject:@[ title, @([item isEnabled]), @([item state]) ]];
    if ([item hasSubmenu]) {
      [result addObjectsFromArray:[self _collectFlatStates:[item submenu]]];
    }
  }
  return result;
}

- (bycopy id)validateMenuStateForWindow:(NSNumber *)windowId
{
  NSDebugLog(@"Eau: validateMenuStateForWindow called - windowId: %@", windowId);

  if (![NSThread isMainThread])
    {
      __block id result = nil;
      dispatch_sync(dispatch_get_main_queue(), ^{
        result = [self validateMenuStateForWindow:windowId];
      });
      return result;
    }

  // Find the menu for this window
  NSMenu *menu = nil;
  if (windowId)
    {
      menu = [menuByWindowId objectForKey:windowId];
    }

  // Fallback: use key window's menu
  if (!menu)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow)
        {
          NSNumber *keyWinId = [self _windowIdentifierForWindow:keyWindow];
          if (keyWinId)
            {
              menu = [menuByWindowId objectForKey:keyWinId];
            }
        }
    }

  // Last resort: first cached menu
  if (!menu && [menuByWindowId count] > 0)
    {
      menu = [[menuByWindowId allValues] firstObject];
    }

  if (!menu)
    {
      NSDebugLog(@"Eau: validateMenuStateForWindow: no menu found for window %@", windowId);
      return nil;
    }

  // Recursively validate ALL items before collecting states
  [self _recursiveMenuUpdate:menu];

  // Return a flat array of @[title, enabled, state] triples.
  // No nested dictionaries — copies over DO in one batch instantly.
  NSArray *flat = [self _collectFlatStates:menu];
  NSDebugLog(@"Eau: validateMenuStateForWindow: returning %lu flat items for window %@",
         (unsigned long)[flat count], windowId);
  return flat;
}

- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId
{
  NSDebugLog(@"Eau: requestMenuUpdateForWindow called - windowId: %@", windowId);
  NSDebugLog(@"Eau: requestMenuUpdateForWindow called - windowId: %@", windowId);

  if (![NSThread isMainThread])
    {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self requestMenuUpdateForWindow:windowId];
      });
      return;
    }

  // Find the window and push its menu to Menu.app
  NSWindow *targetWindow = nil;
  for (NSWindow *w in [NSApp windows])
    {
      NSNumber *wid = [self _windowIdentifierForWindow:w];
      if (wid && [wid isEqualToNumber:windowId])
        {
          targetWindow = w;
          break;
        }
    }

  if (!targetWindow)
    {
      // Fallback: use key window
      targetWindow = [NSApp keyWindow];
    }

  if (targetWindow)
    {
      NSDebugLog(@"Eau: requestMenuUpdateForWindow: pushing menu for window %@", windowId);
      [self setMenu:[NSApp mainMenu] forWindow:targetWindow];
    }
  else
    {
      NSDebugLog(@"Eau: requestMenuUpdateForWindow: no window found for %@, cannot push", windowId);
    }
}

- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  // Always use Menu.app IPC when available
  if ((menuServerAvailable || gForceExternalMenuByEnv) && ([NSApp mainMenu] == menu))
    {
      NSDebugLog(@"Eau: Modifying menu rect for GNUstep IPC: hiding menu bar");
      return NSZeroRect;
    }
  
  NSDebugLog(@"Eau: Using standard menu rect (Menu.app %@)", menuServerAvailable ? @"available" : @"unavailable");
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  // Always use Menu.app IPC when available
  if ((menuServerAvailable || gForceExternalMenuByEnv) && ([NSApp mainMenu] == menu))
    {
      NSDebugLog(@"Eau: Proposing menu visibility NO for GNUstep IPC");
      return NO;
    }

  NSDebugLog(@"Eau: Proposing standard menu visibility %@ (Menu.app %@)",
         visibility ? @"YES" : @"NO", menuServerAvailable ? @"available" : @"unavailable");
  return [super proposedVisibility: visibility forMenu: menu];
}

/**
 * Override GSTheme's keyForKeyEquivalent: to convert GNUstep key equivalent
 * strings to Mac-style symbols with Shift shown after Command.
 *
 * The NSMenuItemCell _keyEquivalentString produces strings like "/#s" where
 * modifiers are single-character codes (^=Control, +=Alternate, /=Shift, #=Command)
 * ordered Control → Alternate → Shift → Command → Key.
 *
 * This override converts to Mac Unicode symbols (⌃⌥⌘⇧) and reorders to
 * Control → Alternate → Command → Shift → Key.
 */
- (NSString *) keyForKeyEquivalent: (NSString *)aString
{
  if (!aString || [aString length] == 0)
    {
      return aString;
    }

  // Parse standard GNUstep modifier codes from the front of the string
  //
  // Format: [^][+][/][#]key
  //         ^ = Control   += Alternate/Option   /= Shift   # = Command
  NSUInteger pos = 0;
  NSUInteger len = [aString length];
  BOOL hasControl = NO;
  BOOL hasAlternate = NO;
  BOOL hasShift = NO;
  BOOL hasCommand = NO;

  while (pos < len)
    {
      unichar ch = [aString characterAtIndex: pos];
      if (ch == '^')   { hasControl = YES;  pos++; }
      else if (ch == '+') { hasAlternate = YES; pos++; }
      else if (ch == '/') { hasShift = YES;    pos++; }
      else if (ch == '#') { hasCommand = YES;  pos++; }
      else { break; }
    }

  // Remaining characters are the key name
  NSString *key = [aString substringFromIndex: pos];

  // Build Mac-style string: Control ⌃ → Option ⌥ → Command ⌘ → Shift ⇧ → Key
  NSMutableString *result = [NSMutableString string];
  if (hasControl)  { [result appendString: @"⌃"]; }
  if (hasAlternate){ [result appendString: @"⌥"]; }
  if (hasCommand)  { [result appendString: @"⌘"]; }
  if (hasShift)    { [result appendString: @"⇧"]; }

  // Uppercase single-letter keys
  if ([key length] == 1)
    {
      unichar ch = [key characterAtIndex: 0];
      if (ch >= 'a' && ch <= 'z')
        {
          key = [key uppercaseString];
        }
    }

  [result appendString: key];
  return result;
}

@end
