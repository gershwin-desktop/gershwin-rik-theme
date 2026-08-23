include $(GNUSTEP_MAKEFILES)/common.make

# dialogtest is a bare tool run by hand from obj/.
TOOL_NAME = dialogtest
dialogtest_OBJC_FILES = dialogtest.m
dialogtest_TOOL_LIBS = -lgnustep-gui -lgnustep-base

# alerttest is a real app so the UI-test harness can launch it with
# `launch application "alerttest"`: the runner only starts apps found in the
# standard .app locations.  CoreServices/Applications is where Gershwin keeps
# system-level utility apps, so the harness finds it like any other tool.
APP_NAME = alerttest
alerttest_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/CoreServices/Applications
alerttest_OBJC_FILES = alerttest.m

include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/application.make
