/* t_AlertPanelScrolling.m - ObjectTesting coverage for the Eau theme's
 * alert-panel long-text contract.
 *
 * The rules proven here (behavioral spec, gershwin-eau-theme):
 *
 *  1. A SHORT informative text renders in the plain variant: no internal
 *     scroll view is attached, the message field sits directly in the
 *     content view.
 *  2. A LONG informative text renders in the scrollable variant: the
 *     panel's internal scroll view is attached and the message field is
 *     its document view.
 *  3. Nothing is ever omitted: the document view carries the complete
 *     text, including its first and last line.
 *  4. The scrolled alert stays within the theme's window height cap
 *     (METRICS_SIZE_SCALE of the screen), with a live vertical scroller.
 *
 * The panel is driven through the exact calls eau_setupPanel makes
 * (setTitleBar:icon:title:message: then setButtons:) so the test covers the
 * real layout wiring without depending on swizzle state: when this test
 * binary runs on a desktop, the installed Eau.theme bundle ALSO swaps
 * NSAlert _setupPanel in the process, which un-does the swap done by our
 * statically linked copy of NSAlert+Eau.m.  Driving the panel directly is
 * order-independent; the end-to-end path is covered by
 * Tests/alert_long_text.uitest.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Testing.h"
#import "NSAlert+Eau.h"
#import "AppearanceMetrics.h"

/* Fetch a named object ivar from the panel (scroll / messageField / ...). */
static id panelIvar(EauAlertPanel *panel, const char *name)
{
  Ivar ivar = class_getInstanceVariable([panel class], name);
  if (ivar == NULL)
    {
      return nil;
    }
  return object_getIvar(panel, ivar);
}

/* Build a themed panel the way eau_setupPanel does: title/message first,
 * then buttons (which runs sizePanelToFit). */
static EauAlertPanel *builtPanel(NSString *headline, NSString *body)
{
  EauAlertPanel *panel = [[EauAlertPanel alloc] init];
  [panel setTitleBar: @"" icon: nil title: headline message: body];

  NSButton *ok = [[NSButton alloc] init];
  [ok setTitle: @"OK"];
  [panel setButtons: [NSArray arrayWithObject: ok]];
  [ok release];
  return [panel autorelease];
}

static NSString *longStderrText(void)
{
  NSMutableString *text = [NSMutableString string];
  for (int i = 1; i <= 200; i++)
    {
      [text appendFormat:
        @"stderr line %03d: simulated crash output for the scrolling test\n", i];
    }
  return text;
}

int main(void)
{
  @autoreleasepool {
    [NSApplication sharedApplication];

    /* --- 1. Short alert: plain variant, no internal scrolling --- */
    {
      EauAlertPanel *panel = builtPanel(@"Short Error",
                                        @"The disk 'System' is full.");

      NSScrollView *scroll = panelIvar(panel, "scroll");
      NSTextField *messageField = panelIvar(panel, "messageField");
      NSTextField *titleField = panelIvar(panel, "titleField");

      PASS(scroll != nil && [scroll superview] == nil,
           "short alert keeps the internal scroll view detached");
      PASS(messageField != nil && [messageField superview] != nil,
           "short alert shows the message field directly in the content view");
      PASS(titleField != nil
           && [[titleField stringValue] isEqualToString: @"Short Error"],
           "short alert headline is the message text");
      PASS([[messageField stringValue] isEqualToString: @"The disk 'System' is full."],
           "short alert body is the informative text");
    }

    /* --- 2./3./4. Long alert: scrolled variant, nothing omitted --- */
    {
      NSString *detail = longStderrText();
      EauAlertPanel *panel = builtPanel(@"Long Error", detail);

      NSScrollView *scroll = panelIvar(panel, "scroll");
      NSTextField *messageField = panelIvar(panel, "messageField");

      BOOL attached = (scroll != nil && [scroll superview] != nil);
      PASS(attached,
           "long alert attaches the internal scroll view (scrolled variant)");

      BOOL docIsMessage
        = attached && [[scroll documentView] isEqual: messageField];
      PASS(docIsMessage,
           "scrolled variant uses the message field as its document view");

      PASS(docIsMessage
           && [[(NSTextField *)[scroll documentView] stringValue]
               isEqualToString: detail],
           "document view carries the COMPLETE text, nothing omitted");
      PASS(docIsMessage
           && [[messageField stringValue] containsString: @"stderr line 001:"]
           && [[messageField stringValue] containsString: @"stderr line 200:"],
           "first and last stderr lines are present");

      /* Same cap semantics as sizePanelToFit: the window CONTENT stays
         within METRICS_SIZE_SCALE of the screen content height. */
      NSRect screenContent
        = [NSWindow contentRectForFrameRect: [[NSScreen mainScreen] frame]
                                  styleMask: [panel styleMask]];
      CGFloat capHeight = METRICS_SIZE_SCALE * screenContent.size.height;
      CGFloat winContentHeight = [[panel contentView] bounds].size.height;
      PASS(winContentHeight <= capHeight + 0.5,
           "long alert window (%.0f px) stays within the %.0f px height cap",
           (double)winContentHeight, (double)capHeight);

      if (attached)
        {
          NSScroller *vScroller = [scroll verticalScroller];
          PASS(vScroller != nil && [vScroller superview] != nil,
               "vertical scroller exists in the scrolled variant");
          CGFloat knob = [vScroller knobProportion];
          PASS(knob > 0.0 && knob < 1.0,
               "scroller knob proportion (%.2f) shows more content below",
               (double)knob);
        }
    }

    return 0;
  }
}
