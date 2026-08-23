/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NSApplication beep override for Eau theme
 * Plays the configured alert sound instead of system beep
 */

#import <AppKit/AppKit.h>
#import "Eau.h"
#import "EauSound.h"

@implementation NSApplication (EauBeep)

+ (void)load {
    NSDebugLog(@"NSApplication(EauBeep) +load");
}


// Override the beep method to play configured alert sound
- (void)beep
{
    static BOOL isPlaying = NO;

    // Prevent recursive calls
    if (isPlaying) {
        NSDebugLog(@"Re-entrant beep ignored");
        return;
    }

    isPlaying = YES;
    NSDebugLog(@"-beep called");

    @autoreleasepool {
        // Load preferences for alert sound
        NSString *prefsPath = [NSHomeDirectory() stringByAppendingPathComponent:
                              @".config/gershwin/sound-defaults.plist"];
        NSDebugLog(@"prefsPath: %@", prefsPath);

        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];

        if (prefs) {
            NSString *alertSoundName = [prefs objectForKey:@"alertSound"];

            if (alertSoundName) {
                NSDebugLog(@"alertSound: %@", alertSoundName);
                /* EauSound plays at the user's configured alert volume and
                 * reports failure so we can still fall back to the bell */
                if (EauPlaySystemSound(alertSoundName)) {
                    isPlaying = NO;
                    return;
                }
                NSDebugLog(@"No sound file found for %@ in sound paths", alertSoundName);
            } else {
                NSDebugLog(@"alertSound key missing in prefs");
            }
        } else {
            NSDebugLog(@"No prefs found at %@", prefsPath);
        }

        // Fall back to system beep (PC speaker or /dev/console)
        NSDebugLog(@"Falling back to system bell");
        printf("\a");
        fflush(stdout);
    }

    isPlaying = NO;
}

@end
