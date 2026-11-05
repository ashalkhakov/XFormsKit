# The XForms extension's tests (an XCTest bundle; tools-xctest), against
# UDCode's SDK installed: the extension's sources and XFormsDesignKit's
# compiled in (their XIBs found in this bundle, as in XForms.bundle),
# UDCodeKit's document and text model linked.
#
#   make            build the bundle
#   make run-tests  build and run it (under xvfb-run where there is no display)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = XFUTests
XFUTests_STANDARD_INSTALL = no

DESIGNKIT = ../../Sources/XFormsDesignKit
include $(DESIGNKIT)/files.make
XFUTests_OBJC_FILES = \
  XFUTests.m \
  ../XFUExtension.m \
  ../XFUEditorViewController.m \
  ../XFUTextDiff.m \
  $(addprefix $(DESIGNKIT)/,$(XFORMSDESIGNKIT_OBJC_FILES))
XFUTests_RESOURCE_FILES = \
  ../XFUEditor.xib \
  ../XFUEditorMenus.xib \
  $(addprefix $(DESIGNKIT)/,$(XFORMSDESIGNKIT_RESOURCE_FILES))
XFUTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
ifeq ($(OS),Windows_NT)
XFUTests_CPPFLAGS += -DXFORMSDESIGNKIT_EXPORT=extern
endif
XFUTests_INCLUDE_DIRS = -I.. -I$(DESIGNKIT) -I$(DESIGNKIT)/ThirdParty/DMTabBar -I$(DESIGNKIT)/ThirdParty/JUInspectorView \
  -I../../Sources -I../../Sources/XFormsKit
ADDITIONAL_LIB_DIRS += -L../../XFormsKit.framework/Versions/Current -L../../XFormsKit.framework
XFUTests_BUNDLE_LIBS += -lXFormsKit -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch
XFUTests_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 600

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/../../XFormsKit.framework/Versions/Current:$$LD_LIBRARY_PATH" \
	PATH="$(CURDIR)/../../XFormsKit.framework:$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
