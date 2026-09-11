#!/usr/bin/env python3
"""Register XFAVT.{h,m}, XFSVG.h and AppKit/XFSVGView.m in the XFormsKit
framework target of XFormsKit.xcodeproj/project.pbxproj (ids 0126–0129).
Anchor-driven on the XFHostEdit (0108/0109? — actual anchors grepped, not
assumed) and XFRichText / AppKit-group lines so it works on both the
cloud pbxproj and the Xcode-reformatted Mac one, whose h/m build-file id
pairs are swapped for some modules. Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
if 'XFAVT' in s or 'XFSVG' in s:
    print('already registered'); sys.exit(0)

AVT_M_B = 'AA000001000000000000' + '0126'  # build file: XFAVT.m
AVT_M_F = 'BB000001000000000000' + '0126'  # file ref:   XFAVT.m
AVT_H_F = 'BB000001000000000000' + '0127'  # file ref:   XFAVT.h (no build file)
SVG_H_F = 'BB000001000000000000' + '0128'  # file ref:   XFSVG.h (no build file)
SVGV_B = 'AA000001000000000000' + '0129'   # build file: XFSVGView.m
SVGV_F = 'BB000001000000000000' + '0129'   # file ref:   XFSVGView.m
for i in (AVT_M_B, AVT_M_F, AVT_H_F, SVG_H_F, SVGV_B, SVGV_F):
    assert i not in s, i


def insert_after_line(text, anchor_sub, new_line_body):
    idx = text.find(anchor_sub)
    assert idx != -1, 'anchor missing: ' + anchor_sub
    assert text.find(anchor_sub, idx + 1) == -1, 'anchor not unique: ' + anchor_sub
    start = text.rfind('\n', 0, idx) + 1
    end = text.find('\n', idx) + 1
    line = text[start:end]
    indent = line[:len(line) - len(line.lstrip())]
    return text[:end] + indent + new_line_body + '\n' + text[end:]


# --- PBXBuildFile entries, after XFHostEdit.m's ---
m = re.search(r'([A-F0-9]{24}) /\* XFHostEdit\.m in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})', s)
assert m, 'XFHostEdit.m build file not found'
s = insert_after_line(s, m.group(1) + ' /* XFHostEdit.m in Sources */ = {isa',
    AVT_M_B + ' /* XFAVT.m in Sources */ = {isa = PBXBuildFile; fileRef = ' + AVT_M_F + ' /* XFAVT.m */; };')
s = insert_after_line(s, AVT_M_B + ' /* XFAVT.m in Sources */ = {isa',
    SVGV_B + ' /* XFSVGView.m in Sources */ = {isa = PBXBuildFile; fileRef = ' + SVGV_F + ' /* XFSVGView.m */; };')

# --- PBXFileReference entries, after XFHostEdit.h's ---
m = re.search(r'([A-F0-9]{24}) /\* XFHostEdit\.h \*/ = \{isa = PBXFileReference', s)
assert m, 'XFHostEdit.h file ref not found'
s = insert_after_line(s, m.group(1) + ' /* XFHostEdit.h */ = {isa',
    AVT_M_F + ' /* XFAVT.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFAVT.m; sourceTree = "<group>"; };')
s = insert_after_line(s, AVT_M_F + ' /* XFAVT.m */ = {isa',
    AVT_H_F + ' /* XFAVT.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFAVT.h; sourceTree = "<group>"; };')
s = insert_after_line(s, AVT_H_F + ' /* XFAVT.h */ = {isa',
    SVG_H_F + ' /* XFSVG.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = XFSVG.h; sourceTree = "<group>"; };')
s = insert_after_line(s, SVG_H_F + ' /* XFSVG.h */ = {isa',
    SVGV_F + ' /* XFSVGView.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = XFSVGView.m; sourceTree = "<group>"; };')

# --- main group children, after XFHostEdit.m's group line ---
s = insert_after_line(s, '/* XFHostEdit.m */,',
    AVT_H_F + ' /* XFAVT.h */,')
s = insert_after_line(s, AVT_H_F + ' /* XFAVT.h */,',
    AVT_M_F + ' /* XFAVT.m */,')
s = insert_after_line(s, AVT_M_F + ' /* XFAVT.m */,',
    SVG_H_F + ' /* XFSVG.h */,')

# --- AppKit group children, after XFRichText.m's group line ---
s = insert_after_line(s, '/* XFRichText.m */,',
    SVGV_F + ' /* XFSVGView.m */,')

# --- Sources build phase, after XFHostEdit.m's ---
s = insert_after_line(s, '/* XFHostEdit.m in Sources */,',
    AVT_M_B + ' /* XFAVT.m in Sources */,')
s = insert_after_line(s, AVT_M_B + ' /* XFAVT.m in Sources */,',
    SVGV_B + ' /* XFSVGView.m in Sources */,')

open(path, 'w').write(s)
print('registered XFAVT (0126/0127), XFSVG.h (0128), XFSVGView.m (0129) in', path)
