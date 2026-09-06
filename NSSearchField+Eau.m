/**
 * Copyright (C) 2013 Alessandro Sangiuliano
 * Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
 * Date: 31 December 2013
 */

#import "Eau.h"
#import "NSSearchField+Eau.h"
#import <objc/runtime.h>

@implementation NSSearchField (EauTheme)

+ (void) load
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class searchCls = [NSSearchField class];
    SEL keySel = @selector(keyDown:);
    Method km = class_getInstanceMethod(searchCls, keySel);
    if (km)
      {
        SEL swizSel = @selector(eau_keyDown:);
        Method swizm = class_getInstanceMethod(searchCls, swizSel);
        if (swizm)
          method_exchangeImplementations(km, swizm);
      }
  });
}

- (void) eau_clearSearch
{
  NSSearchFieldCell *cell = [self cell];
  [[self window] makeFirstResponder: nil];  // End editing
  [NSApp sendAction: [self action] to: [self target] from: self];
  [cell setStringValue: @""];

  NSText *editor = [self currentEditor];
  if (editor != nil)
    [editor setString: @""];

  [[NSNotificationCenter defaultCenter] postNotificationName: NSControlTextDidChangeNotification
                                                      object: self];
  [self setNeedsDisplay: YES];
}

- (void) eau_keyDown: (NSEvent*)theEvent
{
  NSString *chars = [theEvent charactersIgnoringModifiers];
  if ([chars length] == 1 && [chars characterAtIndex: 0] == 0x1B)
    {
      if ([[[self cell] stringValue] length] > 0)
        {
          [self eau_clearSearch];
          return;
        }
    }
  [self eau_keyDown: theEvent];
}

@end