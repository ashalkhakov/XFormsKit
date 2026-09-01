#!/usr/bin/env python3
"""Register the final W3C suite test files — XFW3CChapter02Tests.m and
XFW3CAppendix{B,G,H}Tests.m — in the XFW3CTests Xcode target (ids
AA/BB000003…0C-0F / 16-19, anchored on the ms74 entries from
tools/addw3cchapters1011.py — run that first). Idempotent; run on BOTH
pbxprojs."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFW3CChapter02Tests' in s:
    print('already registered'); sys.exit(0)
assert 'XFW3CChapter11Tests' in s, 'run tools/addw3cchapters1011.py first'

FILES = [  # (build-file id, file-ref id, filename)
    ('AA000003000000000000000C', 'BB0000030000000000000016', 'XFW3CChapter02Tests.m'),
    ('AA000003000000000000000D', 'BB0000030000000000000017', 'XFW3CAppendixBTests.m'),
    ('AA000003000000000000000E', 'BB0000030000000000000018', 'XFW3CAppendixGTests.m'),
    ('AA000003000000000000000F', 'BB0000030000000000000019', 'XFW3CAppendixHTests.m'),
]
for bf, fr, name in FILES:
    assert bf not in s and fr not in s, name

def insert_after_line(s, anchor, new_lines):
    idx = s.find(anchor)
    assert idx != -1, anchor
    assert s.find(anchor, idx + 1) == -1, 'anchor not unique: ' + anchor
    end = s.find('\n', idx) + 1
    return s[:end] + '\n'.join(new_lines) + '\n' + s[end:]

# PBXBuildFile entries after the ch11 build file
s = insert_after_line(s,
    'AA000003000000000000000B /* XFW3CChapter11Tests.m in Sources */ = {isa',
    ['\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
     % (bf, n, fr, n) for bf, fr, n in FILES])

# PBXFileReference entries after the ch11 file ref
s = insert_after_line(s,
    'BB0000030000000000000015 /* XFW3CChapter11Tests.m */ = {isa',
    ['\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = %s; sourceTree = "<group>"; };'
     % (fr, n, n) for bf, fr, n in FILES])

# group children after the ch11 child line
s = insert_after_line(s,
    'BB0000030000000000000015 /* XFW3CChapter11Tests.m */,',
    ['\t\t\t\t%s /* %s */,' % (fr, n) for bf, fr, n in FILES])

# sources phase after the ch11 sources line
s = insert_after_line(s,
    'AA000003000000000000000B /* XFW3CChapter11Tests.m in Sources */,',
    ['\t\t\t\t%s /* %s in Sources */,' % (bf, n) for bf, fr, n in FILES])

open(path, 'w').write(s)
print('registered W3C chapter 2 + appendices B/G/H in', path)
