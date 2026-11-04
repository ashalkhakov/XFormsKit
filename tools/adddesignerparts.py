#!/usr/bin/env python3
"""The designer's window controller broken into parts, in
XFormsKit.xcodeproj/project.pbxproj (ids DP...):

  - the controller's categories, its private header, XFDEventsPane and
    XFDActionRowsPane leave the XFormsDesignKit target;
  - the form editor, the parts and their pages join it (sources, public
    headers), and the parts' XIBs are its resources;
  - an XFormsDesignKitTests target (Tests/XFormsDesignKitTests) tests the
    framework, with hello.xhtml and Samples/piechart.xhtml as resources.

Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFormsDesignKitTests.xctest' in s:
    print('already done'); sys.exit(0)

GONE = ['XFDWindowController+Outline.m', 'XFDWindowController+Inspector.m', 'XFDWindowController+Preview.m',
        'XFDWindowControllerPriv.h', 'XFDEventsPane.h', 'XFDEventsPane.m', 'XFDActionRowsPane.h',
        'XFDActionRowsPane.m']
SOURCES = ['XFDFormEditor.m', 'XFDPartViewController.m', 'XFDOutlineViewController.m',
           'XFDPreviewViewController.m', 'XFDInspectorViewController.m', 'XFDIdentityInspector.m',
           'XFDAttributesInspector.m', 'XFDInspectorPages.m', 'XFDEventsInspector.m',
           'XFDLibraryViewController.m']
HEADERS = [name[:-2] + '.h' for name in SOURCES]
XIBS = ['XFDOutlineViewController.xib', 'XFDPreviewViewController.xib', 'XFDInspectorViewController.xib', 'XFDIdentityInspector.xib',
        'XFDAttributesInspector.xib', 'XFDEventsInspector.xib', 'XFDLibrary.xib', 'XFDPalettePanel.xib',
        'XFDEventsConsole.xib', 'XFDEventsConsolePanel.xib']
TESTS = ['XFDPartsTests.m', 'XFDServicesTests.m']

KIT_GROUP = 'DK0000000000000000000009'
KIT_SOURCES = 'DK0000000000000000000003'
KIT_RESOURCES = 'DK0000000000000000000005'
KIT_HEADERS = 'PH0000000000000000000001'
KIT_TARGET = 'DK0000000000000000000001'
KIT_PRODUCT = 'DK0000000000000000000002'
FRAMEWORK_PRODUCT = 'BB0000010000000000000100'
HELLO = 'BB0000010000000000000023'
PROJECT = 'DD0000010000000000000001'
PRODUCTS_GROUP = 'GG0000010000000000000004'
TESTS_GROUP_PARENT = 'GG0000010000000000000003'   # Tests

counter = [0]


def new_id():
    counter[0] += 1
    i = 'DP%022X' % counter[0]
    assert i not in s, i
    return i


def section_end(name):
    i = s.find('/* End %s section */' % name)
    assert i != -1, name
    return i


def insert_section(name, text):
    global s
    i = section_end(name)
    s = s[:i] + text + s[i:]


def add_to_list(owner, key, entries, comment=True):
    """`entries` appended to the list `key` of the object `owner` (its
    definition, not a mention of it in another list)."""
    global s
    m = re.search(re.escape(owner) + r'( /\*[^*]*\*/)? = \{', s)
    assert m, owner
    k = s.index('\t' + key + ' = (', m.end())
    close = s.index(');', k)
    line = s.rindex('\n', 0, close) + 1
    s = s[:line] + ''.join('\t\t\t\t%s,\n' % e for e in entries) + s[line:]


# the files that went: every line naming them
for name in GONE:
    s = '\n'.join(line for line in s.split('\n') if '/* %s' % name not in line
                  and 'path = %s;' % name not in line and 'path = "%s";' % name not in line)

# the kit's new files
refs = {}
for name in SOURCES + HEADERS + XIBS:
    refs[name] = new_id()
    kind = {'.m': 'sourcecode.c.objc', '.h': 'sourcecode.c.h', 'xib': 'file.xib'}[name[-2:] if name.endswith(('.m', '.h')) else 'xib']
    insert_section('PBXFileReference',
                   '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };\n'
                   % (refs[name], name, kind, name))
add_to_list(KIT_GROUP, 'children', ['%s /* %s */' % (refs[n], n) for n in SOURCES + HEADERS + XIBS])
built = []
for name in SOURCES:
    b = new_id()
    insert_section('PBXBuildFile', '\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n'
                   % (b, name, refs[name], name))
    built.append('%s /* %s in Sources */' % (b, name))
add_to_list(KIT_SOURCES, 'files', built)
built = []
for name in HEADERS:
    b = new_id()
    insert_section('PBXBuildFile', '\t\t%s /* %s in Headers */ = {isa = PBXBuildFile; fileRef = %s /* %s */; settings = {ATTRIBUTES = (Public, ); }; };\n'
                   % (b, name, refs[name], name))
    built.append('%s /* %s in Headers */' % (b, name))
add_to_list(KIT_HEADERS, 'files', built)
built = []
for name in XIBS:
    b = new_id()
    insert_section('PBXBuildFile', '\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n'
                   % (b, name, refs[name], name))
    built.append('%s /* %s in Resources */' % (b, name))
add_to_list(KIT_RESOURCES, 'files', built)

# the tests' target
T = {k: new_id() for k in ('target', 'product', 'sources', 'frameworks', 'resources', 'configs', 'debug',
                           'release', 'group', 'proxy', 'dependency', 'kitlink', 'fwlink', 'hello',
                           'piechart', 'piechartref')}
test_refs = {name: new_id() for name in TESTS}
for name in TESTS:
    insert_section('PBXFileReference',
                   '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = %s; sourceTree = "<group>"; };\n'
                   % (test_refs[name], name, name))
insert_section('PBXFileReference',
               '\t\t%s /* piechart.xhtml */ = {isa = PBXFileReference; lastKnownFileType = text.xml; name = piechart.xhtml; path = Samples/piechart.xhtml; sourceTree = SOURCE_ROOT; };\n'
               % T['piechartref'])
insert_section('PBXFileReference',
               '\t\t%s /* XFormsDesignKitTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = XFormsDesignKitTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };\n'
               % T['product'])
add_to_list(PRODUCTS_GROUP, 'children', ['%s /* XFormsDesignKitTests.xctest */' % T['product']])
insert_section('PBXGroup',
               '\t\t%s /* XFormsDesignKitTests */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\t\t\t\t%s /* piechart.xhtml */,\n\t\t\t);\n\t\t\tpath = XFormsDesignKitTests;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'
               % (T['group'], ''.join('\t\t\t\t%s /* %s */,\n' % (test_refs[n], n) for n in TESTS), T['piechartref']))
add_to_list(TESTS_GROUP_PARENT, 'children', ['%s /* XFormsDesignKitTests */' % T['group']])

test_built = []
for name in TESTS:
    b = new_id()
    insert_section('PBXBuildFile', '\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n'
                   % (b, name, test_refs[name], name))
    test_built.append('%s /* %s in Sources */' % (b, name))
insert_section('PBXBuildFile',
               '\t\t%s /* XFormsDesignKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = %s /* XFormsDesignKit.framework */; };\n'
               '\t\t%s /* XFormsKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = %s /* XFormsKit.framework */; };\n'
               '\t\t%s /* hello.xhtml in Resources */ = {isa = PBXBuildFile; fileRef = %s /* hello.xhtml */; };\n'
               '\t\t%s /* piechart.xhtml in Resources */ = {isa = PBXBuildFile; fileRef = %s /* piechart.xhtml */; };\n'
               % (T['kitlink'], KIT_PRODUCT, T['fwlink'], FRAMEWORK_PRODUCT, T['hello'], HELLO,
                  T['piechart'], T['piechartref']))
insert_section('PBXSourcesBuildPhase',
               '\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n'
               % (T['sources'], ''.join('\t\t\t\t%s,\n' % b for b in test_built)))
insert_section('PBXFrameworksBuildPhase',
               '\t\t%s /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t%s /* XFormsDesignKit.framework in Frameworks */,\n\t\t\t\t%s /* XFormsKit.framework in Frameworks */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n'
               % (T['frameworks'], T['kitlink'], T['fwlink']))
insert_section('PBXResourcesBuildPhase',
               '\t\t%s /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t%s /* hello.xhtml in Resources */,\n\t\t\t\t%s /* piechart.xhtml in Resources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n'
               % (T['resources'], T['hello'], T['piechart']))
insert_section('PBXContainerItemProxy',
               '\t\t%s /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = %s /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = %s;\n\t\t\tremoteInfo = XFormsDesignKit;\n\t\t};\n'
               % (T['proxy'], PROJECT, KIT_TARGET))
insert_section('PBXTargetDependency',
               '\t\t%s /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = %s /* XFormsDesignKit */;\n\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n\t\t};\n'
               % (T['dependency'], KIT_TARGET, T['proxy']))
insert_section('PBXNativeTarget',
               '\t\t%s /* XFormsDesignKitTests */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "XFormsDesignKitTests" */;\n\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\t%s /* PBXTargetDependency */,\n\t\t\t);\n\t\t\tname = XFormsDesignKitTests;\n\t\t\tproductName = XFormsDesignKitTests;\n\t\t\tproductReference = %s /* XFormsDesignKitTests.xctest */;\n\t\t\tproductType = "com.apple.product-type.bundle.unit-test";\n\t\t};\n'
               % (T['target'], T['configs'], T['sources'], T['frameworks'], T['resources'], T['dependency'],
                  T['product']))
add_to_list(PROJECT, 'targets', ['%s /* XFormsDesignKitTests */' % T['target']])
SETTINGS = '''			buildSettings = {
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = YES;
				HEADER_SEARCH_PATHS = (
					"$(SRCROOT)/Sources",
					"$(SRCROOT)/Sources/XFormsKit",
					"$(SRCROOT)/Sources/XFormsDesignKit",
				);
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@loader_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 12.0;
				PRODUCT_BUNDLE_IDENTIFIER = org.xformskit.XFormsDesignKitTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
			};
'''
for key, name in (('debug', 'Debug'), ('release', 'Release')):
    insert_section('XCBuildConfiguration', '\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n%s\t\t\tname = %s;\n\t\t};\n'
                   % (T[key], name, SETTINGS, name))
insert_section('XCConfigurationList',
               '\t\t%s /* Build configuration list for PBXNativeTarget "XFormsDesignKitTests" */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n'
               % (T['configs'], T['debug'], T['release']))
open(path, 'w').write(s)
print('target', T['target'])
