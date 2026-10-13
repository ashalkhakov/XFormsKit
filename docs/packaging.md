# Packaging and releases

## Artifacts

One workflow, `.github/workflows/build.yml`, builds, tests and ships. Every
push and pull request uploads unsigned builds to its Actions run, kept two
weeks, each named for its app and version: zips of XFormsViewer and
XFormsDesigner, the iOS builds of XFormsMobile, and the XFormsKit AppImage.

A `v*` tag also releases them, attached to the tag's GitHub release (a
pre-release when the tag has a `-`): the Mac apps signed and notarized, each
with its Sparkle appcast; XFormsMobile as an unsigned
`XFormsMobile-<version>-unsigned.ipa` and a simulator build,
`XFormsMobile-Simulator-<version>.zip`; the AppImage with its update
information and `.zsync`. A run started by hand builds the branch as
artifacts, or, given a tag, builds that tag and attaches to its release. The
"Run workflow" button only appears once the workflow is on the default
branch; a tag triggers it from anywhere. Signing, notarizing, the appcasts,
the AppImage and its update information are the shared workflows in
`ashalkhakov/gnustep-release-actions`; the GNUstep stack is gnustep-patches'
image; the build and the smoke tests are this repository's hooks in
`.github/release/`.

## Linux: one AppImage

gnustep-release-actions' `appimage` makes it, the same as every app's image:
the framework, the viewer, the designer and the launcher (installed into the
prefix by `.github/release/linux-install.sh`), the GNUstep runtime, and the
shared launcher, `AppRun`, which writes a GNUstep config pointing
`GNUSTEP_SYSTEM_ROOT` and its siblings at wherever the image is mounted, since
that path is not known until it runs. What is XFormsKit's own is
`.github/release/appimage.conf`.

    ./XFormsKit-*.AppImage                   # the launcher: pick an app
    ./XFormsKit-*.AppImage designer
    ./XFormsKit-*.AppImage form.xhtml        # a file opens the viewer
    ln -s XFormsKit-*.AppImage xformsdesigner && ./xformsdesigner

`AppRun` picks the app from the name it was invoked through, then from the
first argument (`ROUTES` in `appimage.conf`), and otherwise opens **XFormsLauncher** — one image, two apps,
so it asks. The launcher is GNUstep-only; a Mac installs the apps separately.

What the image carries besides the apps:

- the **Eau** theme, built into the prefix with the stack (a theme links
  against the gui it is loaded into, so it cannot ship prebuilt) and selected by
  `AppRun` in each app's defaults domain, with Liberation fonts and Ctrl mapped
  as Command;
- DejaVu and Liberation fonts, so a form lays out the same on a machine that has
  none of the fonts its CSS names;
- an opener, installed as `open` and `xdg-open` in the bundle's
  tools directory, which `NSWorkspace` searches before `$PATH`. It restores the
  host's `PATH` and `LD_LIBRARY_PATH` before handing a URL to the host, because
  a browser started with the image's libraries does not start;
- symbol tables (`NO_STRIP`), so a crash prints its own symbolized backtrace
  (`XFCrashReporter.h`). `APPIMAGE_GDB=1` runs gdb against the host's libraries.

A release's image (not a pre-release's) carries update information naming
the newest release's `.zsync`, which is attached beside it, so Gear Lever,
AppImageUpdate and the like update it by the blocks that changed.

## macOS: signed apps

`XFormsViewer.app` and `XFormsDesigner.app`, each embedding its own
`XFormsKit.framework` (and the designer `XFormsDesignKit.framework`), signed inside-out (framework, then app) with a
Developer ID and notarized. Signing needs `MACOS_CERTIFICATE` (base64 `.p12`),
`MACOS_CERTIFICATE_PASSWORD` and `MACOS_SIGN_IDENTITY`; notarization also needs
`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD`, all in the
`production` environment. Without them the job still produces artifacts,
named `-unsigned`.

Both apps update themselves with Sparkle (*Check for Updates…* in the app
menu; `Apps/Shared/XFUpdater.h`). Each reads its own appcast in the newest
release, `appcast-XFormsViewer.xml` and `appcast-XFormsDesigner.xml`
(`SUFeedURL` in its Info.plist), which a release (not a pre-release) writes
and signs with the EdDSA key in the `SPARKLE_PRIVATE_KEY` secret, also in
`production`; its public half is `SUPublicEDKey`. Without the secret there
are no appcasts, and the apps are not offered the release.

## Versions and Info.plists

Each app has one `Apps/<App>/<App>-Info.plist` for both Cocoa and GNUstep.
Xcode points `INFOPLIST_FILE` at it; gnustep-make finds it by name and merges
it into the `Info-gnustep.plist` it generates, which is a build output and not
in the tree. No Xcode build settings (`$(PRODUCT_NAME)`) in it: gnustep-make
does not expand them.

No version number is kept by hand. The release workflows (gnustep-release-actions'
`stamp-version.sh`) write the tag (or `0.0.0-build<run>`) into those plists and
`MARKETING_VERSION`, and the run number into `CFBundleVersion`: the display
form for GNUstep's About panel, the leading dotted number where Apple parses
it. The tree carries `0.0.0-dev`.
