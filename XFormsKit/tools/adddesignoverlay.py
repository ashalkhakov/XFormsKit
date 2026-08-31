#!/usr/bin/env python3
"""Register Apps/XFormsDesigner/XFDDesignOverlay.{h,m} in the
XFormsDesigner target of XFormsKit.xcodeproj/project.pbxproj (ids 0E/1E).
Anchor-driven on the XFDIDRefField (0D/1D) entries so it works on both the
cloud pbxproj and the Xcode-reformatted Mac one. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFDDesignOverlay' in s:
    print('already registered'); sys.exit(0)

BM = 'AA000002000000000000000E'
FM = 'BB000002000000000000000E'
FH = 'BB000002000000000000001E'
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
    'AA000002000000000000000D /* XFDIDRefField.m in Sources */ = {isa',
    BM + ' /* XFDDesignOverlay.m in Sources */ = {isa = PBXBuildFile; fileRef = ' + FM + ' /* XFDDesignOverlay.m */; };')
s = insert_after_line(s,
    'BB000002000000000000001D /* XFDIDRefField.h */ = {isa',
    FM + ' /* XFDDesignOverlay.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFDDesignOverlay.m; sourceTree = "<group>"; };')
s = insert_after_line(s,
    FM + ' /* XFDDesignOverlay.m */ = {isa',
    FH + ' /* XFDDesignOverlay.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFDDesignOverlay.h; sourceTree = "<group>"; };')
s = insert_after_line(s,
    'BB000002000000000000000D /* XFDIDRefField.m */,',
    FH + ' /* XFDDesignOverlay.h */,')
s = insert_after_line(s,
    FH + ' /* XFDDesignOverlay.h */,',
    FM + ' /* XFDDesignOverlay.m */,')
s = insert_after_line(s,
    'AA000002000000000000000D /* XFDIDRefField.m in Sources */,',
    BM + ' /* XFDDesignOverlay.m in Sources */,')

open(path, 'w').write(s)
print('registered XFDDesignOverlay (0E/1E) in', path)
