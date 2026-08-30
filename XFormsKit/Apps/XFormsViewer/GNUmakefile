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
	../../Samples/XMLSchemaTypeCode.xml \
	../../Samples/address.xhtml \
	../../Samples/balance-table.xhtml \
	../../Samples/balance.xhtml \
	../../Samples/bind.xhtml \
	../../Samples/bookmarks.xhtml \
	../../Samples/books.xhtml \
	../../Samples/button.xhtml \
	../../Samples/calculator.xhtml \
	../../Samples/checkbox.xhtml \
	../../Samples/choices.xhtml \
	../../Samples/colors.xhtml \
	../../Samples/counties.xml \
	../../Samples/date.xhtml \
	../../Samples/deep-copy.xhtml \
	../../Samples/first-field.xhtml \
	../../Samples/flag.svg \
	../../Samples/flags.xhtml \
	../../Samples/gantt.xhtml \
	../../Samples/hello.xhtml \
	../../Samples/incremental-textarea.xhtml \
	../../Samples/incremental.xhtml \
	../../Samples/input-width.xhtml \
	../../Samples/input.xhtml \
	../../Samples/output-image.xhtml \
	../../Samples/piechart.xhtml \
	../../Samples/range.xhtml \
	../../Samples/readonly.xhtml \
	../../Samples/relevant.xhtml \
	../../Samples/repeat.xhtml \
	../../Samples/secret.xhtml \
	../../Samples/select-from-file.xhtml \
	../../Samples/select-model.xhtml \
	../../Samples/select-multi-col.xhtml \
	../../Samples/select.xhtml \
	../../Samples/select1-drop.xhtml \
	../../Samples/select1.xhtml \
	../../Samples/spreadsheet.xhtml \
	../../Samples/switch.xhtml \
	../../Samples/textarea-styled.xhtml \
	../../Samples/textarea.css \
	../../Samples/textarea.xhtml \
	../../Samples/tinymce.xhtml \
	../../Samples/upload.xhtml \
	../../Samples/uploads.xhtml \
	../../Samples/wikipediasearch.xhtml \
	../../Samples/writers.xhtml \
	../../Samples/xf.xhtml \
	../../Samples/xpath.xhtml

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
