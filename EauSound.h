/*
 * EauSound.h
 * Eau Theme - system sound playback
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

/* Plays a system sound by name (e.g. @"Glass") at the alert volume the user
 * configured in the Sound prefPane (.config/gershwin/sound-defaults.plist).
 * Searches the usual system and per-user sound directories. Returns NO when
 * no matching sound file exists, so callers can fall back. */
BOOL EauPlaySystemSound(NSString *soundName);
