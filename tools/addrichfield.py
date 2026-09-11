#!/usr/bin/env python3
"""Register Apps/XFormsDesigner/XFDRichTextField.{h,m} in the
XFormsDesigner target of XFormsKit.xcodeproj/project.pbxproj (ids 0C/1C).
Anchor-driven on the XFDXPathField (0B/1B) entries so it works on both the
cloud pbxproj and the Xcode-reformatted Mac one. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFDRichTextField' in s:
    print('already registered'); sys.exit(0)

BM = 'AA000002000000000000000C'
FM = 'BB000002000000000000000C'
FH = 'BB000002000000000000001C'
for i in (BM, FM, FH):
    assert i not in s, i

def insert_after_line(s, anchor_sub, new_line_body):
    idx = s.find(anchor_sub)
    assert idx != -1, anchor_sub
    assert s.find(anchor_sub, idx + 1) == -1, 'anchor not unique: ' + anchor_sub
    start = s.rfind('\n', 0, idx) + 1
    end = s.find('\n', idx) + 1
    line = s[start:end]
    indent = line[:len(line) - len(line.lstrip())]
    return s[:end] + indent + new_line_body + '\n' + s[end:]

# 1. PBXBuildFile
s = insert_after_line(s,
    'AA000002000000000000000B /* XFDXPathField.m in Sources */ = {isa',
    BM + ' /* XFDRichTextField.m in Sources */ = {isa = PBXBuildFile; fileRef = ' + FM + ' /* XFDRichTextField.m */; };')
# 2. PBXFileReference (m then h, after XFDXPathField.h's ref line)
s = insert_after_line(s,
    'BB000002000000000000001B /* XFDXPathField.h */ = {isa',
    FM + ' /* XFDRichTextField.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFDRichTextField.m; sourceTree = "<group>"; };')
s = insert_after_line(s,
    FM + ' /* XFDRichTextField.m */ = {isa',
    FH + ' /* XFDRichTextField.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFDRichTextField.h; sourceTree = "<group>"; };')
# 3. group children
s = insert_after_line(s,
    'BB000002000000000000000B /* XFDXPathField.m */,',
    FH + ' /* XFDRichTextField.h */,')
s = insert_after_line(s,
    FH + ' /* XFDRichTextField.h */,',
    FM + ' /* XFDRichTextField.m */,')
# 4. Sources phase
s = insert_after_line(s,
    'AA000002000000000000000B /* XFDXPathField.m in Sources */,',
    BM + ' /* XFDRichTextField.m in Sources */,')

open(path, 'w').write(s)
print('registered XFDRichTextField (0C/1C) in', path)
