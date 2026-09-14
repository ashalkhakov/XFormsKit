# Building XFormsKit

The README has the short version. This is the rest.

## macOS (Xcode)

    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit      -configuration Debug test
    xcodebuild -project XFormsKit.xcodeproj -scheme XFW3CTests     -configuration Debug test
    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsViewer   -configuration Debug build
    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsDesigner -configuration Debug build

Both apps embed `XFormsKit.framework` (they link it through `@rpath`), so a
built `.app` runs from anywhere.

## iOS

The framework target is multiplatform. On an iPhone SDK it leaves out the
AppKit layer and builds the engine, XPath, XFDOM, the SVG renderer and the
UIKit form layer:

    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit \
      -destination 'platform=iOS Simulator,name=iPhone 17' test
    xcodebuild -project XFormsKit.xcodeproj -target XFormsMobile \
      -sdk iphonesimulator -configuration Debug build

The unit suite and the whole W3C suite run in the simulator, not just build.

`XFFormViewController` is not a port of the AppKit layout. That layout is a
fixed-width two-column canvas; on a phone it would scroll sideways from the
first row. The iOS form is a grouped table view built from a portable row
model (`XFFormRows`): stock cells, a switch for a boolean, a picker pushed as
the next screen, hints and alerts as footnote rows, swipe to delete a repeat
item, a prev/next bar above the keyboard. A host `<table>` is a grid that
scrolls sideways inside its own row; prose with controls in it flows as a
line. Design notes: [ios-port-plan.md](ios-port-plan.md).

`Apps/XFormsMobile` lists the bundled samples and opens any other form through
the document picker, Files, or another app's share sheet. XForms is a client
for a form server, and there is none to point it at yet, so opening documents
is the useful thing a host can do today.

## GNUstep (Linux)

Needs gnustep-base, gnustep-gui and a back end, gnustep-make, libs-corebase,
Opal (CoreGraphics/CoreText for the SVG renderer) and
[tools-xctest](https://github.com/gnustep/tools-xctest). Four patches in
[`patches/gnustep/`](../patches/gnustep/) matter;
`.github/scripts/dependencies.sh` builds the whole stack from source with them
applied, which is the most reliable way to get a working prefix.

    . $PREFIX/System/Library/Makefiles/GNUstep.sh
    make              # the framework
    make check        # unit tests
    make w3ccheck     # W3C conformance suite
    make apps         # viewer, designer and the AppImage launcher

What a Linux setup should know: [patches/gnustep/README.md](../patches/gnustep/README.md).

## The DOM

The engine speaks one XML API, `XFXML*` (`Sources/XFormsKit/XFXMLTypes.h`),
and one tree implements it everywhere: **XFDOM**, in `Sources/XFormsKit/DOM/`.
It exists because iOS Foundation has no `NSXMLDocument`. It was a build switch
for a while; once it passed every suite on all three platforms, NSXML was
retired. `XFDOMTests` still compares against the platform's NSXML where there
is one, as a reference. Background: [ios-port-dom-lift.md](ios-port-dom-lift.md).

## Continuous integration

`.github/workflows/ci.yml`, on every push:

- **macOS** — framework, viewer, designer; unit and W3C suites; the framework
  for both iPhone SDKs and the iOS app; both suites in the simulator; unsigned
  zips of both apps.
- **Ubuntu (GNUstep, clang, gnustep-2.0)** — the GNUstep stack from source into
  a cached prefix; both suites under `xvfb`; all three apps; the AppImage,
  packaged and smoke-tested.

Packaging and releases: [packaging.md](packaging.md).
