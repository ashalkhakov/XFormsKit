#!/usr/bin/env python3
"""Register Apps/XFormsDesigner/XFDEventsConsole.{h,m} in the
XFormsDesigner target of XFormsKit.xcodeproj/project.pbxproj (ids 59/6A
in the AA000002/BB000002 designer range). Anchor-driven on the
XFDSubmissionTester (58/69) entries from tools/addsubtester.py — run
that first. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFDEventsConsole' in s:
    print('already registered'); sys.exit(0)
assert 'XFDSubmissionTester' in s, 'run tools/addsubtester.py first'

BM = 'AA0000020000000000000059'
FM = 'BB0000020000000000000059'
FH = 'BB000002000000000000006A'
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
    'AA0000020000000000000058 /* XFDSubmissionTester.m in Sources */ = {isa',
    BM + ' /* XFDEventsConsole.m in Sources */ = {isa = PBXBuildFile; fileRef = '
    + FM + ' /* XFDEventsConsole.m */; };')
s = insert_after_line(s,
    'BB0000020000000000000069 /* XFDSubmissionTester.h */ = {isa',
    FM + ' /* XFDEventsConsole.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFDEventsConsole.m; sourceTree = "<group>"; };')
s = insert_after_line(s,
    FM + ' /* XFDEventsConsole.m */ = {isa',
    FH + ' /* XFDEventsConsole.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFDEventsConsole.h; sourceTree = "<group>"; };')
s = insert_after_line(s,
    'BB0000020000000000000069 /* XFDSubmissionTester.h */,',
    FH + ' /* XFDEventsConsole.h */,')
s = insert_after_line(s,
    FH + ' /* XFDEventsConsole.h */,',
    FM + ' /* XFDEventsConsole.m */,')
s = insert_after_line(s,
    'AA0000020000000000000058 /* XFDSubmissionTester.m in Sources */,',
    BM + ' /* XFDEventsConsole.m in Sources */,')

open(path, 'w').write(s)
print('registered XFDEventsConsole (59/6A) in', path)
