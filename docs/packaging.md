# Packaging and releases

## Artifacts

Every push uploads unsigned builds to its Actions run, kept for 14 days: an
`XFormsKit-Linux-<sha>` AppImage and an `XFormsKit-macOS-<sha>` with both apps.

`.github/workflows/release.yml` is the shipping one. It runs on a `v*` tag
(and attaches the files to the GitHub release), or by hand for the artifacts
alone. The "Run workflow" button only appears once the workflow is on the
default branch; a tag triggers it from anywhere.

## Linux: one AppImage

`Scripts/prepare-appdir.sh` assembles an AppDir with the framework, the viewer,
the designer, the launcher and the GNUstep runtime; `Scripts/package-appimage.sh`
hands it to `linuxdeploy`. Both are ports of RDLKit's, which are ports of
UDQuakeTools'; the differences are marked in the files. `AppRun` writes a
GNUstep config pointing `GNUSTEP_SYSTEM_ROOT` and its siblings at wherever the
image is mounted, since that path is not known until it runs.

    ./XFormsKit-Linux-*.AppImage                   # the launcher: pick an app
    ./XFormsKit-Linux-*.AppImage designer
    ./XFormsKit-Linux-*.AppImage form.xhtml        # a file opens the viewer
    ln -s XFormsKit-Linux-*.AppImage xformsdesigner && ./xformsdesigner

`AppRun` picks the app from the name it was invoked through, then from the
first argument, and otherwise opens **XFormsLauncher** — one image, two apps,
so it asks. The launcher is GNUstep-only; a Mac installs the apps separately.

What the image carries besides the apps:

- the **Eau** theme, built into the prefix by `dependencies.sh` (a theme links
  against the gui it is loaded into, so it cannot ship prebuilt) and selected by
  `AppRun` in each app's defaults domain, with Liberation fonts and Ctrl mapped
  as Command;
- DejaVu and Liberation fonts, so a form lays out the same on a machine that has
  none of the fonts its CSS names;
- `Scripts/appimage/open`, installed as `open` and `xdg-open` in the bundle's
  tools directory, which `NSWorkspace` searches before `$PATH`. It restores the
  host's `PATH` and `LD_LIBRARY_PATH` before handing a URL to the host, because
  a browser started with the image's libraries does not start;
- symbol tables (`NO_STRIP`), so a crash prints its own symbolized backtrace
  (`XFCrashReporter.h`). `XF_GDB=1` runs gdb against the host's libraries.

## macOS: signed apps

`XFormsViewer.app` and `XFormsDesigner.app`, each embedding its own
`XFormsKit.framework`, signed inside-out (framework, then app) with a
Developer ID and notarized. Signing needs `MACOS_CERTIFICATE` (base64 `.p12`),
`MACOS_CERTIFICATE_PASSWORD` and `MACOS_SIGN_IDENTITY`; notarization also needs
`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD`, all in the
`production` environment. Without them the job still produces artifacts,
named `-unsigned`.

## Versions and Info.plists

Each app has one `Apps/<App>/<App>-Info.plist` for both Cocoa and GNUstep.
Xcode points `INFOPLIST_FILE` at it; gnustep-make finds it by name and merges
it into the `Info-gnustep.plist` it generates, which is a build output and not
in the tree. No Xcode build settings (`$(PRODUCT_NAME)`) in it: gnustep-make
does not expand them.

No version number is kept by hand. `Scripts/stamp-version.sh` writes the tag
(or `0.0.0-build<run>`) into those plists and `MARKETING_VERSION`: the display
form for GNUstep's About panel, the leading dotted number where Apple parses
it. The tree carries `0.0.0-dev`.
