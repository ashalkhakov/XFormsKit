# Porting XFormsKit to iOS

Status: proposal, not started. Nothing in this document has been
implemented. Figures are measured from the tree at the time of writing
(`master`, after the select1 label fix).

## The short answer

The AppKit widgets are the *smaller* half of the job.

`Sources/XFormsKit/AppKit/` is 5,279 lines and maps onto UIKit fairly
mechanically. But the engine underneath it — 21,687 lines that have no
AppKit dependency at all — is built on `NSXMLDocument` / `NSXMLElement` /
`NSXMLNode`, and **those classes do not exist on iOS**. Verified against
the SDK:

    iPhoneOS.sdk/…/Foundation.framework/Headers/  → NSXMLParser.h only
    MacOSX.sdk/…/Foundation.framework/Headers/    → NSXMLNode.h, NSXMLElement.h,
                                                     NSXMLDocument.h, NSXMLDTD.h, …

iOS ships a SAX parser and no DOM. There are ~1,200 `NSXML*` references
spread across ~40 engine files, so the port is really two projects:

1. Give the engine a portable XML DOM (the critical path).
2. Give the engine a second view layer (the part that was asked about).

Doing 2 without 1 is not possible — nothing in `Sources/XFormsKit/`
compiles for iOS today.

## What the survey found

### The layering is already good

| Layer | Lines | AppKit? | Portable today? |
| --- | ---: | --- | --- |
| Engine (`Sources/XFormsKit/*.m`) | 14,397 | no | blocked only by NSXML |
| XPath (`Sources/XFormsKit/XPath/`) | 4,515 | no | blocked only by NSXML |
| Public headers (`*.h`) | 2,775 | 5 headers only | mostly |
| View layer (`AppKit/`) | 5,279 | yes | no — needs a UIKit twin |
| Tests | 11,180 | 20 references total | almost entirely |

Only five public headers import AppKit: [XFFormView.h](../Sources/XFormsKit/XFFormView.h),
[XFSVG.h](../Sources/XFormsKit/XFSVG.h), [XFRichText.h](../Sources/XFormsKit/XFRichText.h),
[XFRichTextEditor.h](../Sources/XFormsKit/XFRichTextEditor.h) and the umbrella. No
engine `.m` file references a view class. The `XFTableModel` / `XFTableAdapter`
and `XFHostEdit` / designer splits already put the portable half in the engine
and the platform half in `AppKit/`. That discipline is why this port is
tractable at all.

### The engine is not hard to port — apart from the DOM

No other macOS-only Foundation API is used: no `NSTask`, `NSPasteboard`,
`NSWorkspace`, `NSAppleScript`. `CommonCrypto` (used by the digest
functions) ships on iOS, and the `#if defined(__APPLE__)` split in
[XFSubmissionTransport.m](../Sources/XFormsKit/XFSubmissionTransport.m) already
handles it. The XPath engine is the project's own — only one call site
uses the DOM's built-in XPath, [XFModel.m:272](../Sources/XFormsKit/XFModel.m#L272),
and it is a one-line replacement.

`NSURLConnection`, used by `XFHTTPSubmissionTransport`, is deprecated
(iOS 9) but still present. The transport is already pluggable, so an
`NSURLSession` implementation is an additive change, not a port.

### The DOM surface actually used is small

Despite ~1,200 references, the code only touches about 30 selectors and
10 constructors. Full inventory in
[ios-port-widget-map.md](ios-port-widget-map.md). That is a
weekend-sized API surface; the cost is in matching *semantics*
(serialization and escaping, namespace resolution, deep copy, `detach`,
document order), not in typing.

### Node identity is a hard constraint on the DOM choice

[XFNodeState.m:28](../Sources/XFormsKit/XFNodeState.m#L28) attaches per-node MIP
state to the node with `objc_setAssociatedObject`, and
[XFExprContext.m:135](../Sources/XFormsKit/XPath/XFExprContext.m#L135) uses
`indexOfObjectIdenticalTo:`. Both require **one stable Objective-C object per
node, for the life of the tree**.

That rules out the obvious shortcut of wrapping `libxml2`'s `xmlNodePtr`
on demand, where wrapper identity is not stable and associated objects
would be silently lost. The DOM must be a real Objective-C tree whose
nodes *are* the objects. libxml2 (which does ship on iOS) may still be
used as the parser and serializer behind it, but not as the tree.

### The existing test suite can verify the port on macOS

667 test methods exist: 209 in `Tests/XFormsKitTests/`, 458 in
`Tests/W3CTests/`. Of those, only `XFUIControlTests` touches AppKit, and
the entire W3C suite's view coupling is two lines in the harness
([XFW3CTestCase.m:207](../Tests/W3CTests/XFW3CTestCase.m#L207) builds one form
view as a smoke test).

So roughly 630 tests exercise the engine through the DOM and nothing
else. Build the new DOM for macOS as well as iOS, put it behind a build
flag, and the existing suite becomes a conformance test for it — on a
Mac, before an iOS target exists. This is the single most valuable
scheduling fact in this document: **the riskiest phase can be fully
verified before any iOS code is written.**

## Target architecture

Three modules instead of one framework:

    XFormsCore        engine + XPath + XFDOM       (Foundation only)
    XFormsUI-AppKit   today's AppKit/ directory    (macOS, GNUstep)
    XFormsUI-UIKit    new                          (iOS, iPadOS)

`XFormsKit.framework` stays as the macOS product (Core + AppKit UI) so
that the viewer, the designer and the GNUstep build see no change.

### The DOM: `XFDOM*`

New classes `XFDOMNode`, `XFDOMElement`, `XFDOMDocument` — named to avoid
confusion with the existing [XFXML](../Sources/XFormsKit/XFXML.h) static-helper
facade. A pure Objective-C tree, parsed with `NSXMLParser`.

Written clean-room, directly against the NSXML shape, so the engine's
call sites move over by renaming the class rather than through a
compatibility facade. Lifting the previous project's DOM was assessed and
declined — the reasoning, and the gap analysis that became this
implementation's test specification, are in
[ios-port-dom-lift.md](ios-port-dom-lift.md).

**Status: the engine runs on it.** `Sources/XFormsKit/DOM/` holds
`XFDOMNode`, `XFDOMElement`, `XFDOMDocument` and the `NSXMLParser`-based
builder. The engine, the XPath layer, the AppKit layer and the tests were
renamed off `NSXML*` onto the neutral `XFXML*` names declared in
[XFXMLTypes.h](../Sources/XFormsKit/XFXMLTypes.h), which are
`@compatibility_alias` declarations bound to NSXML by default and to
XFDOM under `XF_PORTABLE_DOM`.

**Both configurations are green — 683 tests each:**

    xcodebuild -scheme XFormsKit test                                          # NSXML
    xcodebuild -scheme XFormsKit test \
        GCC_PREPROCESSOR_DEFINITIONS='$(inherited) XF_PORTABLE_DOM=1'          # XFDOM
    make check XF_PORTABLE_DOM=1        # the same switch under GNUstep
    make w3ccheck XF_PORTABLE_DOM=1

225 unit tests (including 16 differential DOM tests) and all 458 W3C
conformance tests pass against XFDOM, and unchanged against NSXML.

Still to do: run both configurations under GNUstep, which has not been
exercised from here; migrate the two apps, which still name NSXML types
directly and so only build in the default configuration; and retire the
two workarounds XFDOM makes unnecessary (the `<!--xf:ws-->` whitespace
markers in XFProcessor, and the CDATA token substitution in
XFSubmission).

On macOS the names alias the system classes so the shipping product keeps
the battle-tested implementation and carries zero regression risk:

    #if XF_PORTABLE_DOM
    @class XFDOMElement;                   // the new implementation
    #else
    #define XFDOMElement NSXMLElement      // macOS default
    #endif

A macro rather than a `typedef` because message sends to the alias
(`[XFDOMElement elementWithName:…]`) must keep working; whether a
`typedef` also suffices is a one-hour spike, not a design decision.

The rename of ~1,200 references is mechanical (`sed`), reviewable as a
single no-op commit, and can land on `master` long before any iOS work —
it changes nothing on macOS.

### The view layer: extract the geometry, not the widgets

Two ways to get a UIKit view layer:

**A. Parallel implementation.** Write `XFFormViewIOS` next to
`XFFormView`. Fastest to a first screen, but it duplicates ~1,600 lines
of layout arithmetic and doubles the maintenance cost forever — the
`xf:select1` label bug fixed in
[XFFormView+Layout.m](../Sources/XFormsKit/AppKit/XFFormView+Layout.m) would have
had to be found and fixed twice.

**B. Extract the layout engine (recommended).**
[XFFormView+Layout.m](../Sources/XFormsKit/AppKit/XFFormView+Layout.m) is almost
pure geometry over the control tree already: absolute frames, one text
measurement primitive (`widthOfText:font:`, which is
`sizeWithAttributes:` — available on iOS unchanged), and a set of layout
constants. Split it into a portable pass that walks the control tree and
emits *widget specs* (kind, frame, text, state, the owning control), and
a per-platform factory that turns specs into real views.

Two properties of the existing code make B much cheaper than it sounds:

- The views are already flipped — [XFFormView.m:220](../Sources/XFormsKit/AppKit/XFFormView.m#L220)
  returns `isFlipped = YES`, which is UIKit's native origin. The layout
  arithmetic transfers **unchanged**; no coordinate flipping anywhere.
- Layout already calls back into widget construction only for
  *measurement* (`sizeToFit` on buttons, popup item widths). Those few
  sites become measurement functions in the spec pass.

B is roughly a week more than A up front and pays for itself the first
time a layout rule changes.

### SVG: retarget to Core Graphics, once

[XFSVGView.m](../Sources/XFormsKit/AppKit/XFSVGView.m) is 1,404 lines, of which
parsing, the render tree and hit testing (lines 1–1020) are portable in
substance but written against `NSBezierPath`, `NSAffineTransform`,
`NSGradient` and `NSColor`. `NSAffineTransform` and `NSGradient` do not
exist on iOS at all.

Rather than maintain two drawing backends, port the renderer to Core
Graphics (`CGPath`, `CGAffineTransform`, `CGGradient`, `CGContext`) — one
implementation that compiles for both platforms, and a simplification of
the macOS side as a side effect. `XFSVGView`/`XFSVGViewIOS` then shrink
to a thin `drawRect:` host each.

## Phases

Each phase is independently landable and verifiable. Phases 1–3 are
macOS-only work that leaves the shipping product unchanged.

### Phase 0 — Module split — **DONE**

No separate `XFormsCore` target was needed. The framework target is
multiplatform instead: on an iPhone SDK it excludes
`Sources/XFormsKit/AppKit/` and defines `XF_PORTABLE_DOM`, which is the
same split without a second product to keep in sync, and without touching
how macOS builds.

    SUPPORTED_PLATFORMS = macosx iphoneos iphonesimulator
    SDKROOT = auto
    EXCLUDED_SOURCE_FILE_NAMES[sdk=iphone*] = <the AppKit layer>
    GCC_PREPROCESSOR_DEFINITIONS[sdk=iphone*] = $(inherited) XF_PORTABLE_DOM=1

The header split that would have been the bulk of this phase turned out to
exist already: no engine source imports AppKit, and
[XFormsKit.h](../Sources/XFormsKit/XFormsKit.h) guards its five view
headers behind `#if __has_include(<AppKit/AppKit.h>)`.

### Phase 1 — The portable DOM (≈2–3.5 weeks, critical path)

Write `XFDOM*` against the inventory in
[ios-port-widget-map.md](ios-port-widget-map.md), pinning each behaviour
with a differential test against NSXML; then rename engine references
behind the `XF_PORTABLE_DOM` flag. Exit: the **full existing suite passes
in both configurations** —

    xcodebuild -scheme XFormsKit test                                   # NSXML
    xcodebuild -scheme XFormsKit test XF_PORTABLE_DOM=1                 # XFDOM

Budget the range for serialization fidelity: the W3C suite compares
serialized instance data, and escaping, namespace-declaration placement
and whitespace handling are where a hand-written DOM bleeds. The lift
helps least exactly here — it hands over a good tree, not a good
serializer.

### Phase 2 — Core Graphics SVG (≈1–1.5 weeks)

Retarget the renderer; keep `XFSVGView` as the macOS host. Exit: the SVG
tests in `XFUIControlTests` pass and the samples render identically
(compare screenshots of `Samples/` before and after).

### Phase 3 — Portable text and layout (≈2–3 weeks)

`XFRichText` off `NSFontManager` onto `UIFontDescriptor`-style trait
queries behind a small font abstraction; extract the layout pass per
option B. Exit: macOS form rendering pixel-identical; the layout pass has
its own unit tests asserting widget specs (which is also the first time
the label-per-item class of bug becomes directly testable without a view).

### Phase 4 — iOS Core lands — **DONE (build), test host outstanding**

`XFormsKit.framework` builds for both iOS SDKs:

    xcodebuild -project XFormsKit.xcodeproj -target XFormsKit \
      -sdk iphonesimulator -configuration Debug build
    xcodebuild -project XFormsKit.xcodeproj -target XFormsKit \
      -sdk iphoneos -configuration Debug build CODE_SIGNING_ALLOWED=NO

The simulator slice is a universal x86_64 + arm64 Mach-O with a minimum of
iOS 15, carrying 99 Objective-C classes — the engine, the XPath layer and
XFDOM — and linking **Foundation, CoreFoundation and libobjc only**. No
AppKit, no UIKit, no libxml2. CI asserts that shape on every run rather
than trusting the exclusion list: it fails if a view class appears in the
binary or if anything but Foundation is linked.

What is left of this phase is running the ~630 engine tests *on* iOS.
That needs an iOS unit-test target and a host app, which is a scheme and
signing question rather than a porting one — the same test sources should
run unchanged, since only `XFUIControlTests` touches AppKit.

### Phase 5 — The UIKit widget factory (≈2–3 weeks)

The part the question was about. Per-control mapping and the
AppKit-idiom translations (target/action → `UIControlEvents`, editing
notifications → delegates, key-view loop → input accessory) are tabulated
in [ios-port-widget-map.md](ios-port-widget-map.md). Radio buttons,
checkboxes and the hover badges have no UIKit equivalent and need custom
views — budgeted inside this phase.

Exit: `Samples/hello.xhtml` and the kaldi onboarding form are usable end
to end in the Simulator.

### Phase 6 — iOS interaction gaps (≈1–2 weeks)

Upload (`NSOpenPanel` runs modal and synchronous; `UIDocumentPickerViewController`
is presented and async — the form view needs a presenting-controller
delegate, an API addition), badges and tooltips without hover, host
`<table>` rendering, hardware-keyboard `accesskey` via `UIKeyCommand`.

### Phase 7 — Host app and CI (≈1 week)

A minimal iOS viewer, an iOS test target in CI, README updates.

## Effort

| Phase | Work | Estimate |
| --- | --- | ---: |
| 0 | Module split | **done** |
| 1 | Portable DOM (clean-room `XFDOM*`) | **done** |
| 2 | Core Graphics SVG | 1–1.5 w |
| 3 | Portable text + layout extraction | 2–3 w |
| 4 | iOS Core green | **done** (tests on-device outstanding) |
| 5 | UIKit widget factory | 2–3 w |
| 6 | iOS interaction gaps | 1–2 w |
| 7 | Host app + CI | 1 w |
| | **Total** | **10–15 weeks** |

One engineer already familiar with this codebase. The spread is
dominated by phase 1: if the DOM's serialization matches quickly it is
two weeks, if the W3C suite finds a long tail of escaping and namespace
differences it is three and a half.

A useful earlier milestone: phases 0, 1, 4 and a cut-down phase 5
(text fields, buttons, checkboxes, radios, popups — no SVG, no rich text,
no tables) gives a working iOS form renderer in roughly 5–7 weeks.

## Decisions needed before starting

1. **Layout: option A or B.** Recommendation: B. Costs about a week more
   and removes a permanent double-maintenance tax.
2. **DOM implementation.** Largely settled: lift the previous project's
   DOM ([ios-port-dom-lift.md](ios-port-dom-lift.md)), which is a pure
   Objective-C tree over `NSXMLParser` and therefore satisfies the
   node-identity constraint. What remains open is whether the rewritten
   serializer uses libxml2's `xmlTextWriter` (as the old one did — ships
   on iOS, but a second dependency) or is written directly in
   Objective-C. Recommendation: plain Objective-C, to keep one code path
   across Apple and GNUstep and to make NSXML output parity easier to
   control.
3. **Minimum iOS version.** `UIButton` menus (the `NSPopUpButton`
   replacement) and the compact `UIDatePicker` styles want iOS 14+.
   Below that, popups need a `UIPickerView` input view.
4. **iPad-first or phone-first.** The layout is a fixed-width two-column
   form (`kLabelWidth + kFieldWidth`, absolute frames). That lands well on
   an iPad and badly on a phone in portrait. A phone-first target means a
   responsive single-column mode, which is design work beyond porting and
   is *not* in the estimate above.

## Out of scope

- **XFormsDesigner** (10,249 lines across both apps) — a Mac document
  app built on `NSOutlineView`, inspectors, panels and xibs. Not a port,
  a rewrite. `XFHostEdit`, the editing engine it drives, is already
  portable and would come along for free.
- **GNUstep.** Unaffected. Every phase either leaves `AppKit/` alone or
  changes it identically for both Apple and GNUstep; phase 1's DOM would
  give GNUstep a way to drop its NSXML dependency, but that is a bonus,
  not a goal.
- **Responsive phone layout** — see decision 4.
