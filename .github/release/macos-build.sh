#!/bin/bash
# XFormsViewer and XFormsDesigner for gnustep-release-actions'
# macos-release.yml: stamped, universal, into $RELEASE_DIR.
set -euo pipefail
for scheme in XFormsKit XFormsViewer XFormsDesigner; do
  xcodebuild -project XFormsKit.xcodeproj -scheme "$scheme" \
    -destination 'generic/platform=macOS' -configuration Release \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" build
done
for app in XFormsViewer XFormsDesigner; do
  ditto "$RUNNER_TEMP/DerivedData/Build/Products/Release/$app.app" "$RELEASE_DIR/$app.app"
done
