# AGENTS.md

Eau: default Aqua-style theme bundle for the Gershwin Desktop. It is a GNUstep theme (principal class `Eau`, an `GSTheme` subclass), not a Darwin/AppKit app. Targets GNUstep on Linux/FreeBSD/OpenBSD.

## Build & install
- Use `gmake`, never `make`.
- Build: `gmake` (repo root) -> `Eau.theme/` bundle plus `obj/` artifacts.
- `GNUmakefile` already sets `GNUSTEP_INSTALLATION_DOMAIN = SYSTEM`. Always install to SYSTEM only, never LOCAL. Verify after install that nothing landed in `/Local`.
- Compiled with `-fobjc-arc -fobjc-arc-exceptions`, links `-lX11` (see `GNUmakefile`). Fix every build warning.
- No `GNUmakefile.in`; edit `GNUmakefile` directly (still check for a `.in` sibling first).
- Local GNUstep lives at `/System` (source `/System/Library/Makefiles/GNUstep.sh`); the Gershwin dev stack is at `/Developer`. CI (`.github/workflows/build.yml`) builds against gershwin-developer's `make corelibs` + `make eau-theme` on FreeBSD/OpenBSD/Arch/Debian - not standalone.

## Customization: two mechanisms
- Most UI work is method swizzling in `+load` of `+Eau` categories. Two variants:
  - `class_addMethod` + `method_exchangeImplementations` with a new `eau_`/`swz` selector (e.g. `NSButton+Eau.m`, `NSButtonCell+Eau.m`, `NSWindow+Eau.m`, `GSDisplayServer+Eau.m`, `NSAlert+Eau.m`).
  - `method_setImplementation` with C-function IMPs (`NSMenu+Eau.m`, `NSMenuView+Eau.m`, `NSTextView+Eau.m`, `GSStandardDecorationView+Eau.m`).
- When touching a swizzle, always add a new swizzled selector and chain to the original - never fully replace a method body.
- GCD is limited to `dispatch_once` in `+load` (only `NSButton+Eau.m`, `GSDisplayServer+Eau.m`, `Eau+TitleBarButtons.m` use it; most files swizzle directly). Do not add GCD-based async paths.
- The theme engine also has hooks: some methods are overridden directly on `Eau` (e.g. `keyForKeyEquivalent:`) or via `_overrideNSPopUpButtonMethod_mouseDown:` style selectors (`NSPopUpButton+Eau.m`).

## Architecture notes
- Menu bar is served by a separate Menu.app over Distributed Objects: Eau registers a menu client (`NSConnection`, name `MenuClient.<pid>`) and connects to `org.gnustep.Gershwin.MenuServer`. When Menu.app is available the in-app menu bar is hidden (`modifyRect:forMenu:isHorizontal:` returns `NSZeroRect`). Menu code must assume this split; `EauMenuRelaunchManager.m` / `EauMenuScrollManager.m` support it.
- Default cell behaviors are set by swizzling `init`/`initWithCoder:` (e.g. `NSTextFieldCell` forces `bezeled:NO`). When changing a default, keep the same per-instance pattern.
- Sizing/spacing constants for ASD controls live in `AppearanceMetrics.h` (spacing, orbs, margins, etc.) - reuse these rather than hardcoding.

## Conventions
- Sources are not ASCII-only: Unicode menu-key symbols (`⌃⌥⌘⇧`) in `Eau.m` are intentional. Use a plain hyphen `-`, never an em dash, in new code and comments. Put WHY in comments, not WHAT.
- Format per `.clang-format` (2-space indent, Stroustrup braces, 100 columns).

## Verification
- No test framework. Only manual tools under `Test/` (`alerttest`, `dialogtest`, `guiDrawing` GORM sample) linking `-lgnustep-gui`. Real verification is running the installed theme against system apps (e.g. `/System/Applications/LoginWindow.app`), not hand-written smoke tests.
- Before finishing: clean build with no warnings, then review `git diff`.

## Git
- Work on the `dev` branch. Never commit/push to `main`/`master`.
- Commit only when the user explicitly asks ("commit"); push only when explicitly asked.