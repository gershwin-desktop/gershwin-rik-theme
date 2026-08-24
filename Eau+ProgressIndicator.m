#include "Eau.h"

@protocol EauDockService
- (void)setProgressValue:(double)value;
- (void)setProgressVisible:(BOOL)visible;
@end

@interface Eau(EauProgressIndicator)

@end

@interface Eau(EauDockProgress)
- (void)reportDockProgress:(double)value;
- (void)resetDockHideTimer;
- (void)hideDockProgress:(NSTimer *)timer;
@end

// Mirror an app's progress bar into its Dock icon via the DockIcon DO service
// (Workspace's Dock, see DockService.m).  Eau runs inside every app, so the
// service resolves the caller and updates that app's own Dock icon.  Value is
// throttled to changes; a timer hides the Dock bar a while after the last
// draw, so a finished or removed indicator does not stay stuck on the icon.
#define EAU_DOCK_HIDE_DELAY 2.0
static id<EauDockService> dockProgressProxy = nil;
static double lastDockValue = -2.0;   /* sentinel: nothing reported yet */
static NSTimer *dockHideTimer = nil;
static NSTimeInterval lastDockConnectAttempt = 0.0;

static id<EauDockService> EauDockProgressProxy(void)
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  if (dockProgressProxy == nil && (now - lastDockConnectAttempt) > 5.0)
    {
      /* Retry every few seconds so an app that starts before the Dock is
       * still able to pick the service up once the Dock is running. */
      lastDockConnectAttempt = now;
      NSConnection *conn =
        [NSConnection connectionWithRegisteredName:@"DockIcon" host:nil];
      if (conn)
        {
          dockProgressProxy = (id<EauDockService>)[conn rootProxy];
        }
    }
  return dockProgressProxy;
}

@implementation Eau(EauProgressIndicator)


// progress indicator drawing methods
static NSColor *fillColour = nil;
#define MaxCount 10
static int indeterminateMaxCount = MaxCount;
static int spinningMaxCount = MaxCount;
static NSColor *indeterminateColors[MaxCount];
static NSImage *spinningImages[MaxCount];

- (void) initProgressIndicatorDrawing
{
  int i;

  // FIXME: Should come from defaults and should be reset when defaults change
  // FIXME: Should probably get the color from the color extension list (see NSToolbar)
  fillColour = [NSColor controlShadowColor];

  // Load images for indeterminate style
  for (i = 0; i < MaxCount; i++)
    {
      NSString *imgName = [NSString stringWithFormat: @"common_ProgressIndeterminate_%d", i + 1];
      NSImage *image = [NSImage imageNamed: imgName];

      if (image == nil)
        {
          indeterminateMaxCount = i;
          break;
        }
          indeterminateColors[i] = [NSColor colorWithPatternImage: image];
    }

  // Load images for spinning style
  for (i = 0; i < MaxCount; i++)
    {
      NSString *imgName = [NSString stringWithFormat: @"common_ProgressSpinning_%d", i + 1];
      NSImage *image = [NSImage imageNamed: imgName];

      if (image == nil)
        {
          spinningMaxCount = i;
          break;
        }
      spinningImages[i] = image;
    }
}

- (void) drawProgressIndicator: (NSProgressIndicator*)progress
                    withBounds: (NSRect)bounds
                      withClip: (NSRect)rect
                       atCount: (int)count
                      forValue: (double)val
{
  NSRect r;
  if (fillColour == nil)
    {
      [self initProgressIndicatorDrawing];
    }
  // Mirror the indicator into this app's Dock icon: determinate bars report
  // their fraction, indeterminate/spinning bars report -1 (no fill).
  if ([progress style] == NSProgressIndicatorSpinningStyle
      || [progress isIndeterminate])
    {
      [self reportDockProgress: -1.0];
    }
  else
    {
      [self reportDockProgress: val];
    }
  // Draw the Bezel
  if ([progress isBezeled])
    {
      // Calc the inside rect to be drawn
      r = [self drawProgressIndicatorBezel: bounds withClip: rect];
    }
  else
    {
      r = bounds;
    }

  if ([progress style] == NSProgressIndicatorSpinningStyle)
    {
      [self drawProgressIndicatorSpinner: r atCount: count];
    }
   else
     {
       if ([progress isIndeterminate])
         {
	   if (indeterminateMaxCount != 0)
	     {
	       count = count % indeterminateMaxCount;
	       [indeterminateColors[count] set];
	       NSRectFill(r);
	     }
         }
       else
         {
           // Draw determinate
           if ([progress isVertical])
             {
               float height = NSHeight(r) * val;

               if ([progress isFlipped])
                 {
                   // Compensate for the flip
                   r.origin.y += NSHeight(r) - height;
                 }
               r.size.height = height;
             }
           else
             {
               r.size.width = NSWidth(r) * val;
             }
           r = NSIntersectionRect(r, rect);
           if (!NSIsEmptyRect(r))
             {
               [self drawProgressIndicatorBarDeterminate: (NSRect)r withOrientation:[progress isVertical]];

                NSColor* strokeColor = [NSColor colorWithCalibratedRed: 0.624
                                                                green: 0.624
                                                                  blue: 0.624
                                                                alpha: 1];

                NSRect borderRect = NSMakeRect(
                    NSMinX(bounds) + 0.5,
                    NSMinY(bounds) + 0.5,
                    floor(NSWidth(bounds)-1),
                    NSHeight(bounds)-1
                );
                NSBezierPath* emptyRectanglePath = [NSBezierPath bezierPathWithRoundedRect: borderRect
                                                                                  xRadius: 3
                                                                                  yRadius: 3];
                if(val < 1.0)
                  {
                  if([progress isVertical])
                    {
                      [emptyRectanglePath moveToPoint: NSMakePoint(NSMinX(r), NSMinY(r))];
                      [emptyRectanglePath lineToPoint: NSMakePoint(NSMaxX(r), NSMinY(r))];
                    }
                  else
                    {
                      [emptyRectanglePath moveToPoint: NSMakePoint(floor(NSMaxX(r))+0.5, NSMaxY(r))];
                      [emptyRectanglePath lineToPoint: NSMakePoint(floor(NSMaxX(r))+0.5, NSMinY(r))];
                    }
                  }
                [strokeColor setStroke];
                [emptyRectanglePath setLineWidth: 1];
                [emptyRectanglePath stroke];

             }
         }
     }
}

- (NSRect) drawProgressIndicatorBezel: (NSRect)bounds withClip: (NSRect) rect
{
    return [self drawInnerGrayBezel: bounds withClip: rect];
}

// Classic spoke-wheel spinner: twelve identical radial batons on an
// invisible disc.  All batons look the same, so the animation is purely
// the wheel rotating one spoke per frame - which is what gives the era
// look; a fading tail would read as a modern spinner instead.
- (void) drawProgressIndicatorSpinner: (NSRect)r atCount: (int)count
{
  CGFloat diameter = MIN(NSWidth(r), NSHeight(r));
  CGFloat radius, innerRadius, batonWidth;
  NSPoint center;
  NSBezierPath *wheel;
  NSColor *batonColour;
  int i;

  if (diameter < 4.0)
    return;

  center = NSMakePoint(NSMidX(r), NSMidY(r));
  radius = diameter / 2.0 - 1.0;
  /* Batons reach from near the hub to near the rim, like wheel spokes */
  innerRadius = radius * 0.4;
  batonWidth = MAX(1.0, diameter / 12.0);

  batonColour = [NSColor colorWithCalibratedWhite: 0.30 alpha: 1.0];
  [batonColour setStroke];

  wheel = [NSBezierPath bezierPath];
  [wheel setLineWidth: batonWidth];
  [wheel setLineCapStyle: NSRoundLineCapStyle];
  for (i = 0; i < 12; i++)
    {
      /* One spoke step per animation frame, clockwise on screen */
      CGFloat degrees = -((count + i) % 12) * 30.0;
      CGFloat rad = degrees * M_PI / 180.0;
      CGFloat s = sin(rad);
      CGFloat c = cos(rad);

      [wheel moveToPoint: NSMakePoint(center.x + c * innerRadius,
                                      center.y + s * innerRadius)];
      [wheel lineToPoint: NSMakePoint(center.x + c * radius,
                                      center.y + s * radius)];
    }
  [wheel stroke];
}

- (void) drawProgressIndicatorBarDeterminate: (NSRect)bounds withOrientation:(BOOL) isVertical
{

  //// Color Declarations
  NSColor* baseColor = [NSColor colorWithCalibratedRed: 0.376 green: 0.761 blue: 0.957 alpha: 1];
  NSColor* lightColor = [baseColor highlightWithLevel: 0.5];
  NSColor* lightColor2 = [NSColor colorWithCalibratedHue: [baseColor hueComponent] saturation: 0.2 brightness: [baseColor brightnessComponent] alpha: [baseColor alphaComponent]];
  NSColor* saturate = [NSColor colorWithCalibratedHue: [baseColor hueComponent] saturation: 0.8 brightness: [baseColor brightnessComponent] alpha: [baseColor alphaComponent]];

  //// Gradient Declarations
  NSGradient* progressbarGradient = [[NSGradient alloc] initWithColorsAndLocations: 
      lightColor, 0.0, 
      baseColor, 0.45, 
      saturate, 0.55, 
      lightColor2, 1.0, nil];


  //// fullrectange Drawing
  NSBezierPath* fullrectangePath = [NSBezierPath bezierPathWithRoundedRect:bounds  xRadius: 3 yRadius: 3];

  int angle = 90;
  //maybe there is a better method to determine the orientation
  if(isVertical)
    angle = 0;
  [progressbarGradient drawInBezierPath: fullrectangePath angle: angle];


}

@end

@implementation Eau(EauDockProgress)

- (void)reportDockProgress:(double)value
{
  id<EauDockService> proxy = EauDockProgressProxy();
  if (proxy == nil)
    {
      return;
    }
  if (value == lastDockValue)
    {
      /* Value unchanged but still being drawn: keep the bar visible by
       * pushing the hide time out.  A determinate bar that stalls mid-way
       * must not flicker, and a spinning indicator redraws constantly. */
      [self resetDockHideTimer];
      return;
    }
  lastDockValue = value;
  [proxy setProgressValue: value];
  [proxy setProgressVisible: YES];
  [self resetDockHideTimer];
}

- (void)resetDockHideTimer
{
  if (dockHideTimer)
    {
      [dockHideTimer invalidate];
      dockHideTimer = nil;
    }
  /* scheduledTimerWithTimeInterval only serves the default mode; a modal
   * alert or menu tracking (Build's success alert, a Run dialog) would stall
   * the timer, leaving the Dock bar stuck.  Serve those modes too. */
  NSTimer *t = [NSTimer timerWithTimeInterval: EAU_DOCK_HIDE_DELAY
                                       target: self
                                     selector: @selector(hideDockProgress:)
                                     userInfo: nil
                                      repeats: NO];
  NSRunLoop *rl = [NSRunLoop currentRunLoop];
  [rl addTimer: t forMode: NSDefaultRunLoopMode];
  [rl addTimer: t forMode: NSModalPanelRunLoopMode];
  [rl addTimer: t forMode: NSEventTrackingRunLoopMode];
  dockHideTimer = t;
}

- (void)hideDockProgress:(NSTimer *)timer
{
  dockHideTimer = nil;
  lastDockValue = -2.0;
  id<EauDockService> proxy = EauDockProgressProxy();
  if (proxy)
    {
      [proxy setProgressVisible: NO];
    }
}

@end
