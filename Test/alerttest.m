/* alerttest - shows a short error alert and then a long error alert.
 *
 * Used by Tests/alert_long_text.uitest to prove that the Eau theme shows
 * long informative text in the scrollable variant of the alert panel while
 * short texts stay in the plain (unscrolled) layout.  The long text is a
 * realistic multi-line stderr dump with a distinctive first and last line
 * so the UI test can assert nothing was omitted.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <AppKit/AppKit.h>

static NSString *longStderrText(void)
{
  NSMutableString *text = [NSMutableString string];
  for (int i = 1; i <= 200; i++)
    {
      [text appendFormat:
        @"stderr line %03d: simulated crash output for the alert scrolling test\n", i];
    }
  return text;
}

static NSInteger runErrorAlert(NSString *headline, NSString *detail)
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText: headline];
  [alert setInformativeText: detail];
  [alert addButtonWithTitle: @"OK"];
  NSInteger result = [alert runModal];
  [alert release];
  return result;
}

@interface AppDelegate : NSObject
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSLog(@"ALERTTEST: showing SHORT error alert");
    NSInteger r1 = runErrorAlert(@"Short Error",
                                 @"This test tests the short alert layout.");
    NSLog(@"ALERTTEST: short alert returned %ld", (long)r1);

    NSLog(@"ALERTTEST: showing LONG error alert");
    NSInteger r2 = runErrorAlert(@"Long Error", longStderrText());
    NSLog(@"ALERTTEST: long alert returned %ld", (long)r2);

    [NSApp terminate: nil];
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        AppDelegate *delegate = [[AppDelegate alloc] init];
        [NSApp setDelegate: delegate];

        [NSApp run];
        [delegate release];
    }
    return 0;
}
