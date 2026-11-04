#!/usr/bin/env python3
"""UDCode's XForms extension in XFormsKit.xcodeproj/project.pbxproj (ids
XU...):

  - an UDCodeExtension group with the extension's files;
  - an XForms target, a bundle (XForms.bundle): the extension's sources and
    XIBs, linking XFormsKit and XFormsDesignKit, which it embeds in its
    Contents/Frameworks, and UDCode's SDK (.deps/UDCodeKit.xcframework,
    UDPieceTable, LSPKit), which the running UDCode has;
  - an XFUTests target (UDCodeExtension/Tests), its tests, which compile the
    extension's sources in.

The XForms scheme (xcshareddata) builds the one and runs the other.
Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XForms.bundle' in s:
    print('already done'); sys.exit(0)

PROJECT = 'DD0000010000000000000001'
MAIN_GROUP = 'GG0000010000000000000001'
PRODUCTS_GROUP = 'GG0000010000000000000004'
KIT_TARGET, KIT_PRODUCT = 'EE0000010000000000000001', 'BB0000010000000000000100'
DESIGNKIT_TARGET, DESIGNKIT_PRODUCT = 'DK0000000000000000000001', 'DK0000000000000000000002'

SOURCES = ['XFUExtension.m', 'XFUEditorViewController.m', 'XFUTextDiff.m']
HEADERS = ['XFUExtension.h', 'XFUEditorViewController.h', 'XFUTextDiff.h']
XIBS = ['XFUEditor.xib', 'XFUEditorMenus.xib']
SDK = ['UDCodeKit', 'UDPieceTable', 'LSPKit']

counter = [0]


def new_id():
    counter[0] += 1
    i = 'XU%022X' % counter[0]
    assert i not in s, i
    return i


def insert_section(name, text):
    global s
    marker = '/* End %s section */' % name
    i = s.find(marker)
    if i == -1:
        # a section the project has not got yet: before the next one Xcode writes
        order = ['PBXBuildFile', 'PBXContainerItemProxy', 'PBXCopyFilesBuildPhase', 'PBXFileReference',
                 'PBXFrameworksBuildPhase', 'PBXGroup', 'PBXNativeTarget']
        later = order[order.index(name) + 1:]
        j = min(s.find('/* Begin %s section */' % n) for n in later if s.find('/* Begin %s section */' % n) != -1)
        s = s[:j] + '/* Begin %s section */\n/* End %s section */\n\n' % (name, name) + s[j:]
        i = s.find(marker)
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


def file_ref(name, kind, path=None, tree='"<group>"'):
    i = new_id()
    extra = ' name = %s;' % name if path else ''
    insert_section('PBXFileReference', '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s;%s path = %s; sourceTree = %s; };\n'
                   % (i, name, kind, extra, path or name, tree))
    return i


def build_file(ref, name, phase, settings=''):
    i = new_id()
    insert_section('PBXBuildFile', '\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */;%s };\n'
                   % (i, name, phase, ref, name, settings))
    return '%s /* %s in %s */' % (i, name, phase)


def phase(kind, name, files, extra=''):
    i = new_id()
    insert_section(kind, '\t\t%s /* %s */ = {\n\t\t\tisa = %s;\n\t\t\tbuildActionMask = 2147483647;\n%s\t\t\tfiles = (\n%s\t\t\t);\n%s\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n'
                   % (i, name, kind, extra if kind == 'PBXCopyFilesBuildPhase' else '',
                      ''.join('\t\t\t\t%s,\n' % f for f in files),
                      '\t\t\tname = "Embed Frameworks";\n' if kind == 'PBXCopyFilesBuildPhase' else ''))
    return '%s /* %s */' % (i, name)


def dependency(target, name):
    proxy, dep = new_id(), new_id()
    insert_section('PBXContainerItemProxy', '\t\t%s /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = %s /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = %s;\n\t\t\tremoteInfo = %s;\n\t\t};\n'
                   % (proxy, PROJECT, target, name))
    insert_section('PBXTargetDependency', '\t\t%s /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = %s /* %s */;\n\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n\t\t};\n'
                   % (dep, target, name, proxy))
    return '%s /* PBXTargetDependency */' % dep


def configs(target_name, settings):
    debug, release, lst = new_id(), new_id(), new_id()
    for i, name in ((debug, 'Debug'), (release, 'Release')):
        insert_section('XCBuildConfiguration', '\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\t\t\t};\n\t\t\tname = %s;\n\t\t};\n'
                       % (i, name, ''.join('\t\t\t\t%s = %s;\n' % kv for kv in settings), name))
    insert_section('XCConfigurationList', '\t\t%s /* Build configuration list for PBXNativeTarget "%s" */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n'
                   % (lst, target_name, debug, release))
    return lst, target_name


def target(i, name, list_id, phases, deps, product, kind):
    insert_section('PBXNativeTarget', '\t\t%s /* %s */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;\n\t\t\tbuildPhases = (\n%s\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n%s\t\t\t);\n\t\t\tname = %s;\n\t\t\tproductName = %s;\n\t\t\tproductReference = %s;\n\t\t\tproductType = "%s";\n\t\t};\n'
                   % (i, name, list_id, name, ''.join('\t\t\t\t%s,\n' % p for p in phases),
                      ''.join('\t\t\t\t%s,\n' % d for d in deps), name, name, product, kind))
    add_to_list(PROJECT, 'targets', ['%s /* %s */' % (i, name)])


# the files
refs = {}
for name in SOURCES + HEADERS + XIBS:
    kind = {'m': 'sourcecode.c.objc', 'h': 'sourcecode.c.h', 'b': 'file.xib'}[name[-1]]
    refs[name] = file_ref(name, kind)
info = file_ref('Info.plist', 'text.plist.xml', 'Resources/Info.plist')
language = file_ref('LanguageInfo.plist', 'text.plist.xml', 'Resources/LanguageInfo.plist')
package = file_ref('package.json', 'text.json')
tests = file_ref('XFUTests.m', 'sourcecode.c.objc', 'Tests/XFUTests.m')
sdk = {name: file_ref('%s.xcframework' % name, 'wrapper.xcframework', '.deps/%s.xcframework' % name, 'SOURCE_ROOT')
       for name in SDK}
group = new_id()
children = [refs[n] + ' /* %s */' % n for n in SOURCES + HEADERS + XIBS] + [
    info + ' /* Info.plist */', language + ' /* LanguageInfo.plist */', package + ' /* package.json */',
    tests + ' /* XFUTests.m */'] + ['%s /* %s.xcframework */' % (sdk[n], n) for n in SDK]
insert_section('PBXGroup', '\t\t%s /* UDCodeExtension */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\t\t\t);\n\t\t\tpath = UDCodeExtension;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'
               % (group, ''.join('\t\t\t\t%s,\n' % c for c in children)))
add_to_list(MAIN_GROUP, 'children', ['%s /* UDCodeExtension */' % group], comment=False)

# the bundle
bundle_product = new_id()
insert_section('PBXFileReference', '\t\t%s /* XForms.bundle */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = XForms.bundle; sourceTree = BUILT_PRODUCTS_DIR; };\n'
               % bundle_product)
tests_product = new_id()
insert_section('PBXFileReference', '\t\t%s /* XFUTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = XFUTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };\n'
               % tests_product)
add_to_list(PRODUCTS_GROUP, 'children', ['%s /* XForms.bundle */' % bundle_product, '%s /* XFUTests.xctest */' % tests_product])

bundle_sources = phase('PBXSourcesBuildPhase', 'Sources', [build_file(refs[n], n, 'Sources') for n in SOURCES])
bundle_resources = phase('PBXResourcesBuildPhase', 'Resources',
                         [build_file(refs[n], n, 'Resources') for n in XIBS]
                         + [build_file(language, 'LanguageInfo.plist', 'Resources')])
bundle_frameworks = phase('PBXFrameworksBuildPhase', 'Frameworks',
                          [build_file(KIT_PRODUCT, 'XFormsKit.framework', 'Frameworks'),
                           build_file(DESIGNKIT_PRODUCT, 'XFormsDesignKit.framework', 'Frameworks')]
                          + [build_file(sdk[n], '%s.xcframework' % n, 'Frameworks') for n in SDK])
embed_settings = ' settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); };'
bundle_embed = phase('PBXCopyFilesBuildPhase', 'Embed Frameworks',
                     [build_file(KIT_PRODUCT, 'XFormsKit.framework', 'Embed Frameworks', embed_settings),
                      build_file(DESIGNKIT_PRODUCT, 'XFormsDesignKit.framework', 'Embed Frameworks', embed_settings)],
                     '\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 10;\n')
search = '("$(SRCROOT)/UDCodeExtension", "$(SRCROOT)/Sources", "$(SRCROOT)/Sources/XFormsKit", "$(SRCROOT)/Sources/XFormsDesignKit", "$(SRCROOT)/Sources/XFormsDesignKit/ThirdParty/DMTabBar")'
bundle_list, _ = configs('XForms', [
    ('CURRENT_PROJECT_VERSION', '0.0.0'), ('GENERATE_INFOPLIST_FILE', 'NO'), ('HEADER_SEARCH_PATHS', search),
    ('INFOPLIST_FILE', 'UDCodeExtension/Resources/Info.plist'),
    ('LD_RUNPATH_SEARCH_PATHS', '("$(inherited)", "@loader_path/../Frameworks")'),
    ('MARKETING_VERSION', '0.0.0'), ('MACOSX_DEPLOYMENT_TARGET', '12.0'),
    ('PRODUCT_BUNDLE_IDENTIFIER', 'org.xformskit.udcode.xforms'), ('PRODUCT_NAME', '"$(TARGET_NAME)"'),
    ('SDKROOT', 'macosx'), ('SKIP_INSTALL', 'YES'), ('WRAPPER_EXTENSION', 'bundle')])
bundle_target = new_id()
target(bundle_target, 'XForms', bundle_list, [bundle_sources, bundle_resources, bundle_frameworks, bundle_embed],
       [dependency(KIT_TARGET, 'XFormsKit'), dependency(DESIGNKIT_TARGET, 'XFormsDesignKit')],
       '%s /* XForms.bundle */' % bundle_product, 'com.apple.product-type.bundle')

# its tests
tests_sources = phase('PBXSourcesBuildPhase', 'Sources',
                      [build_file(tests, 'XFUTests.m', 'Sources')] + [build_file(refs[n], n, 'Sources') for n in SOURCES])
tests_resources = phase('PBXResourcesBuildPhase', 'Resources', [build_file(refs[n], n, 'Resources') for n in XIBS])
tests_frameworks = phase('PBXFrameworksBuildPhase', 'Frameworks',
                         [build_file(KIT_PRODUCT, 'XFormsKit.framework', 'Frameworks'),
                          build_file(DESIGNKIT_PRODUCT, 'XFormsDesignKit.framework', 'Frameworks')]
                         + [build_file(sdk[n], '%s.xcframework' % n, 'Frameworks') for n in SDK])
tests_list, _ = configs('XFUTests', [
    ('GENERATE_INFOPLIST_FILE', 'YES'), ('HEADER_SEARCH_PATHS', search),
    ('LD_RUNPATH_SEARCH_PATHS', '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks")'),
    ('MACOSX_DEPLOYMENT_TARGET', '12.0'), ('PRODUCT_BUNDLE_IDENTIFIER', 'org.xformskit.udcode.xforms.tests'),
    ('PRODUCT_NAME', '"$(TARGET_NAME)"'), ('SDKROOT', 'macosx')])
tests_target = new_id()
target(tests_target, 'XFUTests', tests_list, [tests_sources, tests_resources, tests_frameworks],
       [dependency(KIT_TARGET, 'XFormsKit'), dependency(DESIGNKIT_TARGET, 'XFormsDesignKit')],
       '%s /* XFUTests.xctest */' % tests_product, 'com.apple.product-type.bundle.unit-test')
open(path, 'w').write(s)
print('XForms', bundle_target, 'XFUTests', tests_target)
