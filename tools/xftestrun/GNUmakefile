# xftestrun — the W3C XForms 1.1 test-suite runner (headless E2E).
# Builds against the XFormsKit framework two levels up:
#   make && ./obj/xftestrun ../../TestSuite/XForms1.1/Edition1
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = xftestrun
xftestrun_OBJC_FILES = main.m
xftestrun_INCLUDE_DIRS = -I../.. -I../../Sources -I../../Sources/XFormsKit
xftestrun_OBJCFLAGS += -fobjc-arc -Wall -Wextra
xftestrun_TOOL_LIBS += -lXFormsKit -lgnustep-gui
xftestrun_LIB_DIRS += -L../../XFormsKit.framework/Versions/Current

include $(GNUSTEP_MAKEFILES)/tool.make
