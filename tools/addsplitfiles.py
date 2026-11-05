#!/usr/bin/env python3
"""The XPath and rich text fields split by responsibility, in
XFormsKit.xcodeproj/project.pbxproj (ids DS...): the path knowledge, the
predicate editor, the node picker, the rich fragments and the rich text
panel join XFormsDesignKit's sources, and their private headers its
group. Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
SOURCES = ['XFDXPathPaths.m', 'XFDPredicateEditor.m', 'XFDXPathPicker.m',
           'XFDRichFragment.m', 'XFDRichTextPanel.m']
HEADERS = [name[:-2] + '.h' for name in SOURCES]
if '/* %s */' % SOURCES[0] in s:
    print('already done'); sys.exit(0)
KIT_GROUP = 'DK0000000000000000000009'
KIT_SOURCES = 'DK0000000000000000000003'
counter = [0]


def new_id():
    counter[0] += 1
    i = 'DS%022X' % counter[0]
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


refs, built = [], []
for name in SOURCES:
    ref, b = new_id(), new_id()
    insert_section('PBXFileReference', '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = %s; sourceTree = "<group>"; };\n'
                   % (ref, name, name))
    insert_section('PBXBuildFile', '\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n'
                   % (b, name, ref, name))
    refs.append('%s /* %s */' % (ref, name))
    built.append('%s /* %s in Sources */' % (b, name))
for name in HEADERS:
    ref = new_id()
    insert_section('PBXFileReference', '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = %s; sourceTree = "<group>"; };\n'
                   % (ref, name, name))
    refs.append('%s /* %s */' % (ref, name))
add_to_list(KIT_GROUP, 'children', refs)
add_to_list(KIT_SOURCES, 'files', built)
open(path, 'w').write(s)
print('added', len(SOURCES), 'sources and', len(HEADERS), 'headers')
