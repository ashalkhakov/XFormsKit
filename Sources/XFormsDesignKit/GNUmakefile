#
# XFormsDesignKit -- the designer's editor as a framework (XFormsDesignKit.h):
# XFormsDesigner.app is main.m and a menu over it, and other apps host it
# to edit forms of their own. Built after XFormsKit (`make designkit` at
# the top); the window's xib goes in as it is, loaded through GSXib5.
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = XFormsDesignKit

XFormsDesignKit_NEEDS_GUI = yes
XFormsDesignKit_CURRENT_VERSION_NAME = A
XFormsDesignKit_DEPLOY_WITH_CURRENT_VERSION = yes

XFormsDesignKit_OBJC_FILES = \
	XFDDocument.m \
	XFDEditors.m \
	XFDWindowController.m \
	XFDWindowController+Outline.m \
	XFDWindowController+Inspector.m \
	XFDWindowController+Preview.m \
	XFDInspectorSpecs.m \
	XFDPalettePanel.m \
	XFDInstanceXMLEditor.m \
	XFDEventsPane.m \
	XFDActionRowsPane.m \
	XFDSubmissionTester.m \
	XFDEventsConsole.m \
	XFDXPathField.m \
	XFDXPathTextStorage.m \
	XFDExpressionField.m \
	XFDRichTextField.m \
	XFDIDRefField.m \
	XFDDesignOverlay.m \
	ThirdParty/DMTabBar/DMTabBar.m \
	ThirdParty/DMTabBar/DMTabBarItem.m \
	ThirdParty/JUInspectorView/JUInspectorBaseView.m \
	ThirdParty/JUInspectorView/JUInspectorView.m \
	ThirdParty/JUInspectorView/JUInspectorViewContainer.m \
	ThirdParty/JUInspectorView/JUInspectorViewHeader.m

XFormsDesignKit_RESOURCE_FILES = XFDDocumentWindow.xib

XFormsDesignKit_INCLUDE_DIRS = \
	-I. \
	-I.. \
	-I../XFormsKit \
	-IThirdParty/DMTabBar \
	-IThirdParty/JUInspectorView

XFormsDesignKit_OBJCFLAGS += -fobjc-arc -Wall
XFormsDesignKit_LIBRARIES_DEPEND_UPON += -lXFormsKit -ldispatch
# Windows: XFORMSDESIGNKIT_EXPORT (in its headers) is "export" while it is
# built, an import elsewhere (as XFormsKit's GNUmakefile says).
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
XFormsDesignKit_CPPFLAGS += "-DXFORMSDESIGNKIT_EXPORT=__declspec(dllexport) extern"
endif
# The framework's import library is beside its DLL on Windows
# (XFormsKit.framework), in Versions/Current elsewhere.
XFormsDesignKit_LIB_DIRS += -L../../XFormsKit.framework/Versions/Current -L../../XFormsKit.framework

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/framework.make
-include GNUmakefile.postamble
