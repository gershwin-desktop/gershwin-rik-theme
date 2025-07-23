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
      
      // Add notification observer for menu changes
      [[NSNotificationCenter defaultCenter] 
        addObserver: self
           selector: @selector(macintoshMenuDidChange:)
               name: @"NSMacintoshMenuDidChangeNotification"
             object: nil];
    }
  return self;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [super dealloc];
}

- (void) macintoshMenuDidChange: (NSNotification*)notification
{
  NSMenu *menu = [notification object];
  
  if (([NSApp mainMenu] == menu) && menuRegistry != nil)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil)
        {
          [self setMenu: menu forWindow: keyWindow];
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
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      return NSZeroRect;
    }
  
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      return NO;
    }
  
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
