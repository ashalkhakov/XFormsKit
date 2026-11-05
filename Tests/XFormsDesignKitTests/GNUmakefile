#
# XFormsDesignKitTests -- the designer's parts and what they are built on
# (XFDPartsTests, XFDInspectorTests, XFDEditorsTests, XFDServicesTests).
# Built after XFormsDesignKit, which the top GNUmakefile makes after its
# own bundles; `make check` there runs it.
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = XFormsDesignKitTests
BUNDLE_EXTENSION = .bundle

XFormsDesignKitTests_NEEDS_GUI = yes
XFormsDesignKitTests_OBJC_FILES = \
	XFDPartsTests.m \
	XFDInspectorTests.m \
	XFDEditorsTests.m \
	XFDServicesTests.m

# The forms the edit tests open: a small one, and one that paints SVG.
XFormsDesignKitTests_RESOURCE_FILES = \
	../Fixtures/hello.xhtml \
	../../Samples/piechart.xhtml

XFormsDesignKitTests_INCLUDE_DIRS = -I../../Sources -I../../Sources/XFormsKit -I../../Sources/XFormsDesignKit
XFormsDesignKitTests_OBJCFLAGS += -fobjc-arc -Wall
XFormsDesignKitTests_BUNDLE_LIBS += -lXFormsDesignKit -lXFormsKit -lXCTest
# The frameworks' import libraries are beside their DLLs on Windows, in
# Versions/Current elsewhere.
XFormsDesignKitTests_LIB_DIRS += \
	-L../../Sources/XFormsDesignKit/XFormsDesignKit.framework/Versions/Current \
	-L../../Sources/XFormsDesignKit/XFormsDesignKit.framework \
	-L../../XFormsKit.framework/Versions/Current -L../../XFormsKit.framework
XFormsDesignKitTests_PRINCIPAL_CLASS = XCTestCase

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble
