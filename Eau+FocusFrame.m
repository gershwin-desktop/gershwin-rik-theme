#import "Eau.h"
#import "Eau+Drawings.h"
#import "Eau+Stepper.h"
#import <objc/runtime.h>

/* A transparent view pinned on top of the window's content view.  Drawing the
 * focus ring here (instead of inside the focused control) means it is never
 * clipped to the control's cell-frame bounds, it sits on top of neighbouring
 * widgets, and it can extend right up to - and just outside - the widget's
 * edge with no gap. */
@interface EauFocusOverlay : NSView
@property (nonatomic, retain) NSBezierPath *ringPath;
@property (nonatomic, assign) NSView *focusedView;
@end

@implementation EauFocusOverlay
- (BOOL) isOpaque
{
  return NO;
}
- (void) drawRect: (NSRect) rect
{
  if (_ringPath == nil)
    return;
  /* The ring is only valid while its control is still the first responder;
   * drop it the moment focus moves elsewhere. */
  if ([[self window] firstResponder] != _focusedView)
    {
      _ringPath = nil;
      return;
    }
  NSColor *src = [NSColor selectedControlColor];
  NSColor *rgb = [src colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  CGFloat r = (rgb != nil) ? [rgb redComponent] : 0.28;
  CGFloat g = (rgb != nil) ? [rgb greenComponent] : 0.58;
  CGFloat b = (rgb != nil) ? [rgb blueComponent] : 0.90;
  [[NSColor colorWithCalibratedRed: r green: g blue: b alpha: 1.0] setStroke];
  [_ringPath setLineWidth: 2];
  [_ringPath stroke];
}
@end

static const void *EauFocusOverlayKey = &EauFocusOverlayKey;

static EauFocusOverlay *eauOverlayForWindow(NSWindow *win)
{
  EauFocusOverlay *ov = objc_getAssociatedObject(win, EauFocusOverlayKey);
  if (ov == nil)
    {
      ov = [[EauFocusOverlay alloc] initWithFrame: NSZeroRect];
      [ov setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      objc_setAssociatedObject(win, EauFocusOverlayKey, ov,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  return ov;
}

@implementation Eau (EauFocusFrame)

- (void) drawFocusFrame: (NSRect) frame view: (NSView*) view
{
  NSBezierPath * path;
  /* The ring is traced just OUTSIDE the widget (m = 2), so it is clearly on
   * top of neighbouring widgets and flush against the edge with no gap. */
  CGFloat m = 2.0;
  NSRect base = [view bounds];

  if([view class] == [NSButton class])
    {
        NSButton *focusButton = (NSButton*)view;
        int bezel_style = [focusButton bezelStyle];
        NSRect fr = NSInsetRect(base, -m, -m);
        switch (bezel_style)
          {
            case NSTexturedSquareBezelStyle:
            case NSSmallSquareBezelStyle:
            case NSRegularSquareBezelStyle:
            case NSShadowlessSquareBezelStyle:
            case NSThickSquareBezelStyle:
            case NSThickerSquareBezelStyle:
              path = [NSBezierPath bezierPathWithRect: fr];
              break;
            default:
              {
                CGFloat r = [self _eau_radiusForFrame: base];
                CGFloat leftR = r, rightR = r;
                [self _eau_adjacencyRadiiForView: view
                                          baseRadius: r
                                           leftRadius: &leftR
                                          rightRadius: &rightR];
                path = [self _eau_roundedPath: fr
                                       topLeft: leftR
                                      topRight: rightR
                                    bottomLeft: leftR
                                   bottomRight: rightR];
              }
              break;
          }
    }
  else if([view class] == [NSStepper class])
    {
      path = [self stepperBezierPathWithFrame: NSInsetRect(base, -m, -m)];
    }
  else if([view class] == [NSPopUpButton class])
    {
      path = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(base, -m, -m)
                                            xRadius: 3
                                            yRadius: 3];
    }
  else if([view class] == [NSMatrix class])
    {
      NSCell* selectedCell = [(NSMatrix*) view selectedCell];
      NSUInteger row = [(NSMatrix*)view selectedRow];
      NSUInteger col = [(NSMatrix*)view selectedColumn];
      NSRect r = [(NSMatrix*) view cellFrameAtRow:row column: col];
      if([selectedCell class] == [NSButtonCell class])
        {
          path = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(r, -m, -m)
                                                xRadius: 3
                                                yRadius: 3];
        }else{
          return;
        }
    }
  else
    {
      path = [NSBezierPath bezierPathWithRect: NSInsetRect(base, -m, -m)];
    }

  /* Hand the ring to the per-window overlay, expressed in the content view's
   * coordinate space so it is drawn last (on top of everything), never clipped
   * by the control's cell-frame bounds, and extends just outside the widget. */
  NSWindow *win = [view window];
  NSView *cv = [win contentView];
  if (cv == nil)
    return;
  NSRect vr = [view convertRect: [view bounds] toView: cv];
  NSBezierPath *ring = [path copy];
  NSAffineTransform *t = [NSAffineTransform transform];
  [t translateXBy: vr.origin.x yBy: vr.origin.y];
  [ring transformUsingAffineTransform: t];

  EauFocusOverlay *ov = eauOverlayForWindow(win);
  [ov setRingPath: ring];
  [ov setFocusedView: view];
  [ov setFrame: [cv bounds]];
  /* Attach synchronously, guarded to once, to the live content view so the
   * overlay is actually in the window's view tree (a deferred add left it
   * detached, with [self window] nil, so it never composited). */
  if ([ov superview] != cv)
    {
      [cv addSubview: ov];
    }
  [ov setNeedsDisplay: YES];
}

- (NSSize) sizeForBorderType: (NSBorderType) aType
{
      switch (aType)
        {
          case NSLineBorder:
            return NSMakeSize(4, 4);
          case NSGrooveBorder:
          case NSBezelBorder:
            return NSMakeSize(1, 1);
          case NSNoBorder:
          default:
            return NSZeroSize;
        }
}

@end
