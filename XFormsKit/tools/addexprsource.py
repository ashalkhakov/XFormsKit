#!/usr/bin/env python3
"""Register Sources/XFormsKit/XPath/XFExprSource.m in the framework target
of XFormsKit.xcodeproj/project.pbxproj (id 0125). Anchor-driven on the
XFBinaryExpr.m (0045) entries so it works on both the cloud pbxproj and
the Xcode-reformatted Mac one. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFExprSource' in s:
    print('already registered'); sys.exit(0)

BM = 'AA0000010000000000000125'
FM = 'BB0000010000000000000125'
for i in (BM, FM):
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
    'AA0000010000000000000045 /* XFBinaryExpr.m in Sources */ = {isa',
    BM + ' /* XFExprSource.m in Sources */ = {isa = PBXBuildFile; fileRef = ' + FM + ' /* XFExprSource.m */; };')
s = insert_after_line(s,
    'BB0000010000000000000045 /* XFBinaryExpr.m */ = {isa',
    FM + ' /* XFExprSource.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFExprSource.m; sourceTree = "<group>"; };')
s = insert_after_line(s,
    'BB0000010000000000000045 /* XFBinaryExpr.m */,',
    FM + ' /* XFExprSource.m */,')
s = insert_after_line(s,
    'AA0000010000000000000045 /* XFBinaryExpr.m in Sources */,',
    BM + ' /* XFExprSource.m in Sources */,')

open(path, 'w').write(s)
print('registered XFExprSource.m (0125) in', path)
