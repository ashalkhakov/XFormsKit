#!/bin/bash
# The engine and the whole W3C conformance suite on XFDOM, in a simulator:
# both test bundles are multiplatform, and on an iPhone SDK drop the AppKit
# widget tests and the NSXML differential tests. Whatever iPhone this
# runner's Xcode ships with, by UDID: a model's name changes every autumn.
set -euo pipefail
udid=$(xcrun simctl list devices available \
       | grep -E '^ +iPhone' | head -1 \
       | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$udid" ]; then
  echo "::error::no iOS Simulator device is available on this runner"
  xcrun simctl list devices available
  exit 1
fi
echo "simulator: $udid"
for scheme in XFormsKit XFW3CTests; do
  xcodebuild -project XFormsKit.xcodeproj -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$udid" -configuration Debug \
    -resultBundlePath "$RUNNER_TEMP/$scheme-iOS.xcresult" test
done
