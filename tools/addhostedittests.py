#!/usr/bin/env python3
"""XFHostEditTests.m, the model layer's tests out of XFUIControlTests.m, in
XFormsKitTests' sources in XFormsKit.xcodeproj/project.pbxproj (ids DT...).
It uses no AppKit, so the iOS run keeps it too. Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
NAME = 'XFHostEditTests.m'
if '/* %s */' % NAME in s:
    print('already done'); sys.exit(0)
TESTS_GROUP = 'GG0000010000000000000006'
TESTS_SOURCES = 'SS0000010000000000000002'


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


ref, built = 'DT%022X' % 1, 'DT%022X' % 2
assert ref not in s and built not in s
insert_section('PBXFileReference', '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = %s; sourceTree = "<group>"; };\n'
               % (ref, NAME, NAME))
insert_section('PBXBuildFile', '\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n'
               % (built, NAME, ref, NAME))
add_to_list(TESTS_GROUP, 'children', ['%s /* %s */' % (ref, NAME)])
add_to_list(TESTS_SOURCES, 'files', ['%s /* %s in Sources */' % (built, NAME)])
open(path, 'w').write(s)
print('added', NAME)
