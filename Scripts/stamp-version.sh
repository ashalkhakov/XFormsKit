#!/bin/bash
# Write a version into everything an About panel reads, so a packaged build
# says which build it is.
#
#   ./Scripts/stamp-version.sh 1.2.3
#
# No number in the repository is maintained by hand: the version comes from the
# tag, or from the run number for an unreleased build -- the same value the
# AppImage and the macOS archives are named after. What is in the tree is
# 0.0.0-dev, which is what a build from a working copy is.
#
# Three files, one per app plus the project:
#   * Apps/<App>/<App>-Info.plist is the bundle's plist on BOTH platforms. The
#     Xcode targets set GENERATE_INFOPLIST_FILE = NO and point INFOPLIST_FILE
#     here; gnustep-make finds the same file by name and merges it into the
#     Info-gnustep.plist it generates inside the bundle, which is why there is
#     no such file in the tree to stamp. Four keys: CFBundleShortVersionString
#     and CFBundleVersion are Apple's, ApplicationRelease and FullVersionID are
#     what GSInfoPanel shows.
#   * project.pbxproj MARKETING_VERSION / CURRENT_PROJECT_VERSION -- the
#     framework target builds with GENERATE_INFOPLIST_FILE, so for it these are
#     what land in the bundle.
#
# Two forms of the version go in, because Apple parses some of these keys and
# GNUstep does not:
#
#   display -- the version as given, less any leading "v". The GNUstep About
#     panel shows this, and it can say anything: "0.0.0-229-18df32a" identifies
#     a build in a way a release number cannot.
#   numeric -- the leading dotted number of that, and nothing else. Xcode
#     compiles CURRENT_PROJECT_VERSION into a generated <Target>_vers.c as a
#     double, so a tag like v0.1.0 would arrive there as (double)v0.1.0 and the
#     framework would fail to build. CFBundleShortVersionString and
#     CFBundleVersion are Apple's as well, and are documented as
#     period-separated integers.
set -euo pipefail

version=${1:-}
if [ -z "$version" ]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

display=${version#v}
numeric=$(printf '%s' "$display" | sed -n 's/^\([0-9][0-9.]*\).*/\1/p' | sed 's/\.$//')
if [ -z "$numeric" ]; then
    echo "$0: '$version' has no leading number; using 0.0.0 where Apple needs one" >&2
    numeric=0.0.0
fi

root=$(cd "$(dirname "$0")/.." && pwd)

# PlistBuddy is not on Linux and neither is xcodebuild: every file is edited the
# one way that works on either host.
python3 - "$root" "$display" "$numeric" <<'PY'
import re, sys
root, display, numeric = sys.argv[1:4]

for app in ("XFormsViewer", "XFormsDesigner"):
    path = "%s/Apps/%s/%s-Info.plist" % (root, app, app)
    text = open(path).read()
    # Apple's keys take the numeric form, GNUstep's the display one.
    for key, value in (("CFBundleShortVersionString", numeric),
                       ("CFBundleVersion", numeric),
                       ("ApplicationRelease", display),
                       ("FullVersionID", display)):
        text, n = re.subn(r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % key,
                          lambda m: m.group(1) + value + m.group(2), text)
        if n != 1:
            raise SystemExit("%s: expected one %s, found %d" % (path, key, n))
    open(path, "w").write(text)

path = "%s/XFormsKit.xcodeproj/project.pbxproj" % root
text = open(path).read()
for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
    text, n = re.subn(r"(\b%s = )[^;]*(;)" % key,
                      lambda m: m.group(1) + numeric + m.group(2), text)
    if n == 0:
        raise SystemExit("%s: no %s to stamp" % (path, key))
open(path, "w").write(text)
PY

echo "stamped $display, and $numeric where Apple parses it"
for app in XFormsViewer XFormsDesigner; do
    grep -h -A1 -E "CFBundleShortVersionString|CFBundleVersion|ApplicationRelease|FullVersionID" \
         "$root/Apps/$app/$app-Info.plist" | grep "<string>"
done
grep -m 1 -n "MARKETING_VERSION" "$root/XFormsKit.xcodeproj/project.pbxproj"
