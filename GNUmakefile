include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = Rick
BUNDLE_NAME = Rik
BUNDLE_EXTENSION = .theme
VERSION = 1

Rik_INSTALL_DIR=$(GNUSTEP_LIBRARY)/Themes
Rik_PRINCIPAL_CLASS = Rik

Rik_OBJC_FILES = \
		Rik.m\
		Rik+Drawings.m\
		Rik+Button.m\
		Rik+FocusFrame.m\
		Rik+WindowDecoration.m\
		Rik+Menu.m\
		Rik+Slider.m\
		Rik+ProgressIndicator.m\
		Rik+Scroller.m\
		Rik+ColorWell.m\
		Rik+Stepper.m\
		Rik+Segmented.m\
		Rik+Browser.m\
		Rik+Table.m\
		GSStandardDecorationView+Rik.m\
		NSWindow+Rik.m\
		NSSegmentedCell+Rik.m\
		RikWindowButton.m\
		RikWindowButtonCell.m\
		RikScrollerKnobCell.m\
		RikScrollerKnobSlotCell.m\
		RikScrollerArrowCell.m\
		NSBrowserCell+Rik.m\
		NSSearchFieldCell+Rik.m\
		NSCell+Rik.m\
		NSButtonCell+Rik.m\
		NSTextFieldCell+Rik.m\
		NSBox+Rik.m\
		NSPopUpButton+Rik.m
ADDITIONAL_TOOL_LIBS =
$(BUNDLE_NAME)_RESOURCE_FILES = \
	./Resources/ThemeIcon.png\
	./Resources/ThemePreview.png\
	./Resources/ThemeImages\
	./Resources/ThemeTiles\
	./Resources/*.clr
include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble

