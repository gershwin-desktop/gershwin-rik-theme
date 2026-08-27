include $(GNUSTEP_MAKEFILES)/common.make

# Never let anything land in the LOCAL domain
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

# alerttest is a real app so the UI-test harness can launch it with
# `launch application "alerttest"`: the runner only starts apps found in the
# standard .app locations.  CoreServices/Applications is where Gershwin keeps
# system-level utility apps, so the harness finds it like any other tool.
APP_NAME = alerttest buttontest
alerttest_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/CoreServices/Applications
alerttest_OBJC_FILES = alerttest.m
buttontest_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/CoreServices/Applications
buttontest_OBJC_FILES = buttontest.m

# dialogtest is a bare manual-only tool, run by hand from obj/ and never
# installed.  It is only built on request because gnustep-make chains
# "install -> all" just for the top-level invocation: a plain "install" here
# (as run by the theme's postamble) would try to install tools that were
# never built on a clean checkout.
ifeq ($(DIALOGTEST),)
TOOL_NAME =
else
TOOL_NAME = dialogtest
dialogtest_OBJC_FILES = dialogtest.m
dialogtest_TOOL_LIBS = -lgnustep-gui -lgnustep-base
endif

include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/application.make
