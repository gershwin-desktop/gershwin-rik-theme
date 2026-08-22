/*
 * NSComboBox+Eau.m
 *
 * Auto-selects the only item of a combo box that has exactly one option, so a
 * field that offers no real choice is never left blank: the single option is
 * selected and shown in the text part.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/NSComboBox.h>
#import <objc/runtime.h>

@interface NSComboBox (EauSingleItem)

- (id) eau_initWithCoder: (NSCoder *)aDecoder __attribute__((objc_method_family(init)));
- (void) eau_addItemWithObjectValue: (id)object;
- (void) eau_addItemsWithObjectValues: (NSArray *)objects;
- (void) eau_insertItemWithObjectValue: (id)object atIndex: (NSInteger)index;
- (void) eau_removeItemAtIndex: (NSInteger)index;
- (void) eau_removeItemWithObjectValue: (id)object;
- (void) eau_removeAllItems;
- (void) eau_reloadData;
- (void) eau_noteNumberOfItemsChanged;
- (void) eau_selectOnlyItemIfPresent;

@end

static void EauSwizzle(Class cls, SEL original, SEL swizzled);

@implementation NSComboBox (EauSingleItem)

+ (void) load
{
  Class cls = [NSComboBox class];

  EauSwizzle(cls, @selector(initWithCoder:), @selector(eau_initWithCoder:));
  EauSwizzle(cls, @selector(addItemWithObjectValue:), @selector(eau_addItemWithObjectValue:));
  EauSwizzle(cls, @selector(addItemsWithObjectValues:), @selector(eau_addItemsWithObjectValues:));
  EauSwizzle(cls, @selector(insertItemWithObjectValue:atIndex:), @selector(eau_insertItemWithObjectValue:atIndex:));
  EauSwizzle(cls, @selector(removeItemAtIndex:), @selector(eau_removeItemAtIndex:));
  EauSwizzle(cls, @selector(removeItemWithObjectValue:), @selector(eau_removeItemWithObjectValue:));
  EauSwizzle(cls, @selector(removeAllItems), @selector(eau_removeAllItems));
  EauSwizzle(cls, @selector(reloadData), @selector(eau_reloadData));
  EauSwizzle(cls, @selector(noteNumberOfItemsChanged), @selector(eau_noteNumberOfItemsChanged));
}

static void EauSwizzle(Class cls, SEL original, SEL swizzled)
{
  Method origMethod = class_getInstanceMethod(cls, original);
  Method swizMethod = class_getInstanceMethod(cls, swizzled);
  if (!origMethod || !swizMethod)
    return;

  /* Adding the category implementation under the original selector first
   * overrides inherited methods (initWithCoder: comes from NSControl) on this
   * class only instead of swapping them globally for every control. */
  BOOL didAdd = class_addMethod(cls, original,
                                method_getImplementation(swizMethod),
                                method_getTypeEncoding(swizMethod));
  if (didAdd)
    class_replaceMethod(cls, swizzled,
                        method_getImplementation(origMethod),
                        method_getTypeEncoding(origMethod));
  else
    method_exchangeImplementations(origMethod, swizMethod);
}

- (id) eau_initWithCoder: (NSCoder *)aDecoder
{
  // Call the original implementation, which is now named eau_initWithCoder:.
  self = [self eau_initWithCoder: aDecoder];
  if (self)
    [self eau_selectOnlyItemIfPresent];
  return self;
}

- (void) eau_addItemWithObjectValue: (id)object
{
  [self eau_addItemWithObjectValue: object];
  [self eau_selectOnlyItemIfPresent];
}

- (void) eau_addItemsWithObjectValues: (NSArray *)objects
{
  [self eau_addItemsWithObjectValues: objects];
  [self eau_selectOnlyItemIfPresent];
}

- (void) eau_insertItemWithObjectValue: (id)object atIndex: (NSInteger)index
{
  [self eau_insertItemWithObjectValue: object atIndex: index];
  [self eau_selectOnlyItemIfPresent];
}

- (void) eau_removeItemAtIndex: (NSInteger)index
{
  [self eau_removeItemAtIndex: index];
  [self eau_selectOnlyItemIfPresent];
}

- (void) eau_removeItemWithObjectValue: (id)object
{
  [self eau_removeItemWithObjectValue: object];
  [self eau_selectOnlyItemIfPresent];
}

- (void) eau_removeAllItems
{
  [self eau_removeAllItems];
  [self eau_selectOnlyItemIfPresent];
}

- (void) eau_reloadData
{
  [self eau_reloadData];
  [self eau_selectOnlyItemIfPresent];
}

- (void) eau_noteNumberOfItemsChanged
{
  [self eau_noteNumberOfItemsChanged];
  [self eau_selectOnlyItemIfPresent];
}

// When the combo box ends up with exactly one option there is nothing to
// choose from, so select it and show it in the text part instead of leaving
// the field empty. This runs after any change to the item list.
- (void) eau_selectOnlyItemIfPresent
{
  if ([self numberOfItems] != 1)
    return;

  if ([self indexOfSelectedItem] != 0)
    [self selectItemAtIndex: 0];

  // objectValue works for both the built-in item list and data source mode;
  // itemObjectValueAtIndex: is invalid (returns nil) when usesDataSource is YES.
  id value = [self objectValue];
  NSString *stringValue = nil;
  if ([value isKindOfClass: [NSString class]])
    stringValue = value;
  else if ([value respondsToSelector: @selector(stringValue)])
    stringValue = [value stringValue];

  if (stringValue && ![[self stringValue] isEqualToString: stringValue])
    [self setStringValue: stringValue];
}

@end