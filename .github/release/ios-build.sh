#!/bin/bash
# For gnustep-release-actions' ios-release.yml: the framework for both iPhone
# SDKs, checked for its shape (the engine and the UIKit form layer, never
# AppKit's widget layer), and XFormsMobile, the form picker and the UIKit
# form, unsigned, for a device and for the simulator, into $RELEASE_DIR.
set -euo pipefail
xcodebuild -project XFormsKit.xcodeproj -target XFormsKit \
  -sdk iphonesimulator -configuration Debug build
xcodebuild -project XFormsKit.xcodeproj -target XFormsKit \
  -sdk iphoneos -configuration Debug build CODE_SIGNING_ALLOWED=NO

# A framework that builds but quietly drags in the view layer, or links
# something not on iOS, would defeat the point: the shape of what came out.
# CoreGraphics and CoreText are expected (the SVG renderer draws through
# them); UIKit is, for the form layer; AppKit never.
products=$(xcodebuild -project XFormsKit.xcodeproj -target XFormsKit \
             -sdk iphonesimulator -configuration Debug -showBuildSettings 2>/dev/null \
           | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
binary="$products/XFormsKit.framework/XFormsKit"
otool -L "$binary" | tail -n +2
if otool -L "$binary" | grep -q "/AppKit.framework/"; then
  echo "::error::the iOS framework links AppKit"; exit 1
fi
otool -L "$binary" | grep -q "/UIKit.framework/" \
  || { echo "::error::the iOS framework does not link UIKit — the form layer is missing"; exit 1; }
classes=$(nm -arch arm64 -gU "$binary" | sed -n 's/.*_OBJC_CLASS_\$_//p')
for c in XFProcessor XFDOMDocument XFXPath XFSubmission XFSVGDocument XFRichText \
         XFFormRows XFFormViewController; do
  echo "$classes" | grep -qx "$c" || { echo "::error::$c is missing from the iOS framework"; exit 1; }
done
# What EXCLUDED_SOURCE_FILE_NAMES[sdk=iphone*] drops: a rename that quietly
# re-included one would otherwise go unnoticed.
for c in XFFormView XFSVGView XFRichTextEditor XFTableAdapter XFBadgeView; do
  if echo "$classes" | grep -qx "$c"; then
    echo "::error::the AppKit view layer leaked into the iOS framework ($c)"; exit 1
  fi
done
echo "engine, SVG, rich text and the UIKit form layer present; AppKit layer excluded"

for sdk in iphoneos iphonesimulator; do
  xcodebuild -project XFormsKit.xcodeproj -target XFormsMobile -sdk "$sdk" -configuration Release \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
  built=$(xcodebuild -project XFormsKit.xcodeproj -target XFormsMobile -sdk "$sdk" -configuration Release \
            -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
  ditto "$built/XFormsMobile.app" "$RELEASE_DIR/$sdk/XFormsMobile.app"
done
