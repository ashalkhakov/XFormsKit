#
# XFormsLauncher — the app chooser inside the AppImage (GNUstep only).
# A Mac ships XFormsViewer.app and XFormsDesigner.app separately and has
# nothing to choose between, so the Xcode project does not build this.
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = XFormsLauncher

XFormsLauncher_OBJC_FILES = \
	main.m \
	XFLauncherAppDelegate.m

XFormsLauncher_RESOURCE_FILES = \
	XFormsLauncher.png

XFormsLauncher_OBJCFLAGS += -fobjc-arc -Wall -Wextra
XFormsLauncher_MAIN_MODEL_FILE =

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble
