include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

PACKAGE_NAME = Eau
BUNDLE_NAME = Eau
BUNDLE_EXTENSION = .theme
VERSION = 1

Eau_INSTALL_DIR=$(GNUSTEP_LIBRARY)/Themes
Eau_PRINCIPAL_CLASS = Eau

Eau_OBJC_FILES = \
		Eau.m\
		EauMenuRelaunchManager.m\
		EauMenuScrollManager.m\
		Eau+Drawings.m\
		Eau+Button.m\
		Eau+FocusFrame.m\
		Eau+WindowDecoration.m\
		Eau+TitleBarButtons.m\
		Eau+Menu.m\
		Eau+Slider.m\
		Eau+ProgressIndicator.m\
		Eau+Scroller.m\
		Eau+ColorWell.m\
		Eau+Stepper.m\
		Eau+Segmented.m\
		Eau+Browser.m\
		Eau+Table.m\
		Eau+TabView.m\
		Eau+ResizeZones.m\
		EauGrowBoxCell.m\
		EauGrowBoxView.m\
		GSStandardDecorationView+Eau.m\
		GSInfoPanel+Eau.m\
		NSApplication+Eau.m\
		NSWindow+Eau.m\
		NSSegmentedCell+Eau.m\
		NSTableView+Eau.m\
		NSTableHeaderCell+Eau.m\
		EauWindowButton.m\
		EauWindowButtonCell.m\
		EauTitleBarButton.m\
		EauTitleBarButtonCell.m\
		EauScrollerKnobCell.m\
		EauScrollerKnobSlotCell.m\
		EauScrollerArrowCell.m\
		NSAlert+Eau.m\
		NSBrowserCell+Eau.m\
		NSSearchField+Eau.m\
		NSSearchFieldCell+Eau.m\
		NSBeep+Eau.m\
		GWDialog+Eau.m\
		NSCell+Eau.m\
		NSButtonCell+Eau.m\
		NSButton+Eau.m\
		NSTextFieldCell+Eau.m\
		NSTextView+Eau.m\
		NSFont+Eau.m\
		NSMenuItemCell+Eau.m\
		NSMenuView+Eau.m\
		NSMenu+Eau.m\
		NSBox+Eau.m\
		NSPopUpButton+Eau.m\
		GSDisplayServer+Eau.m\
		Eau+DragTool.m

# StepTalk scripting support (auto-detected on install)
STEPTALK_LIB := $(firstword $(wildcard \
  $(GNUSTEP_SYSTEM_LIBRARY)/Libraries/libStepTalk.so \
  $(GNUSTEP_LOCAL_LIBRARY)/Libraries/libStepTalk.so \
  $(GNUSTEP_LIBRARY)/Libraries/libStepTalk.so))
with_steptalk = $(if $(STEPTALK_LIB),yes)
ifeq ($(with_steptalk), yes)
  Eau_OBJC_FILES += NSApplication+STScripting.m
endif

ADDITIONAL_TOOL_LIBS =
ADDITIONAL_OBJCFLAGS += -fobjc-arc -fobjc-arc-exceptions
ADDITIONAL_LDFLAGS += -lX11
ifeq ($(with_steptalk), yes)
  ADDITIONAL_LDFLAGS += -lStepTalk
endif
$(BUNDLE_NAME)_RESOURCE_FILES = \
	./Resources/ThemeIcon.png\
	./Resources/ThemePreview.png\
	./Resources/ThemeImages\
	./Resources/ThemeTiles\
	./Resources/*.clr
include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble

