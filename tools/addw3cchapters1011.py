#!/usr/bin/env python3
"""Register Tests/W3CTests/XFW3CChapter{10,11}Tests.m in the
XFW3CTests Xcode target (ids AA/BB000003…0A-0B / 14-15, anchored on the
ms73 entries from tools/addw3cchapters789.py — run that first). Idempotent;
run on BOTH pbxprojs."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFW3CChapter10Tests' in s:
    print('already registered'); sys.exit(0)
assert 'XFW3CChapter09Tests' in s, 'run tools/addw3cchapters789.py first'

CHAPTERS = [  # (build-file id, file-ref id, filename)
    ('AA000003000000000000000A', 'BB0000030000000000000014', 'XFW3CChapter10Tests.m'),
    ('AA000003000000000000000B', 'BB0000030000000000000015', 'XFW3CChapter11Tests.m'),
]
for bf, fr, name in CHAPTERS:
    assert bf not in s and fr not in s, name

def insert_after_line(s, anchor, new_lines):
    idx = s.find(anchor)
    assert idx != -1, anchor
    assert s.find(anchor, idx + 1) == -1, 'anchor not unique: ' + anchor
    end = s.find('\n', idx) + 1
    return s[:end] + '\n'.join(new_lines) + '\n' + s[end:]

# PBXBuildFile entries after the ch09 build file
s = insert_after_line(s,
    'AA0000030000000000000009 /* XFW3CChapter09Tests.m in Sources */ = {isa',
    ['\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
     % (bf, n, fr, n) for bf, fr, n in CHAPTERS])

# PBXFileReference entries after the ch09 file ref
s = insert_after_line(s,
    'BB0000030000000000000013 /* XFW3CChapter09Tests.m */ = {isa',
    ['\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = %s; sourceTree = "<group>"; };'
     % (fr, n, n) for bf, fr, n in CHAPTERS])

# group children after the ch09 child line
s = insert_after_line(s,
    'BB0000030000000000000013 /* XFW3CChapter09Tests.m */,',
    ['\t\t\t\t%s /* %s */,' % (fr, n) for bf, fr, n in CHAPTERS])

# sources phase after the ch09 sources line
s = insert_after_line(s,
    'AA0000030000000000000009 /* XFW3CChapter09Tests.m in Sources */,',
    ['\t\t\t\t%s /* %s in Sources */,' % (bf, n) for bf, fr, n in CHAPTERS])

open(path, 'w').write(s)
print('registered W3C chapters 10-11 in', path)
