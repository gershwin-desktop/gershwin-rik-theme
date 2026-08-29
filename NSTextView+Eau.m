/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * NSTextView keyboard editing shortcuts for Eau theme
 * Makes Cmd+A/C/V/X/Z work in every text view and dialog field editor.
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/* Handle Cmd+A/C/V/X/Z directly on any text view.
 *
 * WHY: GNUstep dispatches key equivalents by asking the key window, then
 * the main menu.  When there is no Edit menu (Menu.app's search box, a
 * dialog whose Edit items are disabled, a menu-less popup), the shortcut is
 * never matched and Cmd+C/V/X/A fall through to the field editor's
 * interpretKeyEvents:, whose default keybinding table has no entries for
 * them - so the keys are inserted as plain text.  Intercepting keyDown: on
 * the text view handles the standard editing shortcuts regardless of the
 * menu state; a field editor is an NSTextView too, so search fields and
 * dialog inputs are covered as well.
 *
 * Only act when this text view (or its window's field editor) is the first
 * responder, so we never steal Cmd+C from file operations in a viewer that
 * happens to contain an inactive text view.
 */

static void (*s_orig_keyDown)(id, SEL, NSEvent *) = NULL;

static void s_eau_textView_keyDown(id self, SEL _cmd, NSEvent *event)
{
  if ([event type] == NSKeyDown)
    {
      /* A field editor is the NSTextView used to edit a single-line control
       * (NSTextField, NSSearchField, ...).  In such controls Tab must move
       * keyboard focus to the next/previous key view, exactly like a button,
       * not insert a literal tab character into the text.  Multi-line
       * NSTextViews are never field editors, so they keep their normal Tab
       * (insert tab) behaviour.  Advancing the key view also ends editing. */
      NSString *nav = [event charactersIgnoringModifiers];
      if ([nav length] == 1)
        {
          unichar k = [nav characterAtIndex: 0];
          if ((k == NSTabCharacter || k == NSBackTabCharacter) && [self isFieldEditor])
            {
              NSWindow *win = [self window];
              if (win != nil)
                {
                  if (k == NSTabCharacter)
                    [win selectNextKeyView: self];
                  else
                    [win selectPreviousKeyView: self];
                  return;
                }
            }
        }
      if (([event modifierFlags] & NSCommandKeyMask)
          && [[self window] firstResponder] == self)
        {
          NSString *key = [event charactersIgnoringModifiers];
          if ([key length] == 1)
            {
              unichar c = [key characterAtIndex: 0];
              switch (c)
                {
                  case 'a':
                    [self selectAll: self];
                    return;
                  case 'c':
                    [self copy: self];
                    return;
                  case 'v':
                    [self paste: self];
                    return;
                  case 'x':
                    [self cut: self];
                    return;
                  case 'z':
                    if ([event modifierFlags] & NSShiftKeyMask)
                      {
                        [[self undoManager] redo];
                      }
                    else
                      {
                        [[self undoManager] undo];
                      }
                    return;
                  default:
                    break;
                }
            }
        }
    }
  if (s_orig_keyDown)
    s_orig_keyDown(self, _cmd, event);
}

/* The field editor is created on demand and is an NSTextView, so swizzling
   NSTextView -keyDown: covers every editable control in the app. */
__attribute__((constructor))
static void eau_installTextViewKeyDown(void)
{
  Class cls = objc_getClass("NSTextView");
  if (!cls) return;
  Method m = class_getInstanceMethod(cls, @selector(keyDown:));
  if (!m) return;
  s_orig_keyDown = (void (*)(id, SEL, NSEvent *))method_getImplementation(m);
  method_setImplementation(m, (IMP)s_eau_textView_keyDown);
}
