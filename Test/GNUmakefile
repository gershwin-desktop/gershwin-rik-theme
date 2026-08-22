include $(GNUSTEP_MAKEFILES)/common.make

# dialogtest is a bare tool run by hand from obj/.
TOOL_NAME = dialogtest
dialogtest_OBJC_FILES = dialogtest.m
dialogtest_TOOL_LIBS = -lgnustep-gui -lgnustep-base

# alerttest is a real app so the UI-test harness can launch it with
# `launch application "alerttest"`: the runner only starts apps found in the
# standard .app locations.  It installs into the user's Applications folder
# (a supported developer/test location) to keep /System and /Local clean.
APP_NAME = alerttest
alerttest_INSTALL_DIR = $(HOME)/Applications
alerttest_OBJC_FILES = alerttest.m

include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/application.make
