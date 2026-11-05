#!/usr/bin/env python3
"""The design kit's modal panels' XIBs (the instance XML editor, the
submission tester, the rich text editor, the predicate editor, the XPath
picker) as XFormsDesignKit's resources in XFormsKit.xcodeproj/project.pbxproj
(ids DQ...). Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
XIBS = ['XFDInstanceXMLEditor.xib', 'XFDSubmissionTester.xib', 'XFDRichTextPanel.xib',
        'XFDPredicateEditor.xib', 'XFDXPathPicker.xib']
if '/* %s */' % XIBS[0] in s:
    print('already done'); sys.exit(0)
KIT_GROUP = 'DK0000000000000000000009'
KIT_RESOURCES = 'DK0000000000000000000005'
counter = [0]


def new_id():
    counter[0] += 1
    i = 'DQ%022X' % counter[0]
    assert i not in s, i
    return i


def insert_section(name, text):
    global s
    i = s.index('/* End %s section */' % name)
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


refs, built = [], []
for name in XIBS:
    ref, b = new_id(), new_id()
    insert_section('PBXFileReference', '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = file.xib; path = %s; sourceTree = "<group>"; };\n'
                   % (ref, name, name))
    insert_section('PBXBuildFile', '\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n'
                   % (b, name, ref, name))
    refs.append('%s /* %s */' % (ref, name))
    built.append('%s /* %s in Resources */' % (b, name))
add_to_list(KIT_GROUP, 'children', refs)
add_to_list(KIT_RESOURCES, 'files', built)
open(path, 'w').write(s)
print('added', len(XIBS))
