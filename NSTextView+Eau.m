/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * NSTextView keyboard editing shortcuts for Eau theme
 * Makes Cmd+A/C/V/X/Z work in every text view and dialog field editor.
 */

#import <AppKit/AppKit.h>

@implementation NSTextView (EauKeyEquivalents)

/* Handle Cmd+A/C/V/X/Z directly on any text view.
 *
 * WHY: GNUstep dispatches key equivalents by asking the key window, then
 * the main menu.  During modal dialogs the application's Edit menu items
 * are usually disabled (their validation only enables them when a file
 * viewer/desktop is the key window), so the key-equivalent dispatch
 * swallows these shortcuts without acting.  Handling them on the text view
 * keeps standard text editing working inside dialogs - and everywhere
 * else, since any field editor is an NSTextView too.
 *
 * Only act when this text view (or its window's field editor) is the first
 * responder, so we never steal Cmd+C from file operations in a viewer that
 * happens to contain an inactive text view.
 */
- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSKeyDown
      && ([theEvent modifierFlags] & NSCommandKeyMask)
      && [[self window] firstResponder] == self)
    {
      NSString *key = [theEvent charactersIgnoringModifiers];
      if ([key length] == 1)
        {
          unichar c = [key characterAtIndex: 0];
          switch (c)
            {
              case 'a':
                [self selectAll: self];
                return YES;
              case 'c':
                [self copy: self];
                return YES;
              case 'v':
                [self paste: self];
                return YES;
              case 'x':
                [self cut: self];
                return YES;
              case 'z':
                if ([theEvent modifierFlags] & NSShiftKeyMask)
                  {
                    [[self undoManager] redo];
                  }
                else
                  {
                    [[self undoManager] undo];
                  }
                return YES;
              default:
                break;
            }
        }
    }
  return [super performKeyEquivalent: theEvent];
}

@end
