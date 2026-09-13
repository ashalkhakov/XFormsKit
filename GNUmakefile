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
BUNDLE_NAME = XFormsKitTests XFW3CTests

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
	Sources/XFormsKit/AppKit/XFSVGView.m \
	Sources/XFormsKit/AppKit/XFCrashReporter.m

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

XFormsKitTests_NEEDS_GUI = yes
XFormsKitTests_OBJC_FILES = \
	Tests/XFormsKitTests/XFDOMTests.m \
	Tests/XFormsKitTests/XFDateDisplayTests.m \
	Tests/XFormsKitTests/XFRichSupportTests.m \
	Tests/XFormsKitTests/XFSVGRenderTests.m \
	Tests/XFormsKitTests/XFDXPathHighlightTests.m \
	Apps/XFormsDesigner/XFDXPathTextStorage.m \
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
# Apps/XFormsDesigner is on the path for XFDXPathHighlightTests, which
# drives the designer's XFDXPathTextStorage directly. The storage is
# compiled into this bundle rather than linked from the app: the
# designer is an executable, not a library, and the syntax
# highlighting is worth testing without it.
# AppKit/ is on this list for XFAppKitPriv.h: the widget tests reach into the
# view layer's private interfaces -- the table adapter, for one -- which the
# Xcode target's header search path already allowed and this did not.
XFormsKitTests_INCLUDE_DIRS = -ISources -ISources/XFormsKit -ISources/XFormsKit/XPath \
                              -ISources/XFormsKit/AppKit -IApps/XFormsDesigner
XFormsKitTests_OBJCFLAGS += -fobjc-arc -Wall
XFormsKitTests_BUNDLE_LIBS += -lXFormsKit -lXCTest
XFormsKitTests_LIB_DIRS += -L./XFormsKit.framework/Versions/Current
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
XFW3CTests_LIB_DIRS += -L./XFormsKit.framework/Versions/Current
XFW3CTests_PRINCIPAL_CLASS = XCTestCase

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/framework.make
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble

check:: all
	@if command -v xctest >/dev/null 2>&1; then \
	  LD_LIBRARY_PATH="$(CURDIR)/XFormsKit.framework/Versions/Current:$$LD_LIBRARY_PATH" \
	  xctest ./XFormsKitTests.bundle; \
	else \
	  echo "xctest not on PATH. Install gnustep/tools-xctest and re-run make check."; \
	  exit 1; \
	fi

viewer: all
	$(MAKE) -C Apps/XFormsViewer

designer: all
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
	  xctest ./XFW3CTests.bundle; \
	else \
	  echo "xctest not on PATH. Install gnustep/tools-xctest and re-run make w3ccheck."; \
	  exit 1; \
	fi

# The W3C XForms 1.1 suite, end to end and headless (TestSuite/README.md).
testsuite: all
	$(MAKE) -C tools/xftestrun
	LD_LIBRARY_PATH="$(CURDIR)/XFormsKit.framework/Versions/Current:$$LD_LIBRARY_PATH" \
	  ./tools/xftestrun/obj/xftestrun TestSuite/XForms1.1/Edition1
