#!/bin/bash
# XFormsViewer and XFormsDesigner for gnustep-release-actions'
# macos-release.yml: first what CI ran, the unit tests and the W3C XForms 1.1
# conformance suite (green since the port, so a gate: a red case is a
# regression or a change the doc should follow), that XFDOMTests still
# compares XFDOM against NSXML, and that the viewer offers every sample; then
# both apps, universal, into $RELEASE_DIR.
set -euo pipefail
xcodebuild -version
xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit \
  -destination 'platform=macOS' -configuration Debug \
  -resultBundlePath "$RUNNER_TEMP/XFormsKitTests.xcresult" test
xcodebuild -project XFormsKit.xcodeproj -scheme XFW3CTests \
  -destination 'platform=macOS' -configuration Debug \
  -resultBundlePath "$RUNNER_TEMP/XFW3CTests.xcresult" test

# XFDOMTests is a differential suite, the one place NSXML is still used: a
# rename that pointed both sides at XFDOM would leave it green, testing nothing.
grep -q "NSXMLDocument" Tests/XFormsKitTests/XFDOMTests.m \
  || { echo "::error::XFDOMTests no longer references NSXML; it is no longer differential"; exit 1; }
# The viewer's Samples menu is a hand-written list, and the GNUstep build
# copies the same files by name: a sample added to Samples/ is in neither
# until someone remembers both.
missing=0
for f in Samples/*.xhtml; do
  name=$(basename "$f")
  grep -q "\"$name\"" Apps/XFormsViewer/main.m \
    || { echo "::error file=Apps/XFormsViewer/main.m::$name is not in the Samples menu"; missing=1; }
  grep -q "Samples/$name" Apps/XFormsViewer/GNUmakefile \
    || { echo "::error file=Apps/XFormsViewer/GNUmakefile::$name is not copied into the GNUstep bundle"; missing=1; }
done
[ "$missing" -eq 0 ] || exit 1

for scheme in XFormsKit XFormsViewer XFormsDesigner; do
  xcodebuild -project XFormsKit.xcodeproj -scheme "$scheme" \
    -destination 'generic/platform=macOS' -configuration Release \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" build
done
for app in XFormsViewer XFormsDesigner; do
  ditto "$RUNNER_TEMP/DerivedData/Build/Products/Release/$app.app" "$RELEASE_DIR/$app.app"
done
