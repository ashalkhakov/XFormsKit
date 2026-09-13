#
# XFormsDesigner — document-based XHTML+XForms form designer
# (the runner is Apps/XFormsViewer). The window layout lives in
# XFDDocumentWindow.xib, loaded through GSXib5 on GNUstep.
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
XFormsDesigner_OBJC_FILES = \
	main.m \
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

XFormsDesigner_RESOURCE_FILES = \
	MainMenu.xib \
	XFDDocumentWindow.xib \
	Info-gnustep.plist

XFormsDesigner_MAIN_MODEL_FILE = MainMenu.xib

XFormsDesigner_INCLUDE_DIRS = \
	-I. \
	-I../../Sources \
	-I../../Sources/XFormsKit \
	-IThirdParty/DMTabBar \
	-IThirdParty/JUInspectorView

XFormsDesigner_OBJCFLAGS += -fobjc-arc -Wall
XFormsDesigner_TOOL_LIBS += -lXFormsKit
XFormsDesigner_LIB_DIRS += -L../../XFormsKit.framework/Versions/Current

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble

after-all::
	@dst="./$(APP_NAME).app/Resources"; \
	mkdir -p "$$dst"; \
	cp -f MainMenu.xib XFDDocumentWindow.xib Info-gnustep.plist "$$dst/"
