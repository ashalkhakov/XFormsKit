# XFormsKit

An XForms 1.1 engine for Cocoa and GNUstep. The processor reads an
XHTML+XForms host document, maintains XML instances, evaluates XPath 1.0
bindings, and maps controls onto AppKit.

XPath evaluation follows the XSLTForms `xpathexpr` object model
(LocationExpr, StepExpr, node tests, core functions, ExprContext
dependencies). Expressions are compiled at runtime (XSLTForms compiles
them in XSLT); the evaluator is an Objective-C translation of that AST.

## Status

First vertical slice:

- Load a well-formed XHTML+XForms document
- One `xf:model` / `xf:instance`
- `xf:input` (`ref`) and `xf:output` (`value`)
- XPath 1.0: location paths and axes, predicates, unions, arithmetic,
  XPath 1.0 core functions, plus XForms `instance()` / `context()`
- AppKit host view (`XFFormView`): stock widgets for input/output/secret/
  textarea/trigger/submit/select/select1/range/group/repeat/switch,
  standalone `xf:label`, and `NSDatePicker` for `xsd:date` / `time` /
  `dateTime` inputs
- XML Events (`XFListener` / `XFXMLEvents`), translated from XSLTForms
  `xmlevtmngt`: registry, EventContexts stack, capture/target/bubble
  dispatch, `ev:listener` and `ev:*` attributes, `xf:action` handlers
- Model init matches XSLTForms: construct loads instances, then
  rebuild / recalculate / revalidate run without events; `xforms-ready`
  follows. `xf:bind` nodesets, `@calculate`, boolean MIPs, and the
  `nodesChanged` / per-MIP dependency lists (`XFMIPBinding`)
- Actions (`XFAbstractAction`): `if` / `while` / `iterate`, `xf:action`
  groups, `xf:setvalue`, `xf:dispatch`, `xf:message`, and
  rebuild/recalculate/revalidate/refresh/reset. Deferred updates via
  `XFDeferredUpdates` (XsltForms_globals.openAction / closeChanges)
- Submission (`XFSubmission` / `XsltForms_submission`): serialize
  XML or urlencoded, relevant pruning, validate, headers, resource/method
  children, `replace="instance"|"text"|"none"|"all"`. Transport is
  pluggable (`XFMapSubmissionTransport` for tests, `XFHTTPSubmissionTransport`
  via `NSURLConnection`). `xf:send` dispatches `xforms-submit`; `xf:load`
  resolves a resource and can replace an instance (XSLTForms `@instance`)
- Groups (`XFGroup` / XsltForms_group): optional `ref`, relevance, child
  controls evaluated against the bound node
- Repeats (`XFRepeat` / XsltForms_repeat): `nodeset`/`ref`, 1-based index,
  `startindex`, per-item control instances, `index()` and `xf:setindex`,
  `xforms-scroll-first` / `xforms-scroll-last`
- Insert / delete (`XsltForms_insert` / `XsltForms_delete`): origin clone,
  `at` / `position`, empty-nodeset + `context`, `xforms-insert` /
  `xforms-delete` on the instance, repeat index update
- `xf:switch` / `xf:case`, `xf:toggle`, `xf:setfocus`
- Standalone `xf:label` (`XFLabelControl`) when the element has `ref` /
  `value` or is not a caption child of another control
- Date-typed `xf:input` (`xsd:date` / `xsd:time` / `xsd:dateTime`, or
  `appearance="date|time|dateTime"`) maps to `NSDatePicker`
- Schema types (`XFType`): XSD + XForms atomic types applied in
  instance `revalidate` (empty is type-valid unless `required`)
- XForms 1.1 XPath functions: `if`/`choose`, `current`, `event`, `id`,
  `lang`, `property`, `power`, `random`, `boolean-from-string`,
  `count-non-empty`, date/duration helpers, `is-valid`,
  `is-card-number`, `digest`/`hmac`
- Multiple `xf:model` elements; `xf:instance/@src` against the host URL
- `xf:select`/`select1` itemset, choices, copy; `xf:upload` + multipart submit
- `xf:hint` / `help` / `alert`; MIP events after `xforms-ready`. All of
  them, and `xf:message`, take inline XHTML and `xf:output` (XForms 1.1
  §9.3.1): the markup reaches the host alongside the plain text, and
  both backends render it — a read-only `NSTextView` on AppKit, an
  attributed label or sheet on iOS
- UIKit form layer (`XFFormViewController`) and an iOS host app
  (`Apps/XFormsMobile`)

XSLTForms JS ↔ XFormsKit class map: `docs/XSLTForms-mapping.md`.

## Layout

    Sources/XFormsKit/     engine + AppKit views
    Apps/XFormsViewer/    document-based host (3-pane navigator / form / inspector)
    Samples/               ported XSLTForms `testsuite/samples` forms
    Tests/XFormsKitTests/  XCTest cases (Apple XCTest or gnustep/tools-xctest)
    Tests/Fixtures/        sample forms

## Viewer editor

XFormsViewer is a small document-based editor, not only a previewer.

- **Palette** (top-left): model, controls, support, and actions. **Add** (or
  double-click) inserts under the selected host element, or under
  `xf:model` / `xhtml:body` when that is the right zone.
- **Navigator**: host tree and instance tree. Instance nodes are data; do
  not drop palette items there.
- **Inspector**: `id`, binding attributes, MIP expressions on `xf:bind`,
  submission options, and `label`/`hint`/`help`/`alert` children. **Apply**
  rewrites the host document and rebuilds the form.
- **Source** tab is editable; **Apply Source** reloads the processor.
- File: New / Open / Save. Edit: Duplicate, Delete.

## Building

### Xcode (macOS)

    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit -configuration Debug build
    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit -configuration Debug test

### The DOM

The engine speaks one XML API, `XFXML*`, declared in
`Sources/XFormsKit/XFXMLTypes.h`, and one tree stands behind it on every
platform: **XFDOM**, the project's own portable implementation in
`Sources/XFormsKit/DOM/`. There is nothing to configure.

It was a build switch for a while — NSXML by default, XFDOM under
`XF_PORTABLE_DOM`, which iOS required because Foundation there has no
`NSXMLDocument`. Once XFDOM passed every suite on macOS, GNUstep and iOS,
the second tree was retired: one implementation means one set of
behaviours to know, the apps stopped needing a configuration of their
own, and a gnustep-base NSXML bug the engine used to trip over
(`patches/gnustep/`) stopped mattering to it.

`XFDOMTests` still compares against the platform's NSXML wherever there
is one. That is deliberate: NSXML is a mature DOM and a useful reference
for what the behaviour ought to be, so the suite asserts XFDOM literally
and logs NSXML's answer beside it. Five documented divergences are
recorded there.

### iOS

The framework target is multiplatform. On an iPhone SDK it excludes the
AppKit view layer and builds the engine, the XPath layer and XFDOM
against Foundation alone:

    xcodebuild -project XFormsKit.xcodeproj -target XFormsKit \
      -sdk iphonesimulator -configuration Debug build

It is tested there, not merely built: 277 unit tests and all 458 W3C
conformance cases run in the simulator.

    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit \
      -destination 'platform=iOS Simulator,name=iPhone 17' test

There is a UIKit form layer too (`XFFormViewController`): a grouped table
view, one control per row, scrolling vertically only. The AppKit layout
is a fixed-width two-column form on a canvas at least 620pt wide, which
on a phone means sideways scrolling from the first row, so the iOS form
is built from a portable row model (`XFFormRows`) shown in the iOS
idiom — stock cells, a switch for a boolean, a picker pushed as the next
screen, hints and alerts as footnote rows, swipe to delete a repeat item,
a prev/next bar above the keyboard. A host `<table>` is drawn as a grid
(scrolling sideways inside its own row when it must), and prose with
controls in it flows as a line rather than one row per control. See `docs/ios-port-plan.md`.

### The iOS app

`Apps/XFormsMobile` is the host: pick a form document, fill it in.

    xcodebuild -project XFormsKit.xcodeproj -target XFormsMobile \
      -sdk iphonesimulator -configuration Debug build

The first screen lists the bundled `Samples/` forms — the same set the
macOS viewer offers under File ▸ Open Sample — and a folder button opens
any other form through the document picker.

Deliberately that and no more — XForms is a client for a form *server*,
and there is none to point it at yet, so opening a document from the
file system is the useful thing a host can do today. Forms also open
from Files and from other apps' share sheets, and the app's own
Documents folder appears in Files, so a form dragged onto the Simulator
window can be picked.

### GNUstep

Requires GNUstep Base, GUI, Make, and [tools-xctest](https://github.com/gnustep/tools-xctest).

    source /usr/share/GNUstep/Makefiles/GNUstep.sh   # path may differ
    make
    make check

`make check` builds the `XFormsKitTests` bundle and runs `xctest` on it.

### Viewer

Document-based host with an Xcode-style 3-pane window: document tree on
the left, Form / Source / Instance in the center, inspector on the right.

    make viewer                          # GNUstep, after the framework
    open -a XFormsViewer Samples/hello.xhtml
    # or: xcodebuild -project XFormsKit.xcodeproj -scheme XFormsViewer build

File ▸ Open Sample lists the ported XSLTForms forms.

### Designer

The form editor, the same document model with an outline, a palette and
inspectors around it. It builds on both platforms:

    make designer                        # GNUstep, after the framework
    make apps                            # both of them
    # or: xcodebuild -project XFormsKit.xcodeproj -scheme XFormsDesigner build

## Continuous integration

`.github/workflows/ci.yml` runs on every push:

- **macOS (Xcode)** — builds the framework, the viewer and the designer,
  then runs the unit suite and the W3C suite. It also builds the framework
  for both iPhone SDKs and the iOS app for the simulator, and runs both
  suites in the simulator. That is what keeps the portable half portable:
  iOS Foundation has no NSXML, so a stray dependency on it fails there and
  nowhere else. It finishes by packaging an unsigned copy of each app.
- **Ubuntu (GNUstep, clang, gnustep-2.0)** — builds the whole GNUstep
  stack from source into a cached prefix
  (`.github/scripts/dependencies.sh`), then builds and runs both suites
  under `xvfb`, builds both apps, and packages and smoke-tests the
  AppImage. One patch is applied to gnustep-base and one to Opal
  (`patches/gnustep/`); see `patches/gnustep/README.md` for them and for
  what else a Linux setup should know.

## Builds and releases

Every push produces downloadable artifacts, from the run's own page in the
Actions tab: an `XFormsKit-Linux-<sha>` AppImage and an
`XFormsKit-macOS-<sha>` holding `XFormsViewer.app` and `XFormsDesigner.app`.
They are unsigned, named for the commit, and kept for 14 days — for trying a
build, not for shipping.

`.github/workflows/release.yml` is the shipping one. It runs on a `v*` tag, or
by hand for the artifacts without publishing a release. Note that the "Run
workflow" button only appears once the workflow is on the default branch; a tag
triggers it from anywhere.

* **Linux** — one AppImage carrying both apps. `Scripts/prepare-appdir.sh`
  assembles an AppDir with the framework, both applications and the GNUstep
  runtime, and `Scripts/package-appimage.sh` hands it to `linuxdeploy`. The
  layout follows GNUstep's: `AppRun` writes a config pointing
  `GNUSTEP_SYSTEM_ROOT` and its siblings at wherever the image is mounted,
  because that path is not known until it runs. Both scripts are ports of
  RDLKit's, which are ports of UDQuakeTools'; the places they differ are
  marked in the files.

  Launching the image opens **XFormsLauncher**, a chooser with a button per
  app — one image, two applications, so it asks which. (It is the same answer
  UDQuakeTools' `UDLauncher` gives for three.) Either app is also reachable
  directly:

      ./XFormsKit-Linux-*.AppImage designer
      ./XFormsKit-Linux-*.AppImage form.xhtml        # a file opens the viewer
      ln -s XFormsKit-Linux-*.AppImage xformsdesigner && ./xformsdesigner

  `AppRun` picks the app from the name it was invoked through, then from the
  first argument — `viewer`, `designer`, or a path, which means the viewer —
  and with none of those it opens the launcher. Desktop entries for all three
  ship in `usr/share/applications` inside the image; the launcher's is the one
  at the top level, which is what desktop integration installs.

  The launcher is GNUstep-only (`make launcher`, or `make apps` for all
  three). A Mac installs `XFormsViewer.app` and `XFormsDesigner.app`
  separately and has nothing to choose between, so the Xcode project does not
  build it.

  The image carries the **Eau** theme, built from source into the prefix by
  `.github/scripts/dependencies.sh` (a theme bundle links against the gui it
  will be dlopened into, so it cannot be shipped prebuilt), and `AppRun`
  selects it — along with the bundled Liberation fonts — by writing them into
  each app's own defaults domain at launch, so they look the way a GNUstep
  desktop is expected to look rather than like stock GNUstep. It also carries
  `Scripts/appimage/open`, installed into the bundle's GNUstep tools directory
  as both `open` and `xdg-open` and named by the `GSUnknownFileTool` default:
  `NSWorkspace` hands a URL to whatever `+[NSTask launchPathForTool:]` finds,
  and that searches GNUstep's tool directories before `$PATH` — inside the
  image those are in the bundle, where no opener lives. The shim restores the
  host's `PATH` and `LD_LIBRARY_PATH` before handing the URL on, because a
  browser started with the image's libraries does not start.
* **macOS** — `XFormsViewer.app` and `XFormsDesigner.app`, each embedding its
  own copy of `XFormsKit.framework` (they link it through `@rpath`, so a
  bundle without it does not launch off the build machine), signed with a
  Developer ID and notarized. Signing needs `MACOS_CERTIFICATE` (a base64
  `.p12`), `MACOS_CERTIFICATE_PASSWORD` and `MACOS_SIGN_IDENTITY`;
  notarization additionally needs `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and
  `NOTARY_PASSWORD`. Without them the build still produces artifacts, marked
  `-unsigned`, rather than failing.

Each app has **one** property list, `Apps/<App>/<App>-Info.plist`, carrying
the Cocoa keys and the GNUstep ones side by side. Xcode points
`INFOPLIST_FILE` at it; gnustep-make finds the same file by name and merges it
into the `Info-gnustep.plist` it generates inside the bundle — that file is a
build output, so there is none in the tree. Nothing in the shared file may use
an Xcode build setting such as `$(PRODUCT_NAME)`, because gnustep-make does not
expand them.

No version number is maintained by hand. `Scripts/stamp-version.sh` writes the
tag (or `0.0.0-build<run>`) into those two plists and into the project's
`MARKETING_VERSION`, in two forms: the display version for GNUstep's About
panel, which can say anything, and the leading dotted number for the keys Apple
parses. What is in the tree is `0.0.0-dev`, which is what a build from a
working copy is.

The AppImage bundles DejaVu and Liberation, and the Microsoft core fonts if
they are installed on the builder: a form's CSS names the fonts its author had,
and the host tree is laid out in whatever the machine can find.

## License

GNU Lesser General Public License 2.1. See `COPYING.LIB`.
The implementation is original so a later relicensing is still possible
if all contributors agree.
