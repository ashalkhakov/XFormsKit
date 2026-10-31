#
# GNUmakefile — XFormsKit on GNUstep: the framework, the designer's editor
# (XFormsDesignKit), the apps, and their tests.
#
#   make            the framework and its test bundles, then XFormsDesignKit
#                   and the apps (XFormsViewer, XFormsDesigner, XFormsLauncher)
#   make check      the sources checked (Scripts/check-sources.sh), the unit
#                   tests and the W3C XForms 1.1 suite (under Xvfb when there
#                   is no display: the widget tests and some W3C cases draw)
#   make install    the framework, XFormsDesignKit and the apps; not the test
#                   bundles
#
# macOS and iOS: Makefile.apple.
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
BUNDLE_NAME = XFormsKitTests XFW3CTests
# Built and run, never installed.
XFormsKitTests_STANDARD_INSTALL = no
XFW3CTests_STANDARD_INSTALL = no

XFormsKit_NEEDS_GUI = yes
XFormsKit_CURRENT_VERSION_NAME = A
XFormsKit_DEPLOY_WITH_CURRENT_VERSION = yes

XFormsKit_HEADER_FILES_DIR = Sources/XFormsKit
XFormsKit_HEADER_FILES = \
	XFormsKit.h \
	XFDOM.h \
	XFXMLTypes.h \
	XFDOMNode.h \
	XFDOMElement.h \
	XFDOMDocument.h \
	XFFormRows.h \
	XFFormViewController.h \
	XFNamespaces.h \
	XFErrors.h \
	XFXML.h \
	XFMarkupParts.h \
	XFDateDisplay.h \
	XFInstance.h \
	XFModel.h \
	XFBind.h \
	XFNodeState.h \
	XFType.h \
	XFMIPBinding.h \
	XFExprContext.h \
	XFXPathValue.h \
	XFXPath.h \
	XFBinding.h \
	XFControl.h \
	XFInputControl.h \
	XFOutputControl.h \
	XFSecretControl.h \
	XFTextareaControl.h \
	XFTriggerControl.h \
	XFSubmitControl.h \
	XFSelectControl.h \
	XFRangeControl.h \
	XFUploadControl.h \
	XFLabelControl.h \
	XFGroup.h \
	XFHostNode.h \
	XFTableModel.h \
	XFHostEdit.h \
	XFVarControl.h \
	XFDialog.h \
	XFSubform.h \
	XFRichText.h \
	XFRichTextEditor.h \
	XFAVT.h \
	XFSVG.h \
	XFRepeat.h \
	XFSwitch.h \
	XFProcessor.h \
	XFDeferredUpdates.h \
	XFAbstractAction.h \
	XFAction.h \
	XFSetvalueAction.h \
	XFDispatchAction.h \
	XFMessageAction.h \
	XFModelAction.h \
	XFSendAction.h \
	XFLoadAction.h \
	XFSetindexAction.h \
	XFInsertAction.h \
	XFDeleteAction.h \
	XFToggleAction.h \
	XFSetfocusAction.h \
	XFSubmission.h \
	XFSubmissionTransport.h \
	XFFormView.h \
	XFCrashReporter.h \
	XFEvent.h \
	XFListener.h \
	XFXMLEvents.h

XFormsKit_OBJC_FILES = \
	Sources/XFormsKit/XFNamespaces.m \
	Sources/XFormsKit/XFErrors.m \
	Sources/XFormsKit/XFXML.m \
	Sources/XFormsKit/XFMarkupParts.m \
	Sources/XFormsKit/XFDateDisplay.m \
	Sources/XFormsKit/XFInstance.m \
	Sources/XFormsKit/XFNodeState.m \
	Sources/XFormsKit/XFType.m \
	Sources/XFormsKit/XFMIPBinding.m \
	Sources/XFormsKit/XFBind.m \
	Sources/XFormsKit/XFModel.m \
	Sources/XFormsKit/XPath/XFExprContext.m \
	Sources/XFormsKit/XPath/XFXPathValue.m \
	Sources/XFormsKit/XPath/XFExprs.m \
	Sources/XFormsKit/XPath/XFNodeTests.m \
	Sources/XFormsKit/XPath/XFLocationExpr.m \
	Sources/XFormsKit/XPath/XFStepExpr.m \
	Sources/XFormsKit/XPath/XFPathExpr.m \
	Sources/XFormsKit/XPath/XFBinaryExpr.m \
	Sources/XFormsKit/XPath/XFExprSource.m \
	Sources/XFormsKit/XPath/XFXPathFunction.m \
	Sources/XFormsKit/XPath/XFXPathCoreFunctions.m \
	Sources/XFormsKit/XPath/XFXPathExtraFunctions.m \
	Sources/XFormsKit/XPath/XFFunctionCallExpr.m \
	Sources/XFormsKit/XPath/XFXPathLexer.m \
	Sources/XFormsKit/XPath/XFXPathParser.m \
	Sources/XFormsKit/XPath/XFXPath.m \
	Sources/XFormsKit/XFBinding.m \
	Sources/XFormsKit/XFControl.m \
	Sources/XFormsKit/XFInputControl.m \
	Sources/XFormsKit/XFOutputControl.m \
	Sources/XFormsKit/XFSecretControl.m \
	Sources/XFormsKit/XFTextareaControl.m \
	Sources/XFormsKit/XFTriggerControl.m \
	Sources/XFormsKit/XFSubmitControl.m \
	Sources/XFormsKit/XFSelectControl.m \
	Sources/XFormsKit/XFRangeControl.m \
	Sources/XFormsKit/XFUploadControl.m \
	Sources/XFormsKit/XFLabelControl.m \
	Sources/XFormsKit/XFGroup.m \
	Sources/XFormsKit/XFHostNode.m \
	Sources/XFormsKit/XFTableModel.m \
	Sources/XFormsKit/XFHostEdit.m \
	Sources/XFormsKit/XFAVT.m \
	Sources/XFormsKit/XFVarControl.m \
	Sources/XFormsKit/XFDialog.m \
	Sources/XFormsKit/XFSubform.m \
	Sources/XFormsKit/XFRepeat.m \
	Sources/XFormsKit/XFSwitch.m \
	Sources/XFormsKit/XFProcessor.m \
	Sources/XFormsKit/XFDeferredUpdates.m \
	Sources/XFormsKit/XFAbstractAction.m \
	Sources/XFormsKit/XFAction.m \
	Sources/XFormsKit/XFSetvalueAction.m \
	Sources/XFormsKit/XFDispatchAction.m \
	Sources/XFormsKit/XFMessageAction.m \
	Sources/XFormsKit/XFModelAction.m \
	Sources/XFormsKit/XFSendAction.m \
	Sources/XFormsKit/XFLoadAction.m \
	Sources/XFormsKit/XFSetindexAction.m \
	Sources/XFormsKit/XFInsertAction.m \
	Sources/XFormsKit/XFDeleteAction.m \
	Sources/XFormsKit/XFToggleAction.m \
	Sources/XFormsKit/XFSetfocusAction.m \
	Sources/XFormsKit/XFSubmission.m \
	Sources/XFormsKit/XFSubmissionTransport.m \
	Sources/XFormsKit/XFEvent.m \
	Sources/XFormsKit/XFListener.m \
	Sources/XFormsKit/XFXMLEvents.m \
	Sources/XFormsKit/DOM/XFDOMNode.m \
	Sources/XFormsKit/DOM/XFDOMElement.m \
	Sources/XFormsKit/DOM/XFDOMDocument.m \
	Sources/XFormsKit/DOM/XFDOMParser.m \
	Sources/XFormsKit/SVG/XFSVGDocument.m \
	Sources/XFormsKit/RichText/XFRichText.m \
	Sources/XFormsKit/UIKit/XFFormRows.m \
	Sources/XFormsKit/AppKit/XFFormView.m \
	Sources/XFormsKit/AppKit/XFFormView+Widgets.m \
	Sources/XFormsKit/AppKit/XFFormView+Layout.m \
	Sources/XFormsKit/AppKit/XFFormView+Editing.m \
	Sources/XFormsKit/AppKit/XFTableAdapter.m \
	Sources/XFormsKit/AppKit/XFRichTextEditor.m \
	Sources/XFormsKit/AppKit/XFRichTextPresentation.m \
	Sources/XFormsKit/AppKit/XFSVGView.m

# The crash reporter, one file for each kind of system (XFCrashReporter.h).
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
XFormsKit_OBJC_FILES += Sources/XFormsKit/AppKit/XFCrashReporter-windows.m
else
XFormsKit_OBJC_FILES += Sources/XFormsKit/AppKit/XFCrashReporter-posix.m
endif

XFormsKit_INCLUDE_DIRS = -ISources -ISources/XFormsKit -ISources/XFormsKit/XPath
XFormsKit_OBJCFLAGS += -fobjc-arc -Wall -Wextra
# Opal supplies CoreGraphics and CoreText on GNUstep; the SVG renderer
# draws through both. Apple platforms get them from the system frameworks,
# which the Xcode project links instead. corebase comes with them: the
# CoreText calls are reference counted with CFRelease and name their
# arguments with CFSTR, and those two live in corebase rather than in
# Opal -- without it the framework loads and then dies at the first
# <text> it paints.
XFormsKit_LIBRARIES_DEPEND_UPON += -ldispatch -lcrypto -lopal -lgnustep-corebase
# Windows: a DLL exports what it marks, and once the runtime marks its
# classes, its C constants and functions must be marked too: XFORMSKIT_EXPORT
# (in its headers) is "export" while it is built, an import elsewhere.
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
XFormsKit_CPPFLAGS += "-DXFORMSKIT_EXPORT=__declspec(dllexport) extern"
endif

XFormsKitTests_NEEDS_GUI = yes
XFormsKitTests_OBJC_FILES = \
	Tests/XFormsKitTests/XFDOMTests.m \
	Tests/XFormsKitTests/XFDateDisplayTests.m \
	Tests/XFormsKitTests/XFRichSupportTests.m \
	Tests/XFormsKitTests/XFSVGRenderTests.m \
	Tests/XFormsKitTests/XFDXPathHighlightTests.m \
	Sources/XFormsDesignKit/XFDXPathTextStorage.m \
	Tests/XFormsKitTests/XFFormRowsTests.m \
	Tests/XFormsKitTests/XFXPathTests.m \
	Tests/XFormsKitTests/XFInstanceTests.m \
	Tests/XFormsKitTests/XFHelloFormTests.m \
	Tests/XFormsKitTests/XFXMLEventsTests.m \
	Tests/XFormsKitTests/XFModelBindTests.m \
	Tests/XFormsKitTests/XFActionTests.m \
	Tests/XFormsKitTests/XFSubmissionTests.m \
	Tests/XFormsKitTests/XFRepeatGroupTests.m \
	Tests/XFormsKitTests/XFInsertDeleteTests.m \
	Tests/XFormsKitTests/XFUIControlTests.m \
	Tests/XFormsKitTests/XFTypeTests.m

XFormsKitTests_RESOURCE_FILES = Tests/Fixtures/hello.xhtml
# Sources/XFormsDesignKit is on the path for XFDXPathHighlightTests, which
# drives the designer's XFDXPathTextStorage directly. The storage is
# compiled into this bundle rather than linked from XFormsDesignKit, which
# is built after this bundle: the syntax highlighting is worth testing
# without the rest of the designer.
# AppKit/ is on this list for XFAppKitPriv.h: the widget tests reach into the
# view layer's private interfaces -- the table adapter, for one -- which the
# Xcode target's header search path already allowed and this did not.
XFormsKitTests_INCLUDE_DIRS = -ISources -ISources/XFormsKit -ISources/XFormsKit/XPath \
                              -ISources/XFormsKit/AppKit -ISources/XFormsDesignKit
XFormsKitTests_OBJCFLAGS += -fobjc-arc -Wall
# Opal and corebase too: the SVG tests draw through CoreGraphics themselves,
# and a Windows DLL names every library it uses.
XFormsKitTests_BUNDLE_LIBS += -lXFormsKit -lXCTest -lopal -lgnustep-corebase
# The framework's import library is beside its DLL on Windows
# (XFormsKit.framework), in Versions/Current elsewhere.
XFormsKitTests_LIB_DIRS += -L./XFormsKit.framework/Versions/Current -L./XFormsKit.framework
XFormsKitTests_PRINCIPAL_CLASS = XCTestCase

# The W3C XForms 1.1 suite as per-case XCTest assertions (Tests/W3CTests):
# each test loads its suite form headlessly and asserts the behavior the
# form's instruction text demands — widget state and model state, never
# pixels. Spec-true by policy: a case the engine gets wrong stays RED, so
# w3ccheck is a conformance report, not a regression gate — `make check`
# (the unit bundle) remains the always-green gate.
XFW3CTests_NEEDS_GUI = yes
XFW3CTests_OBJC_FILES = \
	Tests/W3CTests/XFW3CTestCase.m \
	Tests/W3CTests/XFW3CChapter02Tests.m \
	Tests/W3CTests/XFW3CChapter03Tests.m \
	Tests/W3CTests/XFW3CChapter04Tests.m \
	Tests/W3CTests/XFW3CChapter05Tests.m \
	Tests/W3CTests/XFW3CChapter06Tests.m \
	Tests/W3CTests/XFW3CChapter07Tests.m \
	Tests/W3CTests/XFW3CChapter08Tests.m \
	Tests/W3CTests/XFW3CChapter09Tests.m \
	Tests/W3CTests/XFW3CChapter10Tests.m \
	Tests/W3CTests/XFW3CChapter11Tests.m \
	Tests/W3CTests/XFW3CAppendixBTests.m \
	Tests/W3CTests/XFW3CAppendixGTests.m \
	Tests/W3CTests/XFW3CAppendixHTests.m

XFW3CTests_INCLUDE_DIRS = -ISources -ISources/XFormsKit -ISources/XFormsKit/XPath -ITests/W3CTests
XFW3CTests_OBJCFLAGS += -fobjc-arc -Wall

XFW3CTests_BUNDLE_LIBS += -lXFormsKit -lXCTest
XFW3CTests_LIB_DIRS += -L./XFormsKit.framework/Versions/Current -L./XFormsKit.framework
XFW3CTests_PRINCIPAL_CLASS = XCTestCase

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/framework.make
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble

# The rest, on the framework: the designer's editor and the apps.
XF_APPS = Apps/XFormsViewer Apps/XFormsDesigner Apps/XFormsLauncher
after-all::
	$(MAKE) -C Sources/XFormsDesignKit
	@for app in $(XF_APPS); do $(MAKE) -C $$app || exit 1; done

after-install::
	$(MAKE) -C Sources/XFormsDesignKit install
	@for app in $(XF_APPS); do $(MAKE) -C $$app install || exit 1; done

after-clean::
	$(MAKE) -C Sources/XFormsDesignKit clean
	@for app in $(XF_APPS); do $(MAKE) -C $$app clean || exit 1; done

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
# The tree's framework is found on LD_LIBRARY_PATH, and on Windows on PATH
# (its DLL beside the wrapper's top, XFormsKit.framework).
check:: all
	Scripts/check-sources.sh
	@if command -v xctest >/dev/null 2>&1; then \
	  LD_LIBRARY_PATH="$(CURDIR)/XFormsKit.framework/Versions/Current:$$LD_LIBRARY_PATH" \
	  PATH="$(CURDIR)/XFormsKit.framework:$$PATH" \
	  $(XVFB) xctest ./XFormsKitTests.bundle; \
	else \
	  echo "xctest not on PATH. Install gnustep/tools-xctest and re-run make check."; \
	  exit 1; \
	fi
	$(XVFB) $(MAKE) w3ccheck

viewer: all
	$(MAKE) -C Apps/XFormsViewer

# The designer's editor as a framework (Sources/XFormsDesignKit), which the
# designer app and other apps that edit forms link.
designkit: all
	$(MAKE) -C Sources/XFormsDesignKit

designer: designkit
	$(MAKE) -C Apps/XFormsDesigner

# The chooser the AppImage opens. GNUstep only: a Mac installs the two apps
# separately and has nothing to choose between.
launcher:
	$(MAKE) -C Apps/XFormsLauncher

apps: viewer designer launcher

# The W3C suite as XCTest assertions (spec-true: engine gaps stay red).
w3ccheck: all
	@if command -v xctest >/dev/null 2>&1; then \
	  LD_LIBRARY_PATH="$(CURDIR)/XFormsKit.framework/Versions/Current:$$LD_LIBRARY_PATH" \
	  PATH="$(CURDIR)/XFormsKit.framework:$$PATH" \
	  xctest ./XFW3CTests.bundle; \
	else \
	  echo "xctest not on PATH. Install gnustep/tools-xctest and re-run make w3ccheck."; \
	  exit 1; \
	fi

# The W3C XForms 1.1 suite, end to end and headless (TestSuite/README.md).
testsuite: all
	$(MAKE) -C tools/xftestrun
	LD_LIBRARY_PATH="$(CURDIR)/XFormsKit.framework/Versions/Current:$$LD_LIBRARY_PATH" \
	  PATH="$(CURDIR)/XFormsKit.framework:$$PATH" \
	  ./tools/xftestrun/obj/xftestrun TestSuite/XForms1.1/Edition1
