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
	XFVarControl.h \
	XFDialog.h \
	XFSubform.h \
	XFRichText.h \
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
	XFEvent.h \
	XFListener.h \
	XFXMLEvents.h

XFormsKit_OBJC_FILES = \
	Sources/XFormsKit/XFNamespaces.m \
	Sources/XFormsKit/XFErrors.m \
	Sources/XFormsKit/XFXML.m \
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
	Sources/XFormsKit/UI/XFFormView.m \
	Sources/XFormsKit/UI/XFRichText.m

XFormsKit_INCLUDE_DIRS = -ISources -ISources/XFormsKit -ISources/XFormsKit/XPath
XFormsKit_OBJCFLAGS += -fobjc-arc -Wall -Wextra
XFormsKit_LIBRARIES_DEPEND_UPON += -ldispatch -lcrypto

XFormsKitTests_NEEDS_GUI = yes
XFormsKitTests_OBJC_FILES = \
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
	  LD_LIBRARY_PATH="$(CURDIR)/XFormsKit.framework/Versions/Current:$$LD_LIBRARY_PATH" \
	  xctest ./XFormsKitTests.bundle; \
	else \
	  echo "xctest not on PATH. Install gnustep/tools-xctest and re-run make check."; \
	  exit 1; \
	fi

viewer: all
	$(MAKE) -C Apps/XFormsViewer
