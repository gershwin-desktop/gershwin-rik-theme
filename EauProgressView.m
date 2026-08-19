/*
 * EauProgressView.m
 * Eau Theme - animated progress bar view
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauProgressView.h"

#import <GNUstepGUI/GSTheme.h>
#import <math.h>

/* The classic bar look is owned by the theme (Eau+ProgressIndicator.m); this
 * category exposes it so the view can paint it unchanged and add waves on
 * top. */
@interface GSTheme (EauProgressIndicatorAccess)
- (void) drawProgressIndicator: (NSProgressIndicator*)progress
                    withBounds: (NSRect)bounds
                      withClip: (NSRect)rect
                       atCount: (int)count
                      forValue: (double)val;
@end

/* 30 FPS is plenty for the slow sweep; a faster timer just burns CPU. */
#define EAU_PROGRESS_FRAME_INTERVAL (1.0 / 30.0)
/* One full sweep; 1.5-2.5 s reads as "slow, continuous". */
#define EAU_PROGRESS_CYCLE_SECONDS 2.0
/* Wave band width, fixed in pixels so it never depends on the bar size. */
#define EAU_PROGRESS_SHEEN_BAND_WIDTH 32.0
/* Indeterminate bars travel broader waves across the full track. */
#define EAU_PROGRESS_INDETERMINATE_SHEEN_BAND_WIDTH 48.0
/* Centre-to-centre distance between waves, fixed in pixels: the frequency
 * is the same on every bar, whatever its size or progress. */
#define EAU_PROGRESS_WAVE_SPACING 40.0
/* Wave spacings scrolled per cycle: an integer keeps the wrap seamless and
 * the speed (spacings per second) constant, independent of fill width. */
#define EAU_PROGRESS_SCROLL_PER_CYCLE 2
/* Slight tilt so the highlight reads as a moving diagonal. */
#define EAU_PROGRESS_SHEEN_ANGLE -8.0

/* Indeterminate pattern frames advanced per animation cycle: the theme
 * picks the stripe image from the count we hand it, so it keeps moving at
 * about one 48 px tile per second, matching the wave speed. */
#define EAU_PROGRESS_INDETERMINATE_FRAMES_PER_CYCLE 12
#define EAU_PROGRESS_CORNER_RADIUS 3.0
#define EAU_PROGRESS_TRACK_INSET 1.0

@implementation EauProgressView

- (id) initWithFrame: (NSRect)frameRect
{
  self = [super initWithFrame: frameRect];
  if (self)
    {
      _minValue = 0.0;
      _maxValue = 1.0;
      _animated = YES;
    }
  return self;
}

- (void) dealloc
{
  /* The timer is weak here (the run loop owns it), but invalidating it is
   * still required so a view torn down while animating stops scheduling. */
  [_animationTimer invalidate];
}

- (BOOL) isFlipped
{
  return YES;
}

#pragma mark - Progress value

- (void) setDoubleValue: (double)value
{
  if (value < _minValue)
    value = _minValue;
  else if (value > _maxValue)
    value = _maxValue;
  if (_doubleValue != value)
    {
      _doubleValue = value;
      /* Crossing the full-progress line can stop or restart the sweep. */
      [self _updateAnimationTimer];
      [self setNeedsDisplay: YES];
    }
}

- (double) doubleValue
{
  return _doubleValue;
}

- (void) setMinValue: (double)value
{
  if (_minValue != value)
    {
      _minValue = value;
      [self setNeedsDisplay: YES];
    }
}

- (double) minValue
{
  return _minValue;
}

- (void) setMaxValue: (double)value
{
  if (_maxValue != value)
    {
      _maxValue = value;
      [self setNeedsDisplay: YES];
    }
}

- (double) maxValue
{
  return _maxValue;
}

- (double) _progressFraction
{
  double span = _maxValue - _minValue;
  if (span <= 0)
    return 0.0;
  double fraction = (_doubleValue - _minValue) / span;
  if (fraction < 0.0)
    return 0.0;
  if (fraction > 1.0)
    return 1.0;
  return fraction;
}

#pragma mark - Modes

- (void) setIndeterminate: (BOOL)flag
{
  if (_indeterminate != flag)
    {
      _indeterminate = flag;
      [self _updateAnimationTimer];
      [self setNeedsDisplay: YES];
    }
}

- (BOOL) isIndeterminate
{
  return _indeterminate;
}

- (void) setAnimated: (BOOL)animated
{
  if (_animated != animated)
    {
      _animated = animated;
      [self _updateAnimationTimer];
    }
}

- (BOOL) isAnimated
{
  return _animated;
}

- (void) setAnimatesWhenFinished: (BOOL)flag
{
  if (_animatesWhenFinished != flag)
    {
      _animatesWhenFinished = flag;
      [self _updateAnimationTimer];
    }
}

- (BOOL) animatesWhenFinished
{
  return _animatesWhenFinished;
}

- (void) setIndicator: (NSProgressIndicator *)indicator
{
  _indicator = indicator;
}

- (NSProgressIndicator *) indicator
{
  return _indicator;
}

#pragma mark - Animation

/* Starts or stops the timer based on whether a sweep is wanted right now.
 * Called whenever anything that feeds the decision changes, so the timer is
 * only ever running while the view is visible and actually animating. */
- (void) _updateAnimationTimer
{
  BOOL wantsAnimation = _animated
    && [self window] != nil
    && ![self isHidden]
    && (_indeterminate || [self _progressFraction] < 1.0
        || _animatesWhenFinished);

  if (wantsAnimation && _animationTimer == nil)
    {
      NSTimer *timer = [NSTimer timerWithTimeInterval: EAU_PROGRESS_FRAME_INTERVAL
                                               target: self
                                             selector: @selector(eau_animationTick:)
                                             userInfo: nil
                                              repeats: YES];
      /* Serve the modal and menu-tracking modes too, or the sweep would
       * stall while an alert is up or a menu is open. */
      NSRunLoop *loop = [NSRunLoop currentRunLoop];
      [loop addTimer: timer forMode: NSDefaultRunLoopMode];
      [loop addTimer: timer forMode: NSModalPanelRunLoopMode];
      [loop addTimer: timer forMode: NSEventTrackingRunLoopMode];
      _animationTimer = timer;
      _lastTickTime = [NSDate timeIntervalSinceReferenceDate];
    }
  else if (!wantsAnimation && _animationTimer != nil)
    {
      [_animationTimer invalidate];
      _animationTimer = nil;
      _lastTickTime = 0;
    }
}

- (void) eau_animationTick: (NSTimer *)timer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  if (_lastTickTime > 0)
    {
      NSTimeInterval delta = now - _lastTickTime;
      /* A long pause (app suspended, modal wait) must not make the sheen
       * jump ahead; drop the frame instead of snapping the phase. */
      if (delta >= 0 && delta < 2.0)
        {
          _animationPhase += delta / EAU_PROGRESS_CYCLE_SECONDS;
          if (_animationPhase >= 1.0)
            _animationPhase -= floor(_animationPhase);
        }
    }
  _lastTickTime = now;
  [self setNeedsDisplay: YES];
}

- (void) viewWillMoveToWindow: (NSWindow *)newWindow
{
  [super viewWillMoveToWindow: newWindow];
  [self _updateAnimationTimer];
}

- (void) setHidden: (BOOL)flag
{
  [super setHidden: flag];
  [self _updateAnimationTimer];
}

- (void) setFrameSize: (NSSize)newSize
{
  [super setFrameSize: newSize];
  _trackPath = nil;
  [self setNeedsDisplay: YES];
}

#pragma mark - Drawing

- (NSGradient *) _sheenGradient
{
  if (_sheenGradient == nil)
    {
      /* Soft profile: transparent -> faint white -> brighter -> faint -> none. */
      _sheenGradient = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithCalibratedWhite: 1.0 alpha: 0.0], 0.0,
        [NSColor colorWithCalibratedWhite: 1.0 alpha: 0.22], 0.4,
        [NSColor colorWithCalibratedWhite: 1.0 alpha: 0.34], 0.5,
        [NSColor colorWithCalibratedWhite: 1.0 alpha: 0.22], 0.6,
        [NSColor colorWithCalibratedWhite: 1.0 alpha: 0.0], 1.0, nil];
    }
  return _sheenGradient;
}

- (NSBezierPath *) _trackPath
{
  NSRect bounds = [self bounds];
  if (_trackPath == nil || !NSEqualRects(_cachedPathBounds, bounds))
    {
      NSRect track = NSInsetRect(bounds, EAU_PROGRESS_TRACK_INSET, EAU_PROGRESS_TRACK_INSET);
      CGFloat radius = MIN(EAU_PROGRESS_CORNER_RADIUS, NSHeight(track) / 2.0);
      _trackPath = [NSBezierPath bezierPathWithRoundedRect: track
                                                   xRadius: radius
                                                   yRadius: radius];
      _cachedPathBounds = bounds;
    }
  return _trackPath;
}

- (void) drawRect: (NSRect)rect
{
  NSRect bounds = [self bounds];
  if (NSIsEmptyRect(bounds))
    return;

  /* 1. The classic theme bar, painted exactly as the theme paints it: track,
   * glossy fill, indeterminate pattern, border, and fill-edge divider.  The
   * count for the indeterminate pattern frames comes from our sweep so the
   * stripe keeps moving. */
  if (_indicator != nil)
    {
      int count = (int)(_animationPhase
                        * EAU_PROGRESS_INDETERMINATE_FRAMES_PER_CYCLE);
      [[GSTheme theme] drawProgressIndicator: _indicator
                                  withBounds: bounds
                                    withClip: bounds
                                     atCount: count
                                    forValue: [self _progressFraction]];
    }

  /* 2. The travelling waves are the only thing this view adds.  They sweep
   * over the whole track and are revealed by the clip as the fill advances,
   * so growing progress never shifts them; the rounded path keeps them
   * inside the bar. */
  if (_animated && _animationTimer != nil)
    {
      [NSGraphicsContext saveGraphicsState];
      [[self _trackPath] addClip];
      if (!_indeterminate)
        {
          NSRect fillRect = bounds;
          fillRect.size.width = NSWidth(bounds) * [self _progressFraction];
          if (!NSIsEmptyRect(fillRect))
            {
              NSRectClip(fillRect);
              [self _drawWavesInRect: bounds];
            }
        }
      else
        {
          [self _drawWavesInRect: bounds];
        }
      [NSGraphicsContext restoreGraphicsState];
    }
}

- (void) _drawWavesInRect: (NSRect)coverageRect
{
  CGFloat coverageWidth = NSWidth(coverageRect);
  CGFloat spacing = EAU_PROGRESS_WAVE_SPACING;
  if (coverageWidth <= 0 || spacing <= 0)
    return;

  CGFloat bandWidth = _indeterminate
    ? EAU_PROGRESS_INDETERMINATE_SHEEN_BAND_WIDTH
    : EAU_PROGRESS_SHEEN_BAND_WIDTH;

  /* Waves form a periodic pattern that scrolls left by a whole number of
   * spacings per cycle, so the wrap is seamless and the speed is constant:
   * neither the distance between waves nor their speed depends on the bar
   * size or on how far the fill has advanced.  The pattern is anchored to
   * the whole bar (never to the fill edge), so a growing fill merely
   * reveals more of it instead of shifting it.  The loop covers the bar
   * plus one spacing of margin so waves enter and leave smoothly. */
  CGFloat scroll = _animationPhase * EAU_PROGRESS_SCROLL_PER_CYCLE * spacing;
  CGFloat baseX = NSMaxX(coverageRect) - scroll;
  NSInteger iMin = (NSInteger)ceil((NSMinX(coverageRect) - spacing - baseX) / spacing);
  NSInteger iMax = (NSInteger)floor((NSMaxX(coverageRect) + spacing - baseX) / spacing);

  NSInteger i;
  for (i = iMin; i <= iMax; i++)
    {
      NSRect bandRect = NSMakeRect(baseX + i * spacing, NSMinY(coverageRect),
                                   bandWidth, NSHeight(coverageRect));

      [NSGraphicsContext saveGraphicsState];
      NSAffineTransform *transform = [NSAffineTransform transform];
      NSPoint center = NSMakePoint(NSMidX(bandRect), NSMidY(bandRect));
      [transform translateXBy: center.x yBy: center.y];
      [transform rotateByDegrees: EAU_PROGRESS_SHEEN_ANGLE];
      [transform translateXBy: -center.x yBy: -center.y];
      [transform concat];

      [[self _sheenGradient] drawFromPoint: NSMakePoint(NSMinX(bandRect), NSMidY(bandRect))
                                   toPoint: NSMakePoint(NSMaxX(bandRect), NSMidY(bandRect))
                                   options: 0];
      [NSGraphicsContext restoreGraphicsState];
    }
}

@end