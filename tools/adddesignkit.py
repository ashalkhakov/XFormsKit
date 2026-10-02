#!/usr/bin/env python3
"""Split the designer's editor out of the XFormsDesigner target of
XFormsKit.xcodeproj/project.pbxproj into an XFormsDesignKit framework
target (ids DK...), as the files moved to Sources/XFormsDesignKit:

  - a Sources/XFormsDesignKit group takes every designer file but main.m,
    MainMenu.xib, the Info.plist and the icon;
  - the framework target compiles them, links XFormsKit, and carries
    XFDDocumentWindow.xib as its resource;
  - XFormsDesigner compiles main.m only, and links and embeds the
    framework, which it depends on;
  - header search paths follow the files.

Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFormsDesignKit.framework' in s:
    print('already split'); sys.exit(0)

TARGET = 'DK0000000000000000000001'
PRODUCT = 'DK0000000000000000000002'
SOURCES = 'DK0000000000000000000003'
FRAMEWORKS = 'DK0000000000000000000004'
RESOURCES = 'DK0000000000000000000005'
CONFIGS = 'DK0000000000000000000006'
DEBUG = 'DK0000000000000000000007'
RELEASE = 'DK0000000000000000000008'
GROUP = 'DK0000000000000000000009'
KIT_LINK = 'DK000000000000000000000A'      # XFormsKit.framework in the kit's Frameworks
KIT_PROXY = 'DK000000000000000000000B'
KIT_DEP = 'DK000000000000000000000C'
APP_LINK = 'DK000000000000000000000D'      # XFormsDesignKit.framework in the app's Frameworks
APP_EMBED = 'DK000000000000000000000E'
APP_PROXY = 'DK000000000000000000000F'
APP_DEP = 'DK0000000000000000000010'
UMBRELLA = 'DK0000000000000000000011'      # XFormsDesignKit.h
for i in (TARGET, PRODUCT, SOURCES, FRAMEWORKS, RESOURCES, CONFIGS, DEBUG, RELEASE, GROUP,
          KIT_LINK, KIT_PROXY, KIT_DEP, APP_LINK, APP_EMBED, APP_PROXY, APP_DEP, UMBRELLA):
    assert i not in s, i

KIT = 'EE0000010000000000000001'
KIT_PRODUCT = 'BB0000010000000000000100'
APP = 'EE0000020000000000000001'
APP_GROUP = 'GG0000020000000000000001'
APP_SOURCES = 'SS0000020000000000000001'
APP_RESOURCES = 'RR0000020000000000000001'
APP_FRAMEWORKS = 'FF0000020000000000000001'
APP_EMBEDS = 'EB0000020000000000000001'
SOURCES_GROUP = 'GG0000010000000000000002'
PRODUCTS_GROUP = 'GG0000010000000000000004'
WINDOW_XIB = 'AA0000020000000000000022'
STAYS_IN_APP = ('main.m', 'MainMenu.xib', 'XFormsDesigner-Info.plist', 'XFormsDesigner.icns')


def section_end(s, name):
    i = s.find('/* End %s section */' % name)
    assert i != -1, name
    return i


def add_to_section(s, name, text):
    i = section_end(s, name)
    return s[:i] + text + s[i:]


def block_span(s, ident):
    m = re.search(r'\t\t' + ident + r' /\*[^*]*\*/ = \{', s)
    assert m, ident
    end = s.find('\n\t\t};\n', m.start()) + len('\n\t\t};\n')
    return m.start(), end


def list_entries(s, ident, key):
    """The entries of a block's list (files, children, ...)."""
    start, end = block_span(s, ident)
    block = s[start:end]
    m = re.search(r'\t\t\t' + key + r' = \(\n(.*?)\t\t\t\);', block, re.S)
    assert m, (ident, key)
    return [line.strip() for line in m.group(1).splitlines() if line.strip()]


def set_entries(s, ident, key, entries):
    start, end = block_span(s, ident)
    block = s[start:end]
    body = ''.join('\t\t\t\t%s\n' % e for e in entries)
    block = re.sub(r'(\t\t\t' + key + r' = \(\n).*?(\t\t\t\);)',
                   lambda m: m.group(1) + body + m.group(2), block, count=1, flags=re.S)
    return s[:start] + block + s[end:]


def name_of(entry):
    return re.search(r'/\* (.*?)(?: in \w+)? \*/', entry).group(1)


# The group: everything the app does not keep, the ThirdParty groups too.
children = list_entries(s, APP_GROUP, 'children')
stays = [c for c in children if name_of(c) in STAYS_IN_APP]
moves = [c for c in children if c not in stays]
s = set_entries(s, APP_GROUP, 'children', stays)
moves.insert(0, UMBRELLA + ' /* XFormsDesignKit.h */,')
s = add_to_section(s, 'PBXGroup',
    '\t\t%s /* XFormsDesignKit */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\t\t\t);\n'
    '\t\t\tpath = XFormsDesignKit;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'
    % (GROUP, ''.join('\t\t\t\t%s\n' % m for m in moves)))
s = set_entries(s, SOURCES_GROUP, 'children',
                list_entries(s, SOURCES_GROUP, 'children') + [GROUP + ' /* XFormsDesignKit */,'])
s = set_entries(s, PRODUCTS_GROUP, 'children',
                list_entries(s, PRODUCTS_GROUP, 'children') + [PRODUCT + ' /* XFormsDesignKit.framework */,'])

# Files and build files.
s = add_to_section(s, 'PBXFileReference',
    '\t\t%s /* XFormsDesignKit.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; '
    'includeInIndex = 0; path = XFormsDesignKit.framework; sourceTree = BUILT_PRODUCTS_DIR; };\n'
    '\t\t%s /* XFormsDesignKit.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; '
    'path = XFormsDesignKit.h; sourceTree = "<group>"; };\n' % (PRODUCT, UMBRELLA))
s = add_to_section(s, 'PBXBuildFile',
    '\t\t%s /* XFormsKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = %s /* XFormsKit.framework */; };\n'
    '\t\t%s /* XFormsDesignKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = %s /* XFormsDesignKit.framework */; };\n'
    '\t\t%s /* XFormsDesignKit.framework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = %s /* XFormsDesignKit.framework */; '
    'settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };\n'
    % (KIT_LINK, KIT_PRODUCT, APP_LINK, PRODUCT, APP_EMBED, PRODUCT))

# Build phases: the app's sources but main.m, and the window's xib, move.
app_sources = list_entries(s, APP_SOURCES, 'files')
s = set_entries(s, APP_SOURCES, 'files', [f for f in app_sources if name_of(f) == 'main.m'])
kit_sources = [f for f in app_sources if name_of(f) != 'main.m']
app_resources = list_entries(s, APP_RESOURCES, 'files')
s = set_entries(s, APP_RESOURCES, 'files', [f for f in app_resources if not f.startswith(WINDOW_XIB)])
s = set_entries(s, APP_FRAMEWORKS, 'files',
                list_entries(s, APP_FRAMEWORKS, 'files') + [APP_LINK + ' /* XFormsDesignKit.framework in Frameworks */,'])
s = set_entries(s, APP_EMBEDS, 'files',
                list_entries(s, APP_EMBEDS, 'files') + [APP_EMBED + ' /* XFormsDesignKit.framework in Embed Frameworks */,'])


def phase(ident, isa, name, files):
    return ('\t\t%s /* %s */ = {\n\t\t\tisa = %s;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\t\t\t);\n'
            '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n'
            % (ident, name, isa, ''.join('\t\t\t\t%s\n' % f for f in files)))


s = add_to_section(s, 'PBXSourcesBuildPhase', phase(SOURCES, 'PBXSourcesBuildPhase', 'Sources', kit_sources))
s = add_to_section(s, 'PBXFrameworksBuildPhase', phase(FRAMEWORKS, 'PBXFrameworksBuildPhase', 'Frameworks',
                                                      [KIT_LINK + ' /* XFormsKit.framework in Frameworks */,']))
s = add_to_section(s, 'PBXResourcesBuildPhase', phase(RESOURCES, 'PBXResourcesBuildPhase', 'Resources',
                                                     [WINDOW_XIB + ' /* XFDDocumentWindow.xib in Resources */,']))

# The target, and who depends on whom.
s = add_to_section(s, 'PBXNativeTarget',
    '\t\t%s /* XFormsDesignKit */ = {\n\t\t\tisa = PBXNativeTarget;\n'
    '\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "XFormsDesignKit" */;\n'
    '\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n\t\t\t);\n'
    '\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\t%s /* PBXTargetDependency */,\n\t\t\t);\n'
    '\t\t\tname = XFormsDesignKit;\n\t\t\tproductName = XFormsDesignKit;\n'
    '\t\t\tproductReference = %s /* XFormsDesignKit.framework */;\n'
    '\t\t\tproductType = "com.apple.product-type.framework";\n\t\t};\n'
    % (TARGET, CONFIGS, SOURCES, FRAMEWORKS, RESOURCES, KIT_DEP, PRODUCT))
s = add_to_section(s, 'PBXContainerItemProxy',
    '\t\t%s /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n'
    '\t\t\tcontainerPortal = DD0000010000000000000001 /* Project object */;\n\t\t\tproxyType = 1;\n'
    '\t\t\tremoteGlobalIDString = %s;\n\t\t\tremoteInfo = XFormsKit;\n\t\t};\n'
    '\t\t%s /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n'
    '\t\t\tcontainerPortal = DD0000010000000000000001 /* Project object */;\n\t\t\tproxyType = 1;\n'
    '\t\t\tremoteGlobalIDString = %s;\n\t\t\tremoteInfo = XFormsDesignKit;\n\t\t};\n'
    % (KIT_PROXY, KIT, APP_PROXY, TARGET))
s = add_to_section(s, 'PBXTargetDependency',
    '\t\t%s /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n'
    '\t\t\ttarget = %s /* XFormsKit */;\n\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n\t\t};\n'
    '\t\t%s /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n'
    '\t\t\ttarget = %s /* XFormsDesignKit */;\n\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n\t\t};\n'
    % (KIT_DEP, KIT, KIT_PROXY, APP_DEP, TARGET, APP_PROXY))
s = set_entries(s, APP, 'dependencies',
                list_entries(s, APP, 'dependencies') + [APP_DEP + ' /* PBXTargetDependency */,'])
s = re.sub(r'(targets = \(\n(?:\t\t\t\t\w+ /\* [^*]* \*/,\n)*?)(\t\t\t\tEE0000020000000000000001 /\* XFormsDesigner \*/,\n)',
           lambda m: m.group(1) + '\t\t\t\t%s /* XFormsDesignKit */,\n' % TARGET + m.group(2), s, count=1)
assert TARGET + ' /* XFormsDesignKit */,\n' in s

# Configurations: a macOS framework, its headers from the moved files.
def config(ident, name):
    return ('\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n'
            '\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;\n\t\t\t\tCURRENT_PROJECT_VERSION = 0.0.0;\n'
            '\t\t\t\tDEFINES_MODULE = NO;\n\t\t\t\tDYLIB_COMPATIBILITY_VERSION = 1;\n\t\t\t\tDYLIB_CURRENT_VERSION = 1;\n'
            '\t\t\t\tDYLIB_INSTALL_NAME_BASE = "@rpath";\n\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
            '\t\t\t\tHEADER_SEARCH_PATHS = (\n\t\t\t\t\t"$(SRCROOT)/Sources",\n\t\t\t\t\t"$(SRCROOT)/Sources/XFormsKit",\n'
            '\t\t\t\t\t"$(SRCROOT)/Sources/XFormsDesignKit",\n'
            '\t\t\t\t\t"$(SRCROOT)/Sources/XFormsDesignKit/ThirdParty/DMTabBar",\n'
            '\t\t\t\t\t"$(SRCROOT)/Sources/XFormsDesignKit/ThirdParty/JUInspectorView",\n\t\t\t\t);\n'
            '\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "LGPL-2.1";\n'
            '\t\t\t\tINSTALL_PATH = "$(LOCAL_LIBRARY_DIR)/Frameworks";\n'
            '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/../Frameworks",\n'
            '\t\t\t\t\t"@loader_path/Frameworks",\n\t\t\t\t);\n'
            '\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 11.0;\n\t\t\t\tMARKETING_VERSION = 0.0.0;\n'
            '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.xformskit.XFormsDesignKit;\n'
            '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME:c99extidentifier)";\n\t\t\t\tSDKROOT = macosx;\n'
            '\t\t\t\tSKIP_INSTALL = YES;\n\t\t\t\tSUPPORTED_PLATFORMS = macosx;\n'
            '\t\t\t};\n\t\t\tname = %s;\n\t\t};\n' % (ident, name, name))


s = add_to_section(s, 'XCBuildConfiguration', config(DEBUG, 'Debug') + config(RELEASE, 'Release'))
s = add_to_section(s, 'XCConfigurationList',
    '\t\t%s /* Build configuration list for PBXNativeTarget "XFormsDesignKit" */ = {\n'
    '\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n'
    '\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n'
    '\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n'
    % (CONFIGS, DEBUG, RELEASE))

# Every other target that looked in the app's directory looks in the kit's.
s = s.replace('"$(SRCROOT)/Apps/XFormsDesigner/ThirdParty/', '"$(SRCROOT)/Sources/XFormsDesignKit/ThirdParty/')
s = s.replace('"$(SRCROOT)/Apps/XFormsDesigner",', '"$(SRCROOT)/Sources/XFormsDesignKit",')

open(path, 'w').write(s)
print('split XFormsDesignKit out of XFormsDesigner')
