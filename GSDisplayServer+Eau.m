/* GSDisplayServer+Eau.m - Fix popup menu window type
   Copyright (C) 2026 Free Software Foundation, Inc.

   This file is part of GNUstep.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

/*
 * libs-back sets _NET_WM_WINDOW_TYPE_DIALOG instead of
 * _NET_WM_WINDOW_TYPE_POPUP_MENU for NSPopUpMenuWindowLevel windows
 * (XGServerWindow.m:3479). This causes the window manager to decorate
 * popup menus with frames/titlebars instead of mapping them undecorated.
 *
 * This category swizzles -setwindowlevel:: on XGServer to fix the
 * _NET_WM_WINDOW_TYPE property after the original method runs.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#include <stdlib.h>

static BOOL EAUIsDialogLikeWindow(NSWindow *window, int level)
{
  if (window == nil)
    {
      return NO;
    }

  if ([window isKindOfClass: [NSPanel class]])
    {
      return YES;
    }

  if (level >= NSModalPanelWindowLevel)
    {
      return YES;
    }

  if (([window styleMask] & NSUtilityWindowMask) != 0)
    {
      return YES;
    }

  return NO;
}

static BOOL EAUIsMenuPanelWindow(NSWindow *window)
{
  Class menuPanelClass = NSClassFromString(@"NSMenuPanel");
  return (menuPanelClass != Nil && [window isKindOfClass: menuPanelClass]);
}

static BOOL EAUIsModalDialogWindow(NSWindow *window, int level)
{
  if (window == nil)
    {
      return NO;
    }

  if (level >= NSModalPanelWindowLevel)
    {
      return YES;
    }

  return NO;
}

static void EAUEnsureWindowStates(Display *dpy,
                                  Window xwin,
                                  Atom *requiredStates,
                                  unsigned int requiredCount)
{
  Atom wmState;
  Atom actualType = None;
  int actualFormat = 0;
  unsigned long nitems = 0;
  unsigned long bytesAfter = 0;
  unsigned char *existing = NULL;
  Atom *newStates;
  BOOL changed = NO;
  unsigned int missingCount = 0;
  unsigned long i;
  unsigned int r;
  unsigned long outIndex;

  wmState = XInternAtom(dpy, "_NET_WM_STATE", False);
  if (wmState == None || requiredStates == NULL || requiredCount == 0)
    {
      return;
    }

  if (XGetWindowProperty(dpy,
                         xwin,
                         wmState,
                         0,
                         1024,
                         False,
                         XA_ATOM,
                         &actualType,
                         &actualFormat,
                         &nitems,
                         &bytesAfter,
                         &existing) == Success
      && actualType == XA_ATOM
      && actualFormat == 32)
    {
      Atom *states = (Atom *)existing;
      for (r = 0; r < requiredCount; r++)
        {
          BOOL found = NO;
          for (i = 0; i < nitems; i++)
            {
              if (states[i] == requiredStates[r])
                {
                  found = YES;
                  break;
                }
            }
          if (found == NO)
            {
              missingCount++;
            }
        }

      if (missingCount > 0)
        {
          newStates = (Atom *)calloc((size_t)nitems + missingCount, sizeof(Atom));
          if (newStates != NULL)
            {
              for (i = 0; i < nitems; i++)
                {
                  newStates[i] = states[i];
                }

              outIndex = nitems;
              for (r = 0; r < requiredCount; r++)
                {
                  BOOL found = NO;
                  for (i = 0; i < nitems; i++)
                    {
                      if (states[i] == requiredStates[r])
                        {
                          found = YES;
                          break;
                        }
                    }
                  if (found == NO)
                    {
                      newStates[outIndex] = requiredStates[r];
                      outIndex++;
                    }
                }

              XChangeProperty(dpy,
                              xwin,
                              wmState,
                              XA_ATOM,
                              32,
                              PropModeReplace,
                              (unsigned char *)newStates,
                              (int)outIndex);
              free(newStates);
              changed = YES;
            }
        }
    }

  if (existing != NULL)
    {
      XFree(existing);
    }

  if (changed == NO && nitems == 0)
    {
      Atom *initialStates;
      initialStates = (Atom *)calloc(requiredCount, sizeof(Atom));
      if (initialStates == NULL)
        {
          return;
        }
      for (r = 0; r < requiredCount; r++)
        {
          initialStates[r] = requiredStates[r];
        }
      XChangeProperty(dpy,
                      xwin,
                      wmState,
                      XA_ATOM,
                      32,
                      PropModeReplace,
                      (unsigned char *)initialStates,
                      (int)requiredCount);
      free(initialStates);
    }
}

@implementation GSDisplayServer (EauPopupMenuFix)

+ (void) load
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = NSClassFromString(@"XGServer");
    if (!cls)
      return;

    SEL origSel = @selector(setwindowlevel::);
    SEL swizSel = @selector(eau_setwindowlevel::);

    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method swizMethod = class_getInstanceMethod(self, swizSel);
    if (!origMethod || !swizMethod)
      return;

    /* Add our method to XGServer, then exchange implementations */
    class_addMethod(cls, swizSel,
                    method_getImplementation(swizMethod),
                    method_getTypeEncoding(swizMethod));
    Method addedMethod = class_getInstanceMethod(cls, swizSel);
    method_exchangeImplementations(origMethod, addedMethod);
  });
}

- (void) eau_setwindowlevel: (int)level : (int)win
{
  NSWindow *nswin;

  /* Call original (swizzled) */
  [self eau_setwindowlevel: level : win];

  nswin = GSWindowWithNumber(win);
  if (nswin == nil)
    {
      return;
    }

  /* Fix popup menu window type: libs-back sets DIALOG instead of POPUP_MENU */
  if (level == NSPopUpMenuWindowLevel)
    {
      /* Only fix actual menu panel windows. NSPopUpMenuWindowLevel is shared
         by tooltips, autocomplete, drag views, popovers, and other windows
         that must keep the default DIALOG type. */
      Class menuPanelClass = NSClassFromString(@"NSMenuPanel");
      if (menuPanelClass != Nil && [nswin isKindOfClass: menuPanelClass])
        {
          Display *dpy = (Display *)[self serverDevice];
          Window xwin = (Window)(uintptr_t)[self windowDevice: win];
          if (dpy != NULL && xwin != 0)
            {
              Atom wmType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
              Atom popupType = XInternAtom(dpy,
                                           "_NET_WM_WINDOW_TYPE_POPUP_MENU",
                                           False);
              XChangeProperty(dpy,
                              xwin,
                              wmType,
                              XA_ATOM,
                              32,
                              PropModeReplace,
                              (unsigned char *)&popupType,
                              1);
            }
        }
    }

  if (EAUIsDialogLikeWindow(nswin, level) && EAUIsMenuPanelWindow(nswin) == NO)
    {
      Display *dpy = (Display *)[self serverDevice];
      Window xwin = (Window)(uintptr_t)[self windowDevice: win];
      if (dpy != NULL && xwin != 0)
        {
          Atom wmType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
          Atom dialogType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DIALOG", False);
          if (wmType != None && dialogType != None)
            {
              XChangeProperty(dpy, xwin, wmType, XA_ATOM, 32,
                              PropModeReplace,
                              (unsigned char *)&dialogType, 1);
            }

          Atom skipTaskbar;
          Atom skipPager;
          Atom modal;
          Atom states[3];
          unsigned int stateCount = 0;

          skipTaskbar = XInternAtom(dpy, "_NET_WM_STATE_SKIP_TASKBAR", False);
          skipPager = XInternAtom(dpy, "_NET_WM_STATE_SKIP_PAGER", False);
          modal = XInternAtom(dpy, "_NET_WM_STATE_MODAL", False);

          if (skipTaskbar != None)
            {
              states[stateCount] = skipTaskbar;
              stateCount++;
            }
          if (skipPager != None)
            {
              states[stateCount] = skipPager;
              stateCount++;
            }
          if (EAUIsModalDialogWindow(nswin, level) && modal != None)
            {
              states[stateCount] = modal;
              stateCount++;
            }

          EAUEnsureWindowStates(dpy, xwin, states, stateCount);
        }
    }
}

@end
