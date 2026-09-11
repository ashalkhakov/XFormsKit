#!/usr/bin/env python3
"""Register Apps/XFormsDesigner/XFDIDRefField.{h,m} in the XFormsDesigner
target of XFormsKit.xcodeproj/project.pbxproj (ids 0D/1D). Anchor-driven
on the XFDRichTextField (0C/1C) entries so it works on both the cloud
pbxproj and the Xcode-reformatted Mac one. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFDIDRefField' in s:
    print('already registered'); sys.exit(0)

BM = 'AA000002000000000000000D'
FM = 'BB000002000000000000000D'
FH = 'BB000002000000000000001D'
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

s = insert_after_line(s,
    'AA000002000000000000000C /* XFDRichTextField.m in Sources */ = {isa',
    BM + ' /* XFDIDRefField.m in Sources */ = {isa = PBXBuildFile; fileRef = ' + FM + ' /* XFDIDRefField.m */; };')
s = insert_after_line(s,
    'BB000002000000000000001C /* XFDRichTextField.h */ = {isa',
    FM + ' /* XFDIDRefField.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFDIDRefField.m; sourceTree = "<group>"; };')
s = insert_after_line(s,
    FM + ' /* XFDIDRefField.m */ = {isa',
    FH + ' /* XFDIDRefField.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFDIDRefField.h; sourceTree = "<group>"; };')
s = insert_after_line(s,
    'BB000002000000000000000C /* XFDRichTextField.m */,',
    FH + ' /* XFDIDRefField.h */,')
s = insert_after_line(s,
    FH + ' /* XFDIDRefField.h */,',
    FM + ' /* XFDIDRefField.m */,')
s = insert_after_line(s,
    'AA000002000000000000000C /* XFDRichTextField.m in Sources */,',
    BM + ' /* XFDIDRefField.m in Sources */,')

open(path, 'w').write(s)
print('registered XFDIDRefField (0D/1D) in', path)
