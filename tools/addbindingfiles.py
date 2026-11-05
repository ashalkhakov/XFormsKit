#!/usr/bin/env python3
"""The inspectors bound to their editors, in XFormsKit.xcodeproj/project.pbxproj
(ids DU...): the action page (XFDActionPage, a public header, as
XFDAttributesInspector.h includes it) and its row templates
(XFDActionRow.xib), and the fields' bindings (XFDFieldBinding, a header of
the kit's own) join XFormsDesignKit; the editors' and the inspectors' tests
(XFDEditorsTests, XFDInspectorTests) join XFormsDesignKitTests. Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if '/* XFDActionPage.m */' in s:
    print('already done'); sys.exit(0)
KIT_GROUP = 'DK0000000000000000000009'
KIT_SOURCES = 'DK0000000000000000000003'
KIT_RESOURCES = 'DK0000000000000000000005'
KIT_HEADERS = 'PH0000000000000000000001'
TESTS_GROUP = 'DP0000000000000000000045'
TESTS_SOURCES = 'DP000000000000000000003F'
counter = [0]


def new_id():
    counter[0] += 1
    i = 'DU%022X' % counter[0]
    assert i not in s, i
    return i


def insert_section(name, text):
    global s
    i = s.index('/* End %s section */' % name)
    s = s[:i] + text + s[i:]


def add_to_list(owner, key, entries):
    """`entries` appended to the list `key` of the object `owner` (its
    definition, not a mention of it in another list)."""
    global s
    m = re.search(re.escape(owner) + r'( /\*[^*]*\*/)? = \{', s)
    assert m, owner
    k = s.index('\t' + key + ' = (', m.end())
    close = s.index(');', k)
    line = s.rindex('\n', 0, close) + 1
    s = s[:line] + ''.join('\t\t\t\t%s,\n' % e for e in entries) + s[line:]


def file_ref(name, kind):
    ref = new_id()
    insert_section('PBXFileReference', '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };\n'
                   % (ref, name, kind, name))
    return ref


def build_file(ref, name, phase, settings=''):
    b = new_id()
    insert_section('PBXBuildFile', '\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */;%s };\n'
                   % (b, name, phase, ref, name, settings))
    return '%s /* %s in %s */' % (b, name, phase)


refs, sources, headers, resources = [], [], [], []
for name in ['XFDActionPage.m', 'XFDFieldBinding.m']:
    ref = file_ref(name, 'sourcecode.c.objc')
    refs.append('%s /* %s */' % (ref, name))
    sources.append(build_file(ref, name, 'Sources'))
ref = file_ref('XFDActionPage.h', 'sourcecode.c.h')
refs.append('%s /* XFDActionPage.h */' % ref)
headers.append(build_file(ref, 'XFDActionPage.h', 'Headers', ' settings = {ATTRIBUTES = (Public, ); };'))
ref = file_ref('XFDFieldBinding.h', 'sourcecode.c.h')
refs.append('%s /* XFDFieldBinding.h */' % ref)
ref = file_ref('XFDActionRow.xib', 'file.xib')
refs.append('%s /* XFDActionRow.xib */' % ref)
resources.append(build_file(ref, 'XFDActionRow.xib', 'Resources'))
tests, test_refs = [], []
for name in ['XFDEditorsTests.m', 'XFDInspectorTests.m']:
    ref = file_ref(name, 'sourcecode.c.objc')
    test_refs.append('%s /* %s */' % (ref, name))
    tests.append(build_file(ref, name, 'Sources'))
add_to_list(KIT_GROUP, 'children', refs)
add_to_list(TESTS_GROUP, 'children', test_refs)
add_to_list(TESTS_SOURCES, 'files', tests)
add_to_list(KIT_SOURCES, 'files', sources)
add_to_list(KIT_HEADERS, 'files', headers)
add_to_list(KIT_RESOURCES, 'files', resources)
open(path, 'w').write(s)
print('added', len(refs) + len(test_refs), 'files')
