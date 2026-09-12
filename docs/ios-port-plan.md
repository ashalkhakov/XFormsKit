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

### SVG: one tree walk, two drawing backends

[XFSVGView.m](../Sources/XFormsKit/AppKit/XFSVGView.m) is 1,404 lines, of which
parsing, the render tree and hit testing (lines 1–1020) are portable in
substance but written against `NSBezierPath`, `NSAffineTransform`,
`NSGradient` and `NSColor`. `NSAffineTransform` and `NSGradient` do not
exist on iOS at all.

Core Graphics cannot be the single answer: GNUstep does not have it (see
phase 2, which corrects this). Instead the renderer keeps one portable
tree walk and puts its dozen leaf drawing operations behind a seam, with
an AppKit backend for macOS and GNUstep and a Core Graphics backend for
iOS. `XFSVGView` then shrinks to a thin `drawRect:` host on each
platform.

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

### Phase 2 — Portable SVG — **DONE (macOS and iOS; GNUstep pending CI)**

The plan here said "retarget to Core Graphics, one implementation for both
platforms". A first attempt found that GNUstep has no Core Graphics —
across `Sources/` and `Apps/` the only CG identifier that appeared
anywhere was `CGFloat` — and the phase was rewritten around two drawing
backends. Then the project decided to adopt **Opal**, GNUstep's
Quartz-2D-compatible library, which puts the single-implementation plan
back: Opal ships CoreGraphics *and* CoreText, and gnustep-gui's
`NSGraphicsContext` already declares `- (CGContextRef)CGContext`, the same
accessor Apple's has.

`Sources/XFormsKit/SVG/XFSVGDocument.m` (1,510 lines) is now the renderer:
scanning, path data, the arc conversion, transforms, colours, the render
tree, paint servers, drawing, hit testing — all through `CGPath`,
`CGAffineTransform`, `CGColor`, `CGGradient`, `CGContext` and `CTFont`,
with no view layer. `Sources/XFormsKit/AppKit/XFSVGView.m` is what remains
of the AppKit host: 80 lines, excluded from the iOS build.

Three things were written around gaps in Opal rather than into them:

- `CGPathCreateWithEllipseInRect` is missing, `CGPathAddEllipseInRect` is
  not, so circles and ellipses are built the second way.
- `CGGradientCreateWithColors` wants a `CFArrayRef`; the renderer uses
  `CGGradientCreateWithColorComponents` and plain C arrays instead, so
  nothing depends on toll-free bridging an `NSArray`.
- `CFAutorelease` is not dependable where CoreFoundation is optional, so
  every created path, colour and gradient is explicitly owned and
  released. The two public factories say so in their names:
  `+createPathWithSVGPathData:` and `+createColorWithSVGString:`.

The iOS framework now carries `XFSVGDocument` and `XFSVGNode` and links
CoreGraphics and CoreText; CI asserts that, and that no view class comes
with them. `.github/scripts/dependencies.sh` builds libs-corebase and Opal
into the GNUstep prefix, and the GNUmakefile links `-lopal`.

What is unverified is GNUstep itself: whether Opal builds cleanly in CI,
whether its CoreText covers `CTFontDrawGlyphs` well enough for SVG text,
and whether `-[NSGraphicsContext CGContext]` answers a usable context
under the cairo backend (if it does not, the form view's SVG widget needs
libs-back built with `--enable-graphics=opal`, or an offscreen bitmap
context to draw into). Issues found there are for patching upstream.

### Phase 3 — Portable text and layout extraction — **text done, layout next**

**Rich text: done.** `XFRichText` was one class doing two jobs — converting
between the instance's XHTML subset and an attributed string, and deciding
what that should look like. The second job made it unportable, because the
attribute names it applied (`NSFontAttributeName`,
`NSUnderlineStyleAttributeName`) come from AppKit on macOS and UIKit on
iOS, and the portable core may import neither.

They are now separate:

- `Sources/XFormsKit/RichText/XFRichText.m` — the converter, Foundation and
  the DOM only. It reads and writes **markers**: `XFRichBlock`,
  `XFRichBold`, `XFRichItalic`, and the two this split added,
  `XFRichUnderline` and `XFRichStrike`. Underline and strikethrough used to
  be carried by the AppKit constants themselves, which is what tied the
  serializer to a UI framework.
- `Sources/XFormsKit/AppKit/XFRichTextPresentation.m` — a category that
  turns those markers into a font, an underline style and a strikethrough.
  A UIKit twin of this one file is what an iOS text widget will want; the
  converter it decorates needs no twin.

The editor toggles markers now and recomputes presentation from them, so
what the serializer reads and what the text view shows cannot drift apart.
The round-trip test additionally pins that the converter emits *no*
presentation, and that decorating adds it back.

`XFRichText` is in the iOS framework, which still links no UI framework.

**Layout extraction: deferred deliberately, and smaller than it looked.**

It does not block phase 5; phase 5 shipped without it. Measuring what the
iOS form actually loses, of the three cases only one needs it:

| Case | Needs the extraction? |
| --- | --- |
| An image `xf:output` | No — it needed a row kind. Done. |
| A host `<table>` | No — `XFTableModel` already models it. Done. |
| A control inline in a sentence | **Yes** |

`<p>Please enter <xf:input/> to continue.</p>` becomes three full-width
rows: prose, field, prose. Interleaving text and widgets on a wrapping
line is what `collectAtomsFrom:` (47 lines), `layoutAtoms:` (124) and
`placeInlineControl:` (77) do — about 250 of `XFFormView+Layout.m`'s 638,
and the only part with no iOS equivalent.

That split is ugly for document-shaped forms and defensible for the rest:
one control per row is what a phone wants anyway. So it waits until a form
needs it.

One thing has moved in its favour since this was written. The plan assumed
measurement was the obstacle — `widthOfText:font:` goes through NSFont. But
Opal brought **CoreText to all three platforms**, and the SVG renderer
already measures with `CTFontGetAdvancesForGlyphs`, so a portable text
measurement exists now. The shape would be: a portable pass taking host
nodes plus a width, answering positioned fragments, control frames and a
height; AppKit places NSViews from it, the markup cell places labels and
control views from the same answer, and both get exact heights instead of
Auto Layout estimates.

### Phase 4 — iOS Core lands — **DONE**

`XFormsKit.framework` builds for both iOS SDKs, and **the engine is proven
on iOS by running, not only by compiling**:

    xcodebuild -scheme XFormsKit  -destination 'platform=iOS Simulator,name=iPhone 17' test
    xcodebuild -scheme XFW3CTests -destination 'platform=iOS Simulator,name=iPhone 17' test

| | macOS | iOS Simulator |
| --- | ---: | ---: |
| Unit tests | 225 | 172 |
| W3C conformance | 458 | **458** |

The whole XForms 1.1 conformance suite passes on iOS against XFDOM. The
53 unit tests that do not run there are the AppKit widget tests
(`XFUIControlTests`) and the NSXML differential tests (`XFDOMTests`, which
needs an NSXML to differ from); both test bundles exclude them on an
iPhone SDK, the same way the framework excludes its view layer.

Two lines of the W3C harness held the suite back: it brought up
`NSApplication` and built an `XFFormView` for every case, so that the
widget layer got exercised too. Both are now behind
`#if __has_include(<AppKit/AppKit.h>)`, and on iOS the same cases run
against the engine alone.

The simulator slice is a universal x86_64 + arm64 Mach-O with a minimum of
iOS 15, carrying the engine, the XPath layer, XFDOM, the SVG renderer and
the rich-text converter, and linking **Foundation, CoreFoundation,
CoreGraphics and CoreText only**. No AppKit, no UIKit. CI asserts that
shape on every run rather than trusting the exclusion lists, and runs both
suites in the simulator on a device it resolves by UDID (naming a model
would pin the job to an Xcode version).

### Phase 5 — The UIKit form (≈2–3 weeks) — **design decided**

Not a transliteration of the AppKit layout. That layout is a fixed-width
two-column form — `kWrapWidth` 620, a 110pt label column beside a 280pt
field column, `kIndent` per nesting level, and a canvas that sizes to its
content so the host scrolls both ways. On a 390pt phone that is sideways
scrolling from the first row, and sideways scrolling is the one thing a
mobile form must not do.

**The target is the iOS form idiom, as [XLForm](https://github.com/xmartlabs/XLForm)
renders it** (MIT, ~5.7k stars, still maintained): a grouped
`UITableView`, one control per row, vertical scrolling only. XLForm is a
reference and a design target, not a dependency — it carries its own form
model (descriptors, validators, NSPredicate visibility), and XForms
already has a far stronger one in bindings and MIPs. Layering the two
would put two form engines in the same app.

Reading its cells, every control it uses is stock UIKit, and the
arrangements reduce to three idioms:

| Our control | Cell content | Placement |
| --- | --- | --- |
| `xf:input` (text, number, email, URL) | `UILabel` + `UITextField` | subviews of `contentView` |
| `xf:secret` | `UITextField`, `secureTextEntry` | `contentView` |
| `xf:textarea` | `UILabel` + `UITextView` | `contentView` |
| boolean `xf:input` | `UISwitch` | cell `textLabel` + switch as **`accessoryView`** |
| `xf:select1` (`minimal`) | `UIPickerView` | picker as the cell's **`inputView`**; value in `detailTextLabel` |
| `xf:select1` (`full`, few items) | `UISegmentedControl` | `contentView` |
| `xf:select1` / `xf:select` (`full`, many) | one row per item | `textLabel` + `UITableViewCellAccessoryCheckmark` |
| date / time / dateTime `xf:input` | `UIDatePicker` | **`inputView`**, or an inline row below holding the picker |
| `xf:range` | `UISlider` or `UIStepper` + `UILabel` | `contentView` |
| `xf:trigger`, `xf:submit` | *(nothing)* | `textLabel`, optional disclosure |
| `xf:output` (text) | *(nothing)* | `UITableViewCellStyleValue1` |
| `xf:upload` | *(nothing)* | `textLabel` + disclosure → document picker |
| `xf:repeat` | multivalued section | its add / remove / reorder ARE `xf:insert` / `xf:delete` |
| `xf:group` | section, label as header | |

Worth noticing: a third of those cells add no control at all — a stock
cell's `textLabel`, `detailTextLabel` and accessory carry them. The
`inputView` idiom is the one that makes pickers work without changing row
heights: the row shows a value and the wheel rises where the keyboard
would. Field-to-field navigation comes from an `inputAccessoryView`
toolbar on the base cell, which replaces the key-view loop.

**What the idiom has no answer for, and we do:** `xf:output` with an image
or SVG, and arbitrary host markup — prose, `<table>`, mixed content. Those
get a markup cell that renders a run of host nodes through the portable
layout pass at a measured height, with `XFSVGDocument` drawing into its
`CGContext`. That is the escape hatch XLForm lacks, and it is why the
layout extraction still matters: it serves markup runs and measurement
rather than the whole canvas.

**The known hard parts**, none of which XLForm solves for us:

- **Nesting.** XForms groups nest arbitrarily; a table view has two
  levels. Nested groups flatten to indented header rows, or push a
  sub-screen.
- **Cell reuse versus control identity.** Our controls are long-lived
  objects carrying value, focus and MIP state; cells recycle. The
  controls stay the source of truth and cells become pure views bound at
  `cellForRowAtIndexPath:`.
- **Churn.** Every recalculate can change relevance and readonly, so rows
  appear and vanish constantly; that wants batch updates, or focus and
  scroll position jump.

**Status: the form renders and edits.**
`Sources/XFormsKit/UIKit/` holds two halves:

- `XFFormRows` — the host tree flattened into sections and rows. Portable:
  it names no view framework, so it builds and is tested on all three
  platforms, and the same rows would drive any renderer.
- `XFFormViewController` — the grouped table view and its cells.

Implemented: text field, switch, segmented, check, selector (with its
pushed options screen), date, slider, button, value, markup. Every write
goes through the engine entry point the AppKit widgets already use —
`setValue:ofControl:`, `selectValue:`, `toggleValue:`, `commitDateValue:`,
`commitNumericValue:` — so the two front ends cannot drift in what they
mean by an edit.

The two appearances split the way XForms defines them. `minimal` means the
options are not on the form: the row shows the choice and pushes a screen
of them. `full` means they all are: a `UISegmentedControl` for a handful,
one checkmarked row each beyond that. A single select PICKS rather than
toggles, or tapping the chosen item would leave it with nothing.

Every row kind in the inventory is implemented, upload and markup
included. Markup renders prose with Dynamic Type styles taken from the
host tags, and draws SVG through the portable `XFSVGDocument` — the same
renderer the AppKit widget uses, so a chart is identical on both.

An image `xf:output` gets a row that draws the picture: sent to the value
cell it printed the base64. A control-free host `<table>` gets a row that
**transposes** it into "Header value" blocks rather than drawing a grid —
columns on a phone are the sideways-scrolling problem in miniature, and a
form that scrolls sideways is what this whole layer exists to avoid. A
table that HOLDS controls is walked into instead, so each control keeps an
editable row; rendering it as text would have lost them silently.

Two things learned in the simulator that are not obvious:

- **`sendActionsForControlEvents:` does nothing in a host-less iOS test.**
  It routes through UIApplication, and a logic-test bundle has none; the
  action silently never fires, which reads exactly like a wiring bug. The
  tests walk `allTargets` and invoke the registered action instead, which
  still proves the wiring and the handler.
- The host tree keeps inter-element whitespace deliberately, so a naive
  flattening puts an empty markup cell between every pair of controls.

Exit: `Samples/hello.xhtml` and the kaldi onboarding form are usable end
to end in the Simulator, scrolling vertically only.

### Phase 6 — iOS interaction gaps — **done**

Upload and host `<table>` rendering were listed here and shipped in phase
5 instead.

**Done:**

- **xf:hint and xf:alert.** AppKit shows both as hover badges, which a
  phone has no gesture for. XLForm's answer is a `UIAlertController` when
  the form is submitted, which says nothing while a field is being filled
  in — and XForms' validity is live, not a submit-time verdict. So each
  gets a footnote row under its control: secondary grey for a hint, red
  for an alert while the control is invalid, appearing and disappearing as
  the MIP changes. That is what Settings and Apple's own sign-up forms do,
  which is the "blend in" test.

  A row rather than a second line inside the cell: the cells mix
  `UITableViewCell`'s own `textLabel` with custom constraints, and a label
  anchored beneath both fights whichever laid out first. The note row
  carries no separator, so it reads as part of the row above.

- **Prose with controls in it flows as a line** (`XFInlineFlowView`),
  which was phase 3's deferred half. `<p><xf:output ref="@firstname"/>
  <xf:output ref="@lastname"/> <xf:trigger><xf:label>Show
  Books</xf:label></xf:trigger></p>` — the writers sample — reads as a
  name followed by a button, and is drawn that way: words and widgets
  share lines and wrap at the edge of the row. Giving each control a
  full-width row turned that sentence into three disconnected rows.

  A block is not all one thing, so the decision is per RUN rather than
  per block: maximal runs of inline material become one flowed line
  each, and anything block-level between them is laid out as it would be
  anywhere else. That matters for the same sample, whose `<p>` ends with
  the empty `xf:group` a subform embeds into — an all-or-nothing rule
  rejected the whole paragraph because of it. Two deliberate
  exceptions: prose with NO controls stays with the markup run, so a
  paragraph split by a control still reads as one piece; and a lone
  control with no words around it is not a sentence, so it keeps the
  ordinary labelled row a phone form wants for a field.

  Words are placed one at a time, because a widget can sit mid-sentence
  and the text either side has to break around it. Blocks without
  controls never reach here — one label lays those out properly — so the
  pieces stay few. The row answers its own height through
  `-systemLayoutSizeFittingSize:`, the hook the table view uses for an
  automatic row height: a flowed line's height depends on the width it is
  given, which an intrinsic content size cannot express.

  The widget factory is shared with the table grid, so a trigger in a
  table cell and the same trigger in a sentence are one button with one
  behaviour.

- **A host `<table>` is a real grid** (`XFTableGridView`), not a list of
  its cells. It used to be transposed into a block of "Title value" text
  when it held no controls, and flattened to one row per cell when it
  did — which broke every form whose table IS the layout: the
  calculator's keypad became twenty rows of one button, and a spreadsheet
  lost its columns.

  Any host table now renders as a grid, driven by the same portable
  `XFTableModel` that feeds AppKit's `NSTableView` — one model, two
  renderers, so the two platforms agree about what a cell contains
  (including the unwrapping of a block-level wrapper down to the single
  control inside it).

  Columns take their natural widths and share out any slack; when the
  total does not fit, **that one table scrolls horizontally inside its own
  row**. The form itself still only ever scrolls vertically, which was the
  point of the whole layout; a single wide table moving under the finger
  is the iOS answer for content that cannot be narrowed, and beats
  squeezing ten columns into a phone's width.

  Laid out by hand rather than with nested stack views, for two reasons:
  columns have to line up ACROSS rows, which stacks do not do, and the
  height has to be known at BIND time — a self-sizing cell is measured
  before it is laid out, so a height discovered during layout arrives too
  late and the row is left at the minimum with everything below the first
  line clipped. Measuring at the natural column widths makes the answer
  independent of the row's width.

- **A minimal hint is the placeholder**, per XSLTForms, and is not
  repeated in a note row.

- **xf:textarea is a real multi-line field**, and a rich one where the
  control asks for `mediatype="application/xhtml+xml"` (§8.1.5, the
  TinyMCE sample). Both kinds shared the one-line `UITextField` at first,
  which made a rich textarea show its markup as tags for the user to
  hand-edit — the wrong content, offered the wrong way. The editor now
  converts through `XFRichText`, the same converter the AppKit editor
  uses, so a document round-trips identically on either platform, and the
  keyboard bar carries bold / italic / underline for the selection, since
  iOS has no menu bar to hang formatting on.

  `xf:output` with that mediatype renders its markup too, instead of
  printing the tags. The TinyMCE sample shows the same value twice, with
  and without the mediatype, and the two must not look alike.
- **xf:message and xf:help** present a `UIAlertController` — here XLForm's
  idiom is the right one, because a message IS a modal interruption. A
  message that carries markup gets a Done sheet instead (below).
- **Rich text in hint / alert / help / message.** XForms 1.1 gives all
  four the label's content model (§9.3.1): text, inline host markup, AND
  `xf:output`. The engine had been flattening all of it, so a form
  writing `Enter your <b>full</b> name` showed plain text on every
  platform, and — the sharper bug — an `xf:output` inside a hint or alert
  contributed *nothing at all*, because those were read by flattening the
  element rather than by walking it.

  Both are fixed in the portable half, in `XFMarkupParts`: each support
  child is split once at load into literal parts and `xf:output` holes,
  and joined again on every refresh, exactly as `XFControl`'s label parts
  already were. Each child yields two joins — the plain text every host
  can show (`hint`, `alert`, `help`) and, only where the form wrote
  formatting, the markup a host that draws XHTML shows instead
  (`hintMarkup`, `alertMarkup`, `helpMarkup`). An output's value is
  escaped into the markup unless it declares an XHTML mediatype, so an
  instance value holding `<` stays text.

  Presentation is per platform, over the shared `XFRichText` converter:
  iOS renders the note row's markup as an `NSAttributedString` in its
  `UILabel`, and shows a rich `xf:message` in a sheet with a read-only
  `UITextView` (`UIAlertController` has no public attributed-message
  API, and reaching into its label is private). AppKit puts the same
  content in a non-editable, non-selectable `NSTextView`
  (`+[XFRichText displayViewWithMarkup:font:maxWidth:textColor:]`, sized
  to fit) — inside the hint/alert hover box, and as the accessory view of
  the message and help alerts.

  `xf:message` reaches the host through a new optional
  `richMessageHandler(markup, text, level)`; a host that does not set one
  keeps getting `messageHandler` with the flattened text, so nothing
  changes for a host that cannot draw markup.
- **xf:setfocus** scrolls to the row and makes its field first responder.
- **incremental="true" for text**, debounced by `@delay`. Only the
  focus-loss event had been bound, so incremental silently did nothing on
  iOS while working on macOS.

  Committing on every keystroke means the form is rebuilt on every
  keystroke, and a rebuilt cell is not the one holding the keyboard. Two
  rounds were needed to make that harmless. First, an unchanged form
  re-binds its visible cells in place instead of reloading. Then the case
  that actually bites: an `xf:alert` note row appears or disappears as the
  value goes in and out of validity — typing the "@" of an email address
  makes it valid, drops the alert row, and the reload that followed took
  the keyboard with it, so the field stopped accepting input mid-word.
  Such a change is now applied as row insertions and deletions
  (`performBatchUpdates:`), which leaves every cell UIKit does not touch —
  the editor among them — exactly as it was. The new sections are adopted
  INSIDE the update block, since the table reads the old counts to apply
  the diff and the new ones to draw the result.

- **Dates are shown in the reader's locale** (`XFDateDisplay`, portable).
  An `xsd:date` node holds `2025-01-01` and must keep it — that lexical
  form is the value that calculates, comparisons and submissions depend
  on — but it is not what a host should print. The date pickers were
  already localized on both platforms; the read-only paths were not, so
  an `xf:output` of a date showed the raw value on iOS AND on macOS. Both
  go through the helper now. A value that does not parse is left as
  typed, so a half-entered date is never shown as a guess.

- **Field-to-field navigation** is a toolbar above the keyboard
  (`inputAccessoryView`) with previous / next / Done, shared by every
  editable field. It replaces the key-view loop, which a phone has no Tab
  to drive: without it the only way to the next field is to dismiss the
  keyboard, scroll and tap. Readonly fields are skipped, and the two
  chevrons disable at the ends of the form. Taking the keyboard now also
  moves the ENGINE's focus (`focusControl:fromUI:`), so `DOMFocusIn` /
  `DOMFocusOut` fire on iOS as they do on AppKit.

- **accesskey** becomes a `UIKeyCommand` per control, with ⌘ as the
  modifier — UIKit will not register an unmodified letter while a field
  can be editing, and AppKit's trigger buttons already use ⌘ for the
  same thing. A trigger activates; anything else takes focus, which is
  what XForms 1.1 asks for and what browsers do. The AppKit side gained
  the other half of this at the same time: `-[XFFormView
  performKeyEquivalent:]` focuses a non-trigger control by its accesskey,
  which only buttons could answer before.

- **xf:dialog** is presented as a form sheet holding a second
  `XFFormViewController` pointed at the dialog's group — which is what
  `rootGroup` was for — with a Done button that hides it through the
  engine, so `xforms-dialog-close` fires and a later `xf:show` works. A
  controller with a `rootGroup` no longer installs the processor's host
  hooks: it is a view of a form another controller drives, and taking
  them would leave that form without hooks once the sheet is dismissed.
  Everything modal is now presented from the frontmost sheet, since UIKit
  refuses to present from a controller that is already presenting.

- **Repeat add / remove** is the table's own idiom: swipe a row to delete
  its item, tap the "Add item" row that closes the section to append one.
  A tappable add row rather than the table's insert control, because that
  control only appears in editing mode and this form has no Edit button —
  Contacts and Settings add rows the same way.

  Both go through `-[XFRepeat insertItemAfterPosition:]` /
  `-deleteItemAtPosition:`, new and portable: the narrow case of §10.3 /
  §10.4 where the nodeset is the repeat's own and the position is known,
  so nothing is evaluated. Everything after that is what `xf:insert` and
  `xf:delete` do — dispose the bindings, mutate the instance, mark the
  model rebuilt, dispatch `xforms-insert` / `xforms-delete`, rebuild the
  items and move the index — inside one deferred-update action, so a
  form whose binds depend on the nodeset recalculates exactly once. A
  form's own add/remove triggers keep working unchanged; this is an
  affordance, not a capability.

  `XFFormRow` now carries the `repeat` and the 1-based `repeatPosition`
  it came from, so a gesture on a row knows which node it acts on. A
  nested repeat tags its rows first and is not overwritten: the innermost
  repeat owns the row, which is the one a swipe on it means.

### Phase 7 — Host app and CI — **done**

`Apps/XFormsMobile` is the iOS host: pick a form document, fill it in.

Deliberately that and no more. XForms is a client for a form SERVER —
submissions, `xf:load`, instances fetched over HTTP — and there is no
server to point this at yet, so the useful thing a host can do today is
open a document from the file system and hand it to the engine and the
UIKit form layer.

- `XFFormBrowserViewController` is the first screen: the bundled sample
  forms as a list, and a folder button opening a
  `UIDocumentPickerViewController` over `.xhtml` / XML / HTML for
  anything else. Either pushes an `XFFormViewController` onto the
  navigation stack, so the back button closes it. A form the engine
  rejects raises an alert carrying the engine's own reason — which
  element or expression is at fault — rather than a flat "could not
  open".
- `Samples/` is bundled, as the macOS viewer bundles it for File ▸ Open
  Sample. A folder REFERENCE, not a group: several forms pull in a
  sibling resource (`counties.xml`, `flag.svg`, `textarea.css`), which
  only resolves if the directory is copied whole. Without it the app is
  unusable on a fresh simulator, where the Files app starts empty — a
  picker with nothing to pick. `UIFileSharingEnabled` puts the app's
  Documents folder in Files too, so a form of your own can be dropped in
  and picked.
- `XFMobileForm` owns one opened document: the processor, the file, and
  that file's read access. A picked URL is security-scoped, and the scope
  has to outlive the read that builds the processor — `xf:instance src=`,
  a schema, a submission reading a resource beside the document can all
  reach back to the file — so it is released in `-dealloc` rather than
  after loading. The base URL rides in with the source, since relative
  resources resolve during construction.
- Forms also arrive from other apps: the Info.plist declares the
  document types and `LSSupportsOpeningDocumentsInPlace`, and
  `application:openURL:options:` opens them through the same path.
- No storyboard and no scene manifest — an empty `UILaunchScreen`
  dictionary and a window from the app delegate.

CI builds the app for the simulator on the portable leg of the matrix. A
device build is not attempted: signing an app needs an identity the
runner has no reason to hold, and the framework's `iphoneos` slice
already covers the linker constraints.

`XFMobileForm` and the browser are compiled into the framework's test
bundle as well, so the loading path and the push are tested rather than
only built (`XFMobileAppTests`); the browser is excluded on macOS, where
there is no UIKit.

## Effort

| Phase | Work | Estimate |
| --- | --- | ---: |
| 0 | Module split | **done** |
| 1 | Portable DOM (clean-room `XFDOM*`) | **done** |
| 2 | Portable SVG (Core Graphics + Opal) | **done** |
| 3 | Portable text + inline flow | **done** |
| 4 | iOS Core green | **done** (735 tests green on iOS) |
| 5 | UIKit form (table-view cells) | **done** |
| 6 | iOS interaction gaps | **done** |
| 7 | Host app + CI | **done** |
| | **Total** | **11–16 weeks** |

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
