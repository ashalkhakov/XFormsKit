#!/usr/bin/env python3
"""The frameworks' public headers inside the frameworks, in
XFormsKit.xcodeproj/project.pbxproj, for what builds on their XCFrameworks
(WorkflowKit's apps, through `make -f Makefile.apple install`):

  - XFormsKit's PUBLIC_HEADERS_FOLDER_PATH (Headers, which put them beside
    the framework in the build products, not in it) goes, for the default;
  - XFormsKit publishes every header its GNUmakefile installs (XFType.h,
    XFAVT.h and XFSVG.h, which XFormsKit.h imports, were not);
  - XFormsDesignKit gets a Headers phase (ids PH...) with the headers its
    GNUmakefile installs (XFormsDesignKit_HEADER_FILES), public; Xcode puts
    them side by side, ThirdParty/'s too, so their quoted imports of each
    other still resolve.

Idempotent."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'XFormsKit.xcodeproj/project.pbxproj'
s = open(path).read()
s = s.replace('\t\t\t\tPUBLIC_HEADERS_FOLDER_PATH = Headers;\n', '')

PHASE = 'PH0000000000000000000001'
TARGET = 'DK0000000000000000000001'
KIT_PHASE = 'HH0000010000000000000001'   # XFormsKit's Headers


def ref(name):
    m = re.findall(r'^\t\t([0-9A-Z]{24}) /\* %s \*/ = \{isa = PBXFileReference' % re.escape(name), s, re.M)
    assert len(m) <= 1, (name, m)
    return m[0] if m else None


def section_end(name):
    i = s.find('/* End %s section */' % name)
    assert i != -1, name
    return i


# XFormsKit: every header its GNUmakefile installs that the project knows
# (not XFCrashReporter.h, GNUstep's alone) and does not yet publish.
make = open('GNUmakefile').read().replace('\\\n', ' ')
kit = re.search(r'^XFormsKit_HEADER_FILES\s*=\s*(.*)$', make, re.M).group(1).split()
added = []
for n, name in enumerate(kit, 1):
    if re.search(r'/\* %s in Headers \*/ = \{isa = PBXBuildFile' % re.escape(name), s) or ref(name) is None:
        continue
    build = 'PK%022X' % (0x100 + n)
    i = section_end('PBXBuildFile')
    s = s[:i] + ('\t\t%s /* %s in Headers */ = {isa = PBXBuildFile; fileRef = %s /* %s */; '
                 'settings = {ATTRIBUTES = (Public, ); }; };\n' % (build, name, ref(name), name)) + s[i:]
    anchor = '\t\t%s /* Headers */ = {\n\t\t\tisa = PBXHeadersBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n' % KIT_PHASE
    assert s.count(anchor) == 1
    s = s.replace(anchor, anchor + '\t\t\t\t%s /* %s in Headers */,\n' % (build, name))
    added.append(name)
if added:
    print('public in XFormsKit:', ' '.join(added))

if PHASE in s:
    open(path, 'w').write(s)
    print('already public'); sys.exit(0)

make = open('Sources/XFormsDesignKit/GNUmakefile').read().replace('\\\n', ' ')
headers = re.search(r'^XFormsDesignKit_HEADER_FILES\s*=\s*(.*)$', make, re.M).group(1).split()


files = []
lines = []
for n, h in enumerate(headers, 1):
    name = h.rsplit('/', 1)[-1]
    build = 'PH%022X' % (0x100 + n)
    assert build not in s, build
    files.append('\t\t\t\t%s /* %s in Headers */,\n' % (build, name))
    lines.append('\t\t%s /* %s in Headers */ = {isa = PBXBuildFile; fileRef = %s /* %s */; '
                 'settings = {ATTRIBUTES = (Public, ); }; };\n' % (build, name, ref(name), name))
i = section_end('PBXBuildFile')
s = s[:i] + ''.join(lines) + s[i:]

phase = ('\t\t%s /* Headers */ = {\n\t\t\tisa = PBXHeadersBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
         '\t\t\tfiles = (\n%s\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n') % (PHASE, ''.join(files))
i = section_end('PBXHeadersBuildPhase')
s = s[:i] + phase + s[i:]

old = '''\t\t%s /* XFormsDesignKit */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = DK0000000000000000000006 /* Build configuration list for PBXNativeTarget "XFormsDesignKit" */;
\t\t\tbuildPhases = (
''' % TARGET
assert s.count(old) == 1
s = s.replace(old, old + '\t\t\t\t%s /* Headers */,\n' % PHASE)
open(path, 'w').write(s)
print('%d headers public in XFormsDesignKit' % len(headers))
