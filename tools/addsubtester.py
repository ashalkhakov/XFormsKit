#!/usr/bin/env python3
"""Register Apps/XFormsDesigner/XFDSubmissionTester.{h,m} in the
XFormsDesigner target of XFormsKit.xcodeproj/project.pbxproj (ids 58/69
in the AA000002/BB000002 designer range). Anchor-driven on the
XFDActionRowsPane (57/67) entries from tools/addwcsplit.py — run that
first. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFDSubmissionTester' in s:
    print('already registered'); sys.exit(0)
assert 'XFDActionRowsPane' in s, 'run tools/addwcsplit.py first'

BM = 'AA0000020000000000000058'
FM = 'BB0000020000000000000058'
FH = 'BB0000020000000000000069'
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
    'AA0000020000000000000057 /* XFDActionRowsPane.m in Sources */ = {isa',
    BM + ' /* XFDSubmissionTester.m in Sources */ = {isa = PBXBuildFile; fileRef = '
    + FM + ' /* XFDSubmissionTester.m */; };')
s = insert_after_line(s,
    'BB0000020000000000000067 /* XFDActionRowsPane.h */ = {isa',
    FM + ' /* XFDSubmissionTester.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFDSubmissionTester.m; sourceTree = "<group>"; };')
s = insert_after_line(s,
    FM + ' /* XFDSubmissionTester.m */ = {isa',
    FH + ' /* XFDSubmissionTester.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFDSubmissionTester.h; sourceTree = "<group>"; };')
s = insert_after_line(s,
    'BB0000020000000000000067 /* XFDActionRowsPane.h */,',
    FH + ' /* XFDSubmissionTester.h */,')
s = insert_after_line(s,
    FH + ' /* XFDSubmissionTester.h */,',
    FM + ' /* XFDSubmissionTester.m */,')
s = insert_after_line(s,
    'AA0000020000000000000057 /* XFDActionRowsPane.m in Sources */,',
    BM + ' /* XFDSubmissionTester.m in Sources */,')

open(path, 'w').write(s)
print('registered XFDSubmissionTester (58/69) in', path)
