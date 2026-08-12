include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM


TOOL_NAME = alerttest dialogtest

alerttest_OBJC_FILES = alerttest.m
dialogtest_OBJC_FILES = dialogtest.m

# This is the critical line to link against gnustep-gui and gnustep-base
alerttest_TOOL_LIBS = -lgnustep-gui -lgnustep-base
dialogtest_TOOL_LIBS = -lgnustep-gui -lgnustep-base

include $(GNUSTEP_MAKEFILES)/tool.make

