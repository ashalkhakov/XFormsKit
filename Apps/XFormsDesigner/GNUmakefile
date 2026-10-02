#
# XFormsDesigner — document-based XHTML+XForms form designer
# (the runner is Apps/XFormsViewer). The editor is XFormsDesignKit
# (Sources/XFormsDesignKit): this app is its main menu and main.m.
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = XFormsDesigner

XFormsDesigner_LDFLAGS += -ldispatch
# The app's own methods by name in a crash report (XFCrashReporter.h).
XFormsDesigner_LDFLAGS += -rdynamic
XFormsDesigner_OBJC_FILES = main.m

XFormsDesigner_RESOURCE_FILES = \
	XFormsDesigner.png \
	MainMenu.xib

XFormsDesigner_MAIN_MODEL_FILE = MainMenu.xib

XFormsDesigner_INCLUDE_DIRS = \
	-I../../Sources \
	-I../../Sources/XFormsKit \
	-I../../Sources/XFormsDesignKit \
	-I../../Sources/XFormsDesignKit/ThirdParty/DMTabBar \
	-I../../Sources/XFormsDesignKit/ThirdParty/JUInspectorView

XFormsDesigner_OBJCFLAGS += -fobjc-arc -Wall
XFormsDesigner_TOOL_LIBS += -lXFormsDesignKit -lXFormsKit
XFormsDesigner_LIB_DIRS += -L../../Sources/XFormsDesignKit/XFormsDesignKit.framework/Versions/Current \
	-L../../XFormsKit.framework/Versions/Current

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble

after-all::
	@dst="./$(APP_NAME).app/Resources"; \
	mkdir -p "$$dst"; \
	cp -f MainMenu.xib "$$dst/"
