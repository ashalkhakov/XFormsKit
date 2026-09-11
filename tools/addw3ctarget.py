#!/usr/bin/env python3
"""Add the XFW3CTests unit-test-bundle target (the W3C suite as XCTest
assertions, Tests/W3CTests) to XFormsKit.xcodeproj/project.pbxproj —
the Xcode twin of `make w3ccheck`. Mirrors the XFormsKitTests target:
links XFormsKit.framework, depends on the framework target, same header
search paths — plus GCC_PREPROCESSOR_DEFINITIONS baking in
XFW3C_SUITE_ROOT="$(SRCROOT)/TestSuite/XForms1.1/Edition1" so the
harness finds the suite when Xcode runs the bundle from DerivedData.
Ids live in their own 000003 family. Anchor-driven and idempotent; run
on BOTH pbxprojs (cloud and Mac)."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFW3CTests' in s:
    print('already registered'); sys.exit(0)
assert 'XFormsKitTests' in s, 'not an XFormsKit pbxproj'

SOURCES = [  # (build-file id AA…, file-ref id BB…, filename)
    ('AA0000030000000000000001', 'BB0000030000000000000002', 'XFW3CTestCase.m'),
    ('AA0000030000000000000002', 'BB0000030000000000000003', 'XFW3CChapter03Tests.m'),
    ('AA0000030000000000000003', 'BB0000030000000000000004', 'XFW3CChapter04Tests.m'),
    ('AA0000030000000000000004', 'BB0000030000000000000005', 'XFW3CChapter05Tests.m'),
    ('AA0000030000000000000005', 'BB0000030000000000000006', 'XFW3CChapter06Tests.m'),
]
HDR = 'BB0000030000000000000001'      # XFW3CTestCase.h
FRAMEWORK_BF = 'AA0000030000000000000006'  # XFormsKit.framework in Frameworks
PRODUCT = 'BB0000030000000000000010'  # XFW3CTests.xctest
GROUP = 'GG0000030000000000000001'
TARGET = 'EE0000030000000000000001'
SRCPHASE = 'SS0000030000000000000001'
FRAMEPHASE = 'FF0000030000000000000001'
DEP = 'DP0000030000000000000001'
PROXY = 'CC0000030000000000000001'
CONFLIST = 'LL0000030000000000000001'
DEBUGCFG = 'XC0000030000000000000001'
RELEASECFG = 'XC0000030000000000000002'

for i in [HDR, FRAMEWORK_BF, PRODUCT, GROUP, TARGET, SRCPHASE, FRAMEPHASE,
          DEP, PROXY, CONFLIST, DEBUGCFG, RELEASECFG] + [a for a, b, n in SOURCES]:
    assert i not in s, i

def insert_before(s, marker, block):
    idx = s.find(marker)
    assert idx != -1, marker
    assert s.find(marker, idx + 1) == -1, 'marker not unique: ' + marker
    start = s.rfind('\n', 0, idx) + 1
    return s[:start] + block + s[start:]

def insert_after_line(s, anchor, new_line):
    idx = s.find(anchor)
    assert idx != -1, anchor
    assert s.find(anchor, idx + 1) == -1, 'anchor not unique: ' + anchor
    end = s.find('\n', idx) + 1
    return s[:end] + new_line + '\n' + s[end:]

# 1. PBXBuildFile entries (after the tests target's framework build file)
lines = []
for bf, fr, name in SOURCES:
    lines.append('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
                 % (bf, name, fr, name))
lines.append('\t\t%s /* XFormsKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = BB0000010000000000000100; };'
             % FRAMEWORK_BF)
s = insert_after_line(s,
    'AA0000010000000000000024 /* XFormsKit.framework in Frameworks */ = {isa',
    '\n'.join(lines))

# 2. PBXFileReference entries
refs = ['\t\t%s /* XFW3CTestCase.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFW3CTestCase.h; sourceTree = "<group>"; };' % HDR]
for bf, fr, name in SOURCES:
    refs.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = %s; sourceTree = "<group>"; };'
                % (fr, name, name))
refs.append('\t\t%s /* XFW3CTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = XFW3CTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };'
            % PRODUCT)
s = insert_before(s, '/* End PBXFileReference section */', '\n'.join(refs) + '\n')

# 3. PBXContainerItemProxy (dependency on the framework target)
s = insert_before(s, '/* End PBXContainerItemProxy section */',
    '\t\t%s /* PBXContainerItemProxy */ = {\n'
    '\t\t\tisa = PBXContainerItemProxy;\n'
    '\t\t\tcontainerPortal = DD0000010000000000000001 /* Project object */;\n'
    '\t\t\tproxyType = 1;\n'
    '\t\t\tremoteGlobalIDString = EE0000010000000000000001;\n'
    '\t\t\tremoteInfo = XFormsKit;\n'
    '\t\t};\n' % PROXY)

# 4. Frameworks build phase
s = insert_before(s, '/* End PBXFrameworksBuildPhase section */',
    '\t\t%s /* Frameworks */ = {\n'
    '\t\t\tisa = PBXFrameworksBuildPhase;\n'
    '\t\t\tbuildActionMask = 2147483647;\n'
    '\t\t\tfiles = (\n'
    '\t\t\t\t%s /* XFormsKit.framework in Frameworks */,\n'
    '\t\t\t);\n'
    '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
    '\t\t};\n' % (FRAMEPHASE, FRAMEWORK_BF))

# 5. The W3CTests group + hook it under Tests + product under Products
children = ['\t\t\t\t%s /* XFW3CTestCase.h */,' % HDR]
for bf, fr, name in SOURCES:
    children.append('\t\t\t\t%s /* %s */,' % (fr, name))
s = insert_before(s, '/* End PBXGroup section */',
    '\t\t%s /* W3CTests */ = {\n'
    '\t\t\tisa = PBXGroup;\n'
    '\t\t\tchildren = (\n'
    '%s\n'
    '\t\t\t);\n'
    '\t\t\tpath = W3CTests;\n'
    '\t\t\tsourceTree = "<group>";\n'
    '\t\t};\n' % (GROUP, '\n'.join(children)))
s = insert_after_line(s, 'GG0000010000000000000007 /* Fixtures */,',
    '\t\t\t\t%s /* W3CTests */,' % GROUP)
s = insert_after_line(s, 'BB0000010000000000000101 /* XFormsKitTests.xctest */,',
    '\t\t\t\t%s /* XFW3CTests.xctest */,' % PRODUCT)

# 6. The native target
s = insert_before(s, '/* End PBXNativeTarget section */',
    '\t\t%s /* XFW3CTests */ = {\n'
    '\t\t\tisa = PBXNativeTarget;\n'
    '\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "XFW3CTests" */;\n'
    '\t\t\tbuildPhases = (\n'
    '\t\t\t\t%s /* Sources */,\n'
    '\t\t\t\t%s /* Frameworks */,\n'
    '\t\t\t);\n'
    '\t\t\tbuildRules = (\n'
    '\t\t\t);\n'
    '\t\t\tdependencies = (\n'
    '\t\t\t\t%s /* PBXTargetDependency */,\n'
    '\t\t\t);\n'
    '\t\t\tname = XFW3CTests;\n'
    '\t\t\tproductName = XFW3CTests;\n'
    '\t\t\tproductReference = %s /* XFW3CTests.xctest */;\n'
    '\t\t\tproductType = "com.apple.product-type.bundle.unit-test";\n'
    '\t\t};\n' % (TARGET, CONFLIST, SRCPHASE, FRAMEPHASE, DEP, PRODUCT))
s = insert_after_line(s, 'EE0000020000000000000001 /* XFormsDesigner */,',
    '\t\t\t\t%s /* XFW3CTests */,' % TARGET)

# 7. Sources build phase
files = ['\t\t\t\t%s /* %s in Sources */,' % (bf, name) for bf, fr, name in SOURCES]
s = insert_before(s, '/* End PBXSourcesBuildPhase section */',
    '\t\t%s /* Sources */ = {\n'
    '\t\t\tisa = PBXSourcesBuildPhase;\n'
    '\t\t\tbuildActionMask = 2147483647;\n'
    '\t\t\tfiles = (\n'
    '%s\n'
    '\t\t\t);\n'
    '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
    '\t\t};\n' % (SRCPHASE, '\n'.join(files)))

# 8. Target dependency
s = insert_before(s, '/* End PBXTargetDependency section */',
    '\t\t%s /* PBXTargetDependency */ = {\n'
    '\t\t\tisa = PBXTargetDependency;\n'
    '\t\t\ttarget = EE0000010000000000000001 /* XFormsKit */;\n'
    '\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n'
    '\t\t};\n' % (DEP, PROXY))

# 9. Build configurations (mirror XFormsKitTests + the baked suite root)
def config(ident, name):
    return (
        '\t\t%s /* %s */ = {\n'
        '\t\t\tisa = XCBuildConfiguration;\n'
        '\t\t\tbuildSettings = {\n'
        '\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;\n'
        '\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\n'
        '\t\t\t\t\t"$(inherited)",\n'
        '\t\t\t\t\t"XFW3C_SUITE_ROOT=$(SRCROOT)/TestSuite/XForms1.1/Edition1",\n'
        '\t\t\t\t);\n'
        '\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
        '\t\t\t\tHEADER_SEARCH_PATHS = (\n'
        '\t\t\t\t\t"$(SRCROOT)/Sources",\n'
        '\t\t\t\t\t"$(SRCROOT)/Sources/XFormsKit",\n'
        '\t\t\t\t\t"$(SRCROOT)/Sources/XFormsKit/XPath",\n'
        '\t\t\t\t);\n'
        '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n'
        '\t\t\t\t\t"$(inherited)",\n'
        '\t\t\t\t\t"@executable_path/../Frameworks",\n'
        '\t\t\t\t\t"@loader_path/../Frameworks",\n'
        '\t\t\t\t);\n'
        '\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 11.0;\n'
        '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.xformskit.XFW3CTests;\n'
        '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
        '\t\t\t};\n'
        '\t\t\tname = %s;\n'
        '\t\t};\n' % (ident, name, name))
s = insert_before(s, '/* End XCBuildConfiguration section */',
    config(DEBUGCFG, 'Debug') + config(RELEASECFG, 'Release'))

# 10. Configuration list
s = insert_before(s, '/* End XCConfigurationList section */',
    '\t\t%s /* Build configuration list for PBXNativeTarget "XFW3CTests" */ = {\n'
    '\t\t\tisa = XCConfigurationList;\n'
    '\t\t\tbuildConfigurations = (\n'
    '\t\t\t\t%s /* Debug */,\n'
    '\t\t\t\t%s /* Release */,\n'
    '\t\t\t);\n'
    '\t\t\tdefaultConfigurationIsVisible = 0;\n'
    '\t\t\tdefaultConfigurationName = Release;\n'
    '\t\t};\n' % (CONFLIST, DEBUGCFG, RELEASECFG))

open(path, 'w').write(s)
print('registered XFW3CTests target in', path)
