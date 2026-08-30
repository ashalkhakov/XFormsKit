#
# XFormsViewer — document-based XHTML+XForms host
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = XFormsViewer

XFormsViewer_OBJC_FILES = \
	main.m \
	XFFormDocument.m \
	XFDocumentWindowController.m

XFormsViewer_RESOURCE_FILES = \
	../../Samples/hello.xhtml \
	../../Samples/address.xhtml \
	../../Samples/bind.xhtml \
	../../Samples/button.xhtml \
	../../Samples/checkbox.xhtml \
	../../Samples/date.xhtml \
	../../Samples/range.xhtml \
	../../Samples/readonly.xhtml \
	../../Samples/relevant.xhtml \
	../../Samples/repeat.xhtml \
	../../Samples/secret.xhtml \
	../../Samples/select1.xhtml \
	../../Samples/choices.xhtml \
	../../Samples/switch.xhtml \
	../../Samples/textarea.xhtml \
	../../Samples/upload.xhtml \
	../../Samples/output-image.xhtml

XFormsViewer_INCLUDE_DIRS = \
	-I. \
	-I../../Sources \
	-I../../Sources/XFormsKit \
	-I../../Sources/XFormsKit/XPath

XFormsViewer_OBJCFLAGS += -fobjc-arc -Wall
XFormsViewer_TOOL_LIBS += -lXFormsKit
XFormsViewer_LIB_DIRS += -L../../XFormsKit.framework/Versions/Current
XFormsViewer_MAIN_MODEL_FILE =

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble
