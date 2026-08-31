#!/usr/bin/env python3
"""Register Sources/XFormsKit/XFRichTextEditor.h as a Public framework
header in XFormsKit.xcodeproj/project.pbxproj (id 0124). Anchor-driven on
the XFHostEdit.h (0122) entries so it works on both the cloud pbxproj and
the Xcode-reformatted Mac one. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if '0000000124' in s:
    print('already registered'); sys.exit(0)

def insert_after_line(s, anchor_sub, new_line_body):
    """Insert a line after the unique line containing anchor_sub, copying
    that line's indentation."""
    idx = s.find(anchor_sub)
    assert idx != -1, anchor_sub
    assert s.find(anchor_sub, idx + 1) == -1, 'anchor not unique: ' + anchor_sub
    start = s.rfind('\n', 0, idx) + 1
    end = s.find('\n', idx) + 1
    indent = s[start:idx - len(s[start:idx].lstrip())] if False else s[start:start + (len(s[start:end]) - len(s[start:end].lstrip()))]
    return s[:end] + indent + new_line_body + '\n' + s[end:]

# 1. PBXBuildFile
s = insert_after_line(s,
    'AA0000010000000000000122 /* XFHostEdit.h in Headers */ = {isa',
    'AA0000010000000000000124 /* XFRichTextEditor.h in Headers */ = {isa = PBXBuildFile; fileRef = BB0000010000000000000124 /* XFRichTextEditor.h */; settings = {ATTRIBUTES = (Public, ); }; };')
# 2. PBXFileReference
s = insert_after_line(s,
    'BB0000010000000000000122 /* XFHostEdit.h */ = {isa',
    'BB0000010000000000000124 /* XFRichTextEditor.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFRichTextEditor.h; sourceTree = "<group>"; };')
# 3. group child (the Sources/XFormsKit group listing)
s = insert_after_line(s,
    'BB0000010000000000000122 /* XFHostEdit.h */,',
    'BB0000010000000000000124 /* XFRichTextEditor.h */,')
# 4. Headers build phase
s = insert_after_line(s,
    'AA0000010000000000000122 /* XFHostEdit.h in Headers */,',
    'AA0000010000000000000124 /* XFRichTextEditor.h in Headers */,')

open(path, 'w').write(s)
print('registered XFRichTextEditor.h (0124)')
