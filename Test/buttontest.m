/* buttontest - exercises the Eau button-bar adjacency rule.
 *
 * Builds a window with several groups of NSButtons so the squared-corner
 * (not-rounded) behaviour on touching edges can be inspected:
 *   - Group A: a horizontal row of exactly-adjacent buttons (pill bar:
 *     outer corners rounded, inner corners squared).
 *   - Group B: a horizontal row of overlapping buttons (edges overlap by a
 *     few px - the current rule only squares exact adjacency, so these stay
 *     rounded; this group documents that limitation).
 *   - Group C: a vertical stack of adjacent buttons (the rule only squares
 *     left/right corners, so a vertical bar keeps all four corners rounded).
 *   - Group D: a couple of standalone buttons for reference.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <AppKit/AppKit.h>

static NSButton *makeButton(NSString *title, NSRect frame)
{
  NSButton *b = [[NSButton alloc] initWithFrame: frame];
  [b setBezelStyle: NSRoundedBezelStyle];
  [b setTitle: title];
  [b setButtonType: NSMomentaryPushInButton];
  [b setBordered: YES];
  [b sizeToFit];
  /* Keep the requested height; sizeToFit only touches width. */
  [b setFrame: frame];
  return b;
}

@interface AppDelegate : NSObject
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSRect wf = NSMakeRect(0, 0, 460, 380);
  NSWindow *win = [[NSWindow alloc]
                    initWithContentRect: wf
                              styleMask: NSTitledWindowMask
                                         | NSClosableWindowMask
                                         | NSMiniaturizableWindowMask
                              backing: NSBackingStoreBuffered
                                defer: NO];
  [win setTitle: @"Eau button-bar adjacency"];
  NSView *cv = [win contentView];

  CGFloat h = 24.0;
  CGFloat w = 80.0;

  /* Group A: exactly-adjacent horizontal row (y=320).  x steps of 80 so the
   * right edge of each button meets the left edge of the next exactly. */
  CGFloat ax = 20.0;
  CGFloat ay = 320.0;
  NSArray *atitles = @[@"One", @"Two", @"Three", @"Four", @"Five"];
  NSButton *firstA = nil;
  for (NSString *t in atitles)
    {
      NSButton *b = makeButton(t, NSMakeRect(ax, ay, w, h));
      if (firstA == nil)
        firstA = b;
      [cv addSubview: b];
      ax += w;
    }

  /* Group B: overlapping horizontal row (y=270).  x steps of 76 so each button
   * overlaps its neighbour by 4px - demonstrates that overlap is NOT squared. */
  CGFloat bx = 20.0;
  CGFloat by = 270.0;
  NSArray *btitles = @[@"A", @"B", @"C", @"D"];
  for (NSString *t in btitles)
    {
      [cv addSubview: makeButton(t, NSMakeRect(bx, by, w, h))];
      bx += (w - 4.0);
    }

  /* Group C: vertical stack (x=20, y stepping by h).  Right edges aligned,
   * touching vertically - the rule only squares left/right, so these stay
   * fully rounded. */
  CGFloat cy = 210.0;
  NSArray *ctitles = @[@"Up", @"Mid", @"Low"];
  for (NSString *t in ctitles)
    {
      [cv addSubview: makeButton(t, NSMakeRect(20.0, cy, w, h))];
      cy -= h;
    }

  /* Group D: standalone reference buttons. */
  [cv addSubview: makeButton(@"Solo", NSMakeRect(200.0, 210.0, w, h))];
  [cv addSubview: makeButton(@"Alone", NSMakeRect(200.0, 176.0, w, h))];

  /* Group E: 24px-high adjacent pills on their own row (so the seams are not
   * painted over by another group).  Kept separate from Group A for clarity. */
  CGFloat e24 = 24.0;
  CGFloat ex = 20.0;
  CGFloat ey = 345.0;
  for (NSString *t in @[@"24a", @"24b", @"24c"])
    {
      [cv addSubview: makeButton(t, NSMakeRect(ex, ey, w, e24))];
      ex += w;
    }

  /* Group F: taller (32px) adjacent buttons - exercises the radius=4 squaring
   * path rather than the pill radius. */
  CGFloat f32 = 32.0;
  CGFloat fx = 20.0;
  CGFloat fy = 120.0;
  for (NSString *t in @[@"X", @"Y", @"Z", @"W"])
    {
      [cv addSubview: makeButton(t, NSMakeRect(fx, fy, w, f32))];
      fx += w;
    }

  /* Spinners: a large wheel (12 spokes) and a small one (24px, 6 spokes) so
   * both spoke counts are visible side by side. */
  NSProgressIndicator *spinBig = [[NSProgressIndicator alloc]
    initWithFrame: NSMakeRect(20.0, 20.0, 40.0, 40.0)];
  [spinBig setStyle: NSProgressIndicatorSpinningStyle];
  [spinBig setIndeterminate: YES];
  [spinBig setDisplayedWhenStopped: YES];
  [spinBig startAnimation: nil];
  [cv addSubview: spinBig];
  NSProgressIndicator *spinSmall = [[NSProgressIndicator alloc]
    initWithFrame: NSMakeRect(70.0, 30.0, 20.0, 20.0)];
  [spinSmall setStyle: NSProgressIndicatorSpinningStyle];
  [spinSmall setIndeterminate: YES];
  [spinSmall setDisplayedWhenStopped: YES];
  [spinSmall startAnimation: nil];
  [cv addSubview: spinSmall];

  [win makeKeyAndOrderFront: nil];
  [win makeFirstResponder: firstA];
  [win center];
  NSRect wfr = [win frame];
  NSString *fstr = [NSString stringWithFormat:@"%d %d %d %d\n", (int)NSMinX(wfr), (int)NSMaxY(wfr), (int)NSWidth(wfr), (int)NSHeight(wfr)];
  [fstr writeToFile:@"/tmp/btg.frame" atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}
@end

int main(int argc, char **argv)
{
  @autoreleasepool {
    [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [NSApp setDelegate: delegate];
    [NSApp run];
  }
  return 0;
}
