# AGENTS.md

Eau: default Aqua-style theme bundle for the Gershwin Desktop, targets GNUstep (Linux/FreeBSD/OpenBSD), not Darwin.

## Build & install
- Use `gmake`, never `make`. Sources are ASCII-only.
- Build: `gmake` (in repo root). Output bundle is `Eau.theme/`.
- Install to the SYSTEM domain only: `GNUSTEP_INSTALLATION_DOMAIN=SYSTEM gmake install`. Never install to LOCAL.
- Files are compiled with `-fobjc-arc -fobjc-arc-exceptions` and link `-lX11`. Fix every build warning.
- There is no `GNUmakefile.in`; edit `GNUmakefile` directly (still check for a `.in` sibling before editing).

## Method swizzling (major pattern)
- Most UI customization is done by swizzling Foundation/GNUstep methods under `+ (void) load` with `dispatch_once`, using `class_addMethod` + `method_exchangeImplementations` (see `NSButton+Eau.m`, `NSWindow+Eau.m`, `NSButtonCell+Eau.m`). A few files instead use `method_setImplementation` with C-function IMPs (e.g. `NSMenu+Eau.m`, `NSMenuView+Eau.m`, `GSDisplayServer+Eau.m`) or direct swizzle helpers.
- When touching a `+Eau` category, always add a new `eauXxx` swizzled selector and call it to reach the original - never fully replace the method body.
- Keep `dispatch`/GCD usage to `dispatch_once` only; do not add new GCD-based async paths (unreliable here).

## Architecture notes
- No tests beyond manual `Test/` tools (`alerttest`, `dialogtest`, and `guiDrawing` GORM sample) that compile against `-lgnustep-gui`. Real verification is by running the theme against system apps (LoginWindow.app etc.), not hand-written "smoke" tests.
- Default behaviors are set by swizzling `init`/`initWithCoder:` of cells (e.g. `NSTextFieldCell` forces `bezeled:NO`). When changing a default, keep the same per-instance pattern.
- Sizing/spacing constants for ASD controls live in `AppearanceMetrics.h` (spacing, orbs etc.) - reuse these rather than hardcoding values.
- Sizes/Comments: always a plain hyphen `-`, never an em dash. Put WHY in comments, not WHAT.

## Git
- Work on the `dev` branch. Never commit/push to `main`/`master`.
- Commit only when the user explicitly asks ("commit"), and only push when the user explicitly says so.