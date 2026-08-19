/*
 * EauProgressView.h
 * Eau Theme - animated progress bar view
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

/* Animated progress bar: the theme draws the classic bar (track, fill,
 * pattern, border) unchanged; this view only adds the travelling highlight
 * waves on top. */
@interface EauProgressView : NSView
{
  double _doubleValue;
  double _minValue;
  double _maxValue;
  BOOL _indeterminate;
  BOOL _animated;
  BOOL _animatesWhenFinished;
  CGFloat _animationPhase;
  NSTimeInterval _lastTickTime;
  NSTimer *__weak _animationTimer;
  NSProgressIndicator *__weak _indicator;

  double _displayedFraction;
  double _targetFraction;
  double _valueTweenFrom;
  NSTimeInterval _tweenStartTime;
  BOOL _displayedFractionInitialized;

  NSGradient *_sheenGradient;
  NSBezierPath *_trackPath;
  NSRect _cachedPathBounds;
}

- (void) setDoubleValue: (double)value;
- (double) doubleValue;

- (void) setMinValue: (double)value;
- (double) minValue;
- (void) setMaxValue: (double)value;
- (double) maxValue;

- (void) setIndeterminate: (BOOL)flag;
- (BOOL) isIndeterminate;

- (void) setAnimated: (BOOL)animated;
- (BOOL) isAnimated;

/* The indicator this view renders over; used to ask the theme to draw the
 * classic bar so only the waves are ours. */
- (void) setIndicator: (NSProgressIndicator *)indicator;
- (NSProgressIndicator *) indicator;

/* Keep the sheen sweeping even when a determinate bar reaches full progress.
 * Default NO: the animation stops at progress 1.0. */
- (void) setAnimatesWhenFinished: (BOOL)flag;
- (BOOL) animatesWhenFinished;

@end