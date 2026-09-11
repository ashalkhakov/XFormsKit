#!/usr/bin/env python3
"""Register the XFDWindowController split in the XFormsDesigner target of
XFormsKit.xcodeproj/project.pbxproj: the +Outline/+Inspector/+Preview
categories, XFDInspectorSpecs, XFDPalettePanel, XFDInstanceXMLEditor,
XFDEventsPane, XFDActionRowsPane (each .m compiled, each .h referenced)
plus the XFDWindowControllerPriv.h header. Ids 50..57 (.m build files and
refs), 63..68 (.h refs) in the AA000002/BB000002 designer range.
Anchor-driven on the XFDDesignOverlay (0E/1E) entries so it works on both
the cloud pbxproj and the Xcode-reformatted Mac one (run
tools/adddesignoverlay.py first if 0E is missing). Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFDEventsPane' in s:
    print('already registered'); sys.exit(0)
assert 'XFDDesignOverlay' in s, 'run tools/adddesignoverlay.py first'

# (name, .m id suffix, .h id suffix or None)
FILES = [
    ('XFDWindowController+Outline',   '50', None),
    ('XFDWindowController+Inspector', '51', None),
    ('XFDWindowController+Preview',   '52', None),
    ('XFDInspectorSpecs',             '53', '63'),
    ('XFDPalettePanel',               '54', '64'),
    ('XFDInstanceXMLEditor',          '55', '65'),
    ('XFDEventsPane',                 '56', '66'),
    ('XFDActionRowsPane',             '57', '67'),
]
PRIV_H = ('XFDWindowControllerPriv', '68')

def bid(sfx):
    return 'AA00000200000000000000' + sfx

def fid(sfx):
    return 'BB00000200000000000000' + sfx

for _, m, h in FILES + [(None, PRIV_H[1], None)]:
    for i in (bid(m), fid(m)) + ((fid(h),) if h else ()):
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

# 1. PBXBuildFile entries, after XFDDesignOverlay's
anchor = 'AA000002000000000000000E /* XFDDesignOverlay.m in Sources */ = {isa'
for name, m, _ in reversed(FILES):
    s = insert_after_line(s, anchor,
        bid(m) + ' /* ' + name + '.m in Sources */ = {isa = PBXBuildFile; fileRef = '
        + fid(m) + ' /* ' + name + '.m */; };')

# 2. PBXFileReference entries, after XFDDesignOverlay.h's
anchor = 'BB000002000000000000001E /* XFDDesignOverlay.h */ = {isa'
refs = []
for name, m, h in FILES:
    refs.append((fid(m), name + '.m', 'sourcecode.c.objc'))
    if h:
        refs.append((fid(h), name + '.h', 'sourcecode.c.h'))
refs.append((fid(PRIV_H[1]), PRIV_H[0] + '.h', 'sourcecode.c.h'))
for ident, fname, ftype in reversed(refs):
    s = insert_after_line(s, anchor,
        ident + ' /* ' + fname + ' */ = {isa = PBXFileReference; lastKnownFileType = '
        + ftype + '; path = ' + ('"' + fname + '"' if '+' in fname else fname)
        + '; sourceTree = "<group>"; };')

# 3. group children, after XFDDesignOverlay.m's row
anchor = 'BB000002000000000000000E /* XFDDesignOverlay.m */,'
for ident, fname, _ in reversed(refs):
    s = insert_after_line(s, anchor, ident + ' /* ' + fname + ' */,')

# 4. Sources build phase, after XFDDesignOverlay.m's row
anchor = 'AA000002000000000000000E /* XFDDesignOverlay.m in Sources */,'
for name, m, _ in reversed(FILES):
    s = insert_after_line(s, anchor, bid(m) + ' /* ' + name + '.m in Sources */,')

open(path, 'w').write(s)
print('registered the XFDWindowController split (50..57 / 63..68) in', path)
