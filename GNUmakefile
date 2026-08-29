#
# GNUmakefile — XFormsKit framework + XCTest bundle
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = XFormsKit
FRAMEWORK_NAME = XFormsKit
BUNDLE_NAME = XFormsKitTests

XFormsKit_NEEDS_GUI = yes
XFormsKit_CURRENT_VERSION_NAME = A
XFormsKit_DEPLOY_WITH_CURRENT_VERSION = yes

XFormsKit_HEADER_FILES_DIR = Sources/XFormsKit
XFormsKit_HEADER_FILES = \
	XFormsKit.h \
	XFNamespaces.h \
	XFErrors.h \
	XFXML.h \
	XFInstance.h \
	XFModel.h \
	XFExprContext.h \
	XFXPathValue.h \
	XFXPath.h \
	XFBinding.h \
	XFControl.h \
	XFInputControl.h \
	XFOutputControl.h \
	XFProcessor.h \
	XFFormView.h

XFormsKit_OBJC_FILES = \
	Sources/XFormsKit/XFNamespaces.m \
	Sources/XFormsKit/XFErrors.m \
	Sources/XFormsKit/XFXML.m \
	Sources/XFormsKit/XFInstance.m \
	Sources/XFormsKit/XFModel.m \
	Sources/XFormsKit/XPath/XFExprContext.m \
	Sources/XFormsKit/XPath/XFXPathValue.m \
	Sources/XFormsKit/XPath/XFXPathLexer.m \
	Sources/XFormsKit/XPath/XFXPathParser.m \
	Sources/XFormsKit/XPath/XFXPath.m \
	Sources/XFormsKit/XFBinding.m \
	Sources/XFormsKit/XFControl.m \
	Sources/XFormsKit/XFInputControl.m \
	Sources/XFormsKit/XFOutputControl.m \
	Sources/XFormsKit/XFProcessor.m \
	Sources/XFormsKit/UI/XFFormView.m

XFormsKit_INCLUDE_DIRS = -ISources -ISources/XFormsKit -ISources/XFormsKit/XPath
XFormsKit_OBJCFLAGS += -fobjc-arc -Wall -Wextra

XFormsKitTests_NEEDS_GUI = yes
XFormsKitTests_OBJC_FILES = \
	Tests/XFormsKitTests/XFXPathTests.m \
	Tests/XFormsKitTests/XFInstanceTests.m \
	Tests/XFormsKitTests/XFHelloFormTests.m

XFormsKitTests_RESOURCE_FILES = Tests/Fixtures/hello.xhtml
XFormsKitTests_INCLUDE_DIRS = -ISources -ISources/XFormsKit -ISources/XFormsKit/XPath
XFormsKitTests_OBJCFLAGS += -fobjc-arc -Wall
XFormsKitTests_BUNDLE_LIBS += -lXFormsKit -lXCTest
XFormsKitTests_LIB_DIRS += -L./XFormsKit.framework/Versions/Current
XFormsKitTests_PRINCIPAL_CLASS = XCTestCase

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/framework.make
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble

check:: all
	@if command -v xctest >/dev/null 2>&1; then \
	  xctest ./XFormsKitTests.bundle; \
	else \
	  echo "xctest not on PATH. Install gnustep/tools-xctest and re-run make check."; \
	  exit 1; \
	fi
