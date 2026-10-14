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
[tools-xctest](https://github.com/gnustep/tools-xctest). A handful of fixes to
GNUstep itself matter, and they live in the shared
[gnustep-patches](https://github.com/ashalkhakov/gnustep-patches) repository,
which publishes the patched stack as releases: an archive for Ubuntu 22.04
that unpacks into `/opt/gnustep`, with every component above.
`.github/pins.env` names the one CI builds on (`GNUSTEP_PATCHES_VERSION`), and
it is the quickest way to a working prefix. To build the same stack on your
own machine, run gnustep-patches' `Scripts/build-gnustep.sh` with
`COMPONENTS="libobjc2 libdispatch tools-make libs-base libs-gui libs-back libs-corebase libs-opal eau tools-xctest"`.

    . $PREFIX/System/Library/Makefiles/GNUstep.sh
    make              # the framework, the designer's editor (XFormsDesignKit),
                      # the viewer, the designer and the AppImage launcher
    make check        # the source checks, the unit tests, the W3C suite
    make install      # all of it but the test bundles
    make w3ccheck     # the W3C conformance suite alone

On macOS and iOS, `Makefile.apple` (Sparkle's XCFramework in `.deps/`,
which gnustep-release-actions' `scripts/deps.sh apple` fetches by the version
`.github/pins.env` names):

    make -f Makefile.apple && make -f Makefile.apple check
    make -f Makefile.apple ios && make -f Makefile.apple ios-check

What a Linux setup should know: [gnustep-patches](https://github.com/ashalkhakov/gnustep-patches).

## The DOM

The engine speaks one XML API, `XFXML*` (`Sources/XFormsKit/XFXMLTypes.h`),
and one tree implements it everywhere: **XFDOM**, in `Sources/XFormsKit/DOM/`.
It exists because iOS Foundation has no `NSXMLDocument`. It was a build switch
for a while; once it passed every suite on all three platforms, NSXML was
retired. `XFDOMTests` still compares against the platform's NSXML where there
is one, as a reference. Background: [ios-port-dom-lift.md](ios-port-dom-lift.md).

## Continuous integration

One workflow, `.github/workflows/build.yml`, on every push and `v*` tag. It
calls gnustep-release-actions' shared workflows, the same as every
repository's, which fetch what `.github/pins.env` names and run the commands
above:

- **macOS** (`Makefile.apple`) — `check`: the source checks
  (`Scripts/check-sources.sh`: every framework import GNUstep lacks is
  guarded, `XFDOMTests` still compares against NSXML, the viewer offers every
  sample), the unit and W3C suites; then the Release universal viewer and
  designer, and `installcheck`: each embeds its frameworks.
- **iOS** (`Makefile.apple`) — `ios`: the framework for both iPhone SDKs,
  checked for its shape (UIKit linked, AppKit never, the listed classes
  present or left out), and XFormsMobile unsigned for device and simulator;
  `ios-check`: both suites in the simulator.
- **Linux** (`GNUmakefile`, `appimage.conf`), on gnustep-patches' released
  stack — `make`, `make check` (the same source checks, both suites under
  `xvfb`), `make install`; the AppImage, packaged and smoke-tested on a clean
  Ubuntu (`Scripts/appimage-smoke.sh`).

Packaging and releases: [packaging.md](packaging.md).
