/*
 * NSProgressIndicator+Eau.m
 * Eau Theme - animated progress indicator
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauProgressView.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/* Bar-style progress indicators are drawn by a hosted EauProgressView so the
 * sheen can sweep continuously.  Spinning indicators, vertical bars, and
 * unbeweled bars keep the theme's regular drawing path. */
static char EauEauProgressViewKey;
static char EauIndicatorAnimatingKey;

static BOOL EauProgressIndicatorHostsView(NSProgressIndicator *indicator)
{
  return [indicator style] == NSProgressIndicatorBarStyle
    && [indicator isBezeled]
    && ![indicator isVertical];
}

/* Lazily creates and hosts the EauProgressView once per indicator; the
 * associated-object reference releases it with the indicator. */
static EauProgressView *EauEauProgressViewFor(NSProgressIndicator *indicator)
{
  EauProgressView *progressView =
    objc_getAssociatedObject(indicator, &EauEauProgressViewKey);
  if (progressView == nil)
    {
      progressView = [[EauProgressView alloc] initWithFrame: [indicator bounds]];
      [progressView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      /* The view asks the theme to draw the classic bar, so it needs to
       * know which indicator it is rendering for. */
      [progressView setIndicator: indicator];
      [indicator addSubview: progressView];
      objc_setAssociatedObject(indicator, &EauEauProgressViewKey, progressView,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  return progressView;
}

@interface NSProgressIndicator (Eau)

- (instancetype) eau_initWithFrame: (NSRect)frameRect __attribute__((objc_method_family(init)));
- (id) eau_initWithCoder: (NSCoder *)aDecoder __attribute__((objc_method_family(init)));
- (void) eau_setDoubleValue: (double)value;
- (void) eau_setMinValue: (double)value;
- (void) eau_setMaxValue: (double)value;
- (void) eau_setIndeterminate: (BOOL)flag;
- (void) eau_setBezeled: (BOOL)flag;
- (void) eau_setStyle: (NSProgressIndicatorStyle)style;
- (void) eau_setVertical: (BOOL)flag;
- (void) eau_setDisplayedWhenStopped: (BOOL)flag;
- (void) eau_setHidden: (BOOL)flag;
- (void) eau_drawRect: (NSRect)rect;
- (void) eau_animate: (id)sender;
- (void) eau_startAnimation: (id)sender;
- (void) eau_stopAnimation: (id)sender;
- (void) eau_syncProgressView;
- (BOOL) eau_indicatorAnimating;
- (void) setEauIndicatorAnimating: (BOOL)flag;

@end

@implementation NSProgressIndicator (Eau)

+ (void) load
{
  Class cls = [NSProgressIndicator class];

  EauSwizzle(cls, @selector(initWithFrame:), @selector(eau_initWithFrame:));
  EauSwizzle(cls, @selector(initWithCoder:), @selector(eau_initWithCoder:));
  EauSwizzle(cls, @selector(setDoubleValue:), @selector(eau_setDoubleValue:));
  EauSwizzle(cls, @selector(setMinValue:), @selector(eau_setMinValue:));
  EauSwizzle(cls, @selector(setMaxValue:), @selector(eau_setMaxValue:));
  EauSwizzle(cls, @selector(setIndeterminate:), @selector(eau_setIndeterminate:));
  EauSwizzle(cls, @selector(setBezeled:), @selector(eau_setBezeled:));
  EauSwizzle(cls, @selector(setStyle:), @selector(eau_setStyle:));
  EauSwizzle(cls, @selector(setVertical:), @selector(eau_setVertical:));
  EauSwizzle(cls, @selector(setDisplayedWhenStopped:), @selector(eau_setDisplayedWhenStopped:));
  EauSwizzle(cls, @selector(setHidden:), @selector(eau_setHidden:));
  EauSwizzle(cls, @selector(drawRect:), @selector(eau_drawRect:));
  EauSwizzle(cls, @selector(animate:), @selector(eau_animate:));
  EauSwizzle(cls, @selector(startAnimation:), @selector(eau_startAnimation:));
  EauSwizzle(cls, @selector(stopAnimation:), @selector(eau_stopAnimation:));
}

static void EauSwizzle(Class cls, SEL original, SEL swizzled)
{
  Method origMethod = class_getInstanceMethod(cls, original);
  Method swizMethod = class_getInstanceMethod(cls, swizzled);
  if (!origMethod || !swizMethod)
    return;

  /* Adding the category implementation under the original selector first
   * overrides inherited methods (setHidden: comes from NSView) on this class
   * only instead of swapping them globally for every NSView. */
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

- (instancetype) eau_initWithFrame: (NSRect)frameRect
{
  // Call the original implementation, which is now named eau_initWithFrame:.
  self = [self eau_initWithFrame: frameRect];
  if (self)
    [self eau_syncProgressView];
  return self;
}

- (id) eau_initWithCoder: (NSCoder *)aDecoder
{
  self = [self eau_initWithCoder: aDecoder];
  if (self)
    [self eau_syncProgressView];
  return self;
}

- (void) eau_setDoubleValue: (double)value
{
  [self eau_setDoubleValue: value];
  [self eau_syncProgressView];
}

- (void) eau_setMinValue: (double)value
{
  [self eau_setMinValue: value];
  [self eau_syncProgressView];
}

- (void) eau_setMaxValue: (double)value
{
  [self eau_setMaxValue: value];
  [self eau_syncProgressView];
}

- (void) eau_setIndeterminate: (BOOL)flag
{
  [self eau_setIndeterminate: flag];
  [self eau_syncProgressView];
}

- (void) eau_setBezeled: (BOOL)flag
{
  [self eau_setBezeled: flag];
  [self eau_syncProgressView];
}

- (void) eau_setStyle: (NSProgressIndicatorStyle)style
{
  [self eau_setStyle: style];
  [self eau_syncProgressView];
}

- (void) eau_setVertical: (BOOL)flag
{
  [self eau_setVertical: flag];
  [self eau_syncProgressView];
}

- (void) eau_setDisplayedWhenStopped: (BOOL)flag
{
  [self eau_setDisplayedWhenStopped: flag];
  [self eau_syncProgressView];
}

- (void) eau_setHidden: (BOOL)flag
{
  [self eau_setHidden: flag];
  [self eau_syncProgressView];
}

- (void) eau_drawRect: (NSRect)rect
{
  if (EauProgressIndicatorHostsView(self))
    {
      /* The hosted EauProgressView renders the whole bar; drawing the theme
       * progress indicator here would paint over it. */
      return;
    }
  [self eau_drawRect: rect];
}

- (void) eau_animate: (id)sender
{
  if (EauProgressIndicatorHostsView(self))
    {
      /* The hosted view animates itself; the indicator's own animation loop
       * has nothing to repaint and its frame count is not used. */
      return;
    }
  [self eau_animate: sender];
}

- (void) eau_startAnimation: (id)sender
{
  [self eau_startAnimation: sender];
  [self setEauIndicatorAnimating: YES];
  [self eau_syncProgressView];
}

- (void) eau_stopAnimation: (id)sender
{
  [self eau_stopAnimation: sender];
  [self setEauIndicatorAnimating: NO];
  [self eau_syncProgressView];
}

- (BOOL) eau_indicatorAnimating
{
  NSNumber *flag = objc_getAssociatedObject(self, &EauIndicatorAnimatingKey);
  return flag ? [flag boolValue] : NO;
}

- (void) setEauIndicatorAnimating: (BOOL)flag
{
  objc_setAssociatedObject(self, &EauIndicatorAnimatingKey, @(flag),
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void) eau_syncProgressView
{
  EauProgressView *progressView = EauEauProgressViewFor(self);
  BOOL hostsView = EauProgressIndicatorHostsView(self);

  [progressView setHidden: (!hostsView || [self isHidden])];
  if (!hostsView)
    return;

  [progressView setMinValue: [self minValue]];
  [progressView setMaxValue: [self maxValue]];
  [progressView setDoubleValue: [self doubleValue]];
  [progressView setIndeterminate: [self isIndeterminate]];
  /* Determinate bars sweep their sheen continuously; indeterminate bars only
   * animate while the app's startAnimation: is active, matching GNUstep. */
  [progressView setAnimated: ([self isIndeterminate]
                              ? [self eau_indicatorAnimating]
                              : YES)];
}

@end