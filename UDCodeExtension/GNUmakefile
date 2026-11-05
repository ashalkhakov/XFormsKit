include $(GNUSTEP_MAKEFILES)/common.make

# UDCode's XForms extension (docs/UDCODE.md): XForms.bundle, XFormsDesignKit's
# designer in a UDCode tab. Built against UDCode's SDK (its udcodekit archive,
# .github/pins.env's UDCODEKIT_VERSION) installed on the same GNUstep stack as
# UDCode's; the top GNUmakefile builds it only where that SDK is.
# Scripts/udcx.sh packages it, its libraries inside it.
BUNDLE_NAME = XForms
BUNDLE_EXTENSION = .bundle
XForms_PRINCIPAL_CLASS = XFUExtension
XForms_NEEDS_GUI = yes
XForms_STANDARD_INSTALL = no
# XFormsDesignKit compiled in, its XIBs among the bundle's resources (the
# parts' +designKitBundle then answers this bundle): a framework inside the
# bundle would need its DLL beside its resources, where Windows does not look
# for the bundle's DLL's libraries.
DESIGNKIT = ../Sources/XFormsDesignKit
include $(DESIGNKIT)/files.make
XForms_OBJC_FILES = \
  XFUExtension.m \
  XFUEditorViewController.m \
  XFUTextDiff.m \
  $(addprefix $(DESIGNKIT)/,$(XFORMSDESIGNKIT_OBJC_FILES))
XForms_RESOURCE_FILES = \
  Resources/LanguageInfo.plist \
  XFUEditor.xib \
  XFUEditorMenus.xib \
  $(addprefix $(DESIGNKIT)/,$(XFORMSDESIGNKIT_RESOURCE_FILES))
XForms_OBJCFLAGS += -fobjc-arc -fblocks -Wall
# Windows: XFormsDesignKit's C functions are this bundle's own, not a DLL's to
# import (XFORMSDESIGNKIT_EXPORT).
ifeq ($(OS),Windows_NT)
XForms_CPPFLAGS += -DXFORMSDESIGNKIT_EXPORT=extern
endif
XForms_INCLUDE_DIRS = -I$(DESIGNKIT) -I$(DESIGNKIT)/ThirdParty/DMTabBar -I$(DESIGNKIT)/ThirdParty/JUInspectorView \
  -I../Sources -I../Sources/XFormsKit
# XFormsKit's framework, whose library the package puts beside the binary.
XForms_LIB_DIRS += -L../XFormsKit.framework/Versions/Current -L../XFormsKit.framework
# Its own library: found from where the binary is. UDCode's own (UDCodeKit,
# GNUstep's) are the running UDCode's: on Linux left for it, as UDCode's own
# plug-ins leave them; a Windows DLL is linked against all it uses.
XForms_BUNDLE_LIBS += -lXFormsKit -ldispatch
ifneq ($(OS),Windows_NT)
XForms_LDFLAGS += -Wl,-rpath,'$$ORIGIN'
else
XForms_BUNDLE_LIBS += -lUDCodeKit -lUDPieceTable -lLSPKit -lgnustep-gui -lgnustep-base -lobjc
endif

include $(GNUSTEP_MAKEFILES)/bundle.make
