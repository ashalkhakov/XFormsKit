# iOS port: inventories and mappings

Reference tables for [ios-port-plan.md](ios-port-plan.md). Measured
from `master` at the time of writing.

> **The iOS column is superseded.** It was written assuming iOS would get
> a transliteration of the AppKit layout — a scrolling canvas of absolutely
> placed widgets. It will not: the iOS form is a grouped `UITableView`, one
> control per row, and the controls live inside cells. The cell inventory
> that replaces this column is in
> [ios-port-plan.md](ios-port-plan.md) under phase 5. What is still
> accurate and still useful here is §2 (AppKit idiom → UIKit idiom), §3
> (the upload API change), §4 (the XML DOM surface) and §5 (the file
> dispositions).

## 1. Control → AppKit → UIKit

Source of truth for the AppKit column:
[XFFormView+Widgets.m](../Sources/XFormsKit/AppKit/XFFormView+Widgets.m) and
[XFFormView+Layout.m](../Sources/XFormsKit/AppKit/XFFormView+Layout.m).

| XForms control | Today (AppKit) | iOS (UIKit) | Notes |
| --- | --- | --- | --- |
| `xf:input` (text) | `NSTextField` editable | `UITextField` | `@placeholder`, numeric right-align and `@cols` all have direct equivalents |
| `xf:input` (boolean) | `NSButton` / `NSSwitchButton` | custom checkbox `UIButton` | `UISwitch` is the idiomatic control but is 51pt wide and breaks the row grid; an SF Symbol `checkmark.square`/`square` button matches the existing layout |
| `xf:input` (date/time/dateTime) | `NSDatePicker`, text-field-and-stepper | `UIDatePicker` | `.date` / `.time` / `.dateAndTime`; `.compact` style (iOS 14+) fits the row height, `.wheels` does not |
| `xf:secret` | `NSSecureTextField` | `UITextField.secureTextEntry` | direct |
| `xf:output` (text) | `NSTextField` non-editable | `UILabel` | direct |
| `xf:output` (HTML) | `NSTextField` + attributed string | `UILabel` + attributed string | the converter is the project's own ([XFRichText.m](../Sources/XFormsKit/AppKit/XFRichText.m)), no WebKit either side |
| `xf:output` (image) | `NSImageView` | `UIImageView` | `NSImage` → `UIImage`; the natural-size-with-cap sizing logic ports as is |
| `xf:textarea` | `NSTextView` in `NSScrollView` | `UITextView` | `UITextView` scrolls itself — the scroll view wrapper disappears |
| `xf:textarea` (rich) | `XFRichTextEditor` | new `UITextView` subclass | ~390 lines; toolbar becomes an `inputAccessoryView` |
| `xf:trigger` / `xf:submit` | `NSButton` rounded bezel | `UIButton` (`.system`) | `appearance="minimal"` → borderless, same as today |
| `xf:trigger` `@accesskey` | `setKeyEquivalent:` | `UIKeyCommand` | hardware keyboard only (iPad, Simulator) |
| `xf:range` | `NSSlider` | `UISlider` | no `altIncrementValue` on iOS — quantise to `@step` in the action; `setContinuous:` → `isContinuous`, non-incremental commit on `.touchUpInside` |
| `xf:select1` (default/minimal) | `NSPopUpButton` | `UIButton` + `UIMenu` (iOS 14+) | option groups become `UIMenu` sections; the blank-first-item rule for an unknown value carries over |
| `xf:select1` (`full`) | `NSButton` / `NSRadioButton` rows | custom radio `UIButton` rows | UIKit has no radio button; SF Symbols `circle` / `inset.filled.circle`. `UISegmentedControl` is tempting for 2–3 items but cannot show group labels |
| `xf:select` (`full`) | `NSButton` / `NSSwitchButton` rows | custom checkbox rows | as the boolean input |
| `xf:select`/`select1` (`compact`) | `NSTableView` list box + `XFListBoxAdapter` | `UITableView` with `.multipleSelection` | the adapter's data-source shape maps over nearly unchanged |
| `xf:group` | `NSBox` with title | `UIView` + `CALayer` border + `UILabel` | `NSBox`'s `titlePosition` behaviour is ~15 lines to reproduce |
| `xf:repeat` | rows in the same canvas | same | pure layout, no widget |
| `xf:switch` / `xf:case` | selected case laid out | same | pure layout |
| `xf:upload` | `NSButton` → `NSOpenPanel` | `UIButton` → `UIDocumentPickerViewController` | **API change**: modal/synchronous becomes presented/async; see §3 |
| host `<table>` | `NSTableView` + [XFTableAdapter](../Sources/XFormsKit/AppKit/XFTableAdapter.m) | plain `UIView` grid | recommended: keep `XFTableModel`'s computed grid and lay cells out as ordinary subviews. A `UITableView` nested in the form's scroll view buys nothing and costs a lot |
| hint/help/alert badges | `XFBadgeView` + tracking areas | tap-to-popover | no hover on iOS; `UIHoverGestureRecognizer` can add pointer support on iPad |
| `view.toolTip` | native | `accessibilityHint` + popover | no tooltips on iOS |
| SVG | [XFSVGView](../Sources/XFormsKit/AppKit/XFSVGView.m) | same renderer on Core Graphics | see plan phase 2 |

## 2. AppKit idiom → UIKit idiom

| Concern | AppKit (today) | UIKit |
| --- | --- | --- |
| Coordinates | `isFlipped = YES` ([XFFormView.m:220](../Sources/XFormsKit/AppKit/XFFormView.m#L220)) | native top-left — **layout arithmetic ports unchanged** |
| Scrolling | host wraps the view in `NSScrollView` | `UIScrollView` + `contentSize` from the layout pass |
| Actions | target/action (`buttonClicked:`, `sliderChanged:`, `popupChanged:`, `checkClicked:`, `boolClicked:`, `dateChanged:`) | `addTarget:action:forControlEvents:` — same selectors, new registration |
| Text editing | `controlTextDidChange:` / `DidEndEditing:` notifications ([XFFormView+Editing.m](../Sources/XFormsKit/AppKit/XFFormView+Editing.m)) | `UITextFieldDelegate` / `UITextViewDelegate` + `.editingChanged` |
| Incremental commit | `NSTimer` coalescing (already platform-neutral) | unchanged |
| Focus / tab order | key-view loop, `makeFirstResponder:` | `becomeFirstResponder` + a prev/next `inputAccessoryView` toolbar |
| Enabled state | `setEnabled:` on `NSControl` | `isEnabled` / `isUserInteractionEnabled` |
| Fonts | `NSFont`, `NSFontManager convertFont:toHaveTrait:` | `UIFont`, `UIFontDescriptor withSymbolicTraits:` |
| Text measurement | `sizeWithAttributes:` | identical API on iOS |
| Colors | `NSColor` | `UIColor` |
| Drawing | `NSBezierPath`, `NSAffineTransform`, `NSGradient`, `NSGraphicsContext` | `CGPath`, `CGAffineTransform`, `CGGradient`, `CGContext` — `NSAffineTransform` and `NSGradient` **do not exist on iOS** |
| Attributed strings | `NSFontAttributeName`, `NSUnderlineStyleAttributeName` … | identical names on iOS |
| HTTP | `NSURLConnection` | `NSURLSession` (transport is already pluggable) |
| Digests | `CommonCrypto` under `#if defined(__APPLE__)` | same, unchanged |

## 3. The one API addition the port forces

Everything else is internal, but file upload cannot be:
[XFFormView+Widgets.m:388](../Sources/XFormsKit/AppKit/XFFormView+Widgets.m#L388)
calls `[panel runModal]` and returns the chosen file synchronously.
UIKit has no modal run loop — a document picker must be *presented* from a
`UIViewController` and answers through a delegate.

The UIKit form view therefore needs a presenting hook, e.g.

    @property (nonatomic, weak) UIViewController *presentationContext;

and `uploadClicked:` becomes asynchronous: present, return, and commit the
value in the picker's delegate callback. Worth mirroring on macOS as a
completion-block API so both platforms share one flow.

## 4. XML DOM surface the engine actually uses

What `XFDOM*` must implement, measured across `Sources/XFormsKit/**`.
Counts are grep hits, including some collisions with ordinary
identifiers (`name`, `index`, `level`, `prefix`); the *set* is what
matters.

**Constructors** — `NSXMLDocument initWithXMLString:options:error:`,
`initWithData:options:error:`, `initWithRootElement:`;
`NSXMLElement elementWithName:`, `initWithName:`;
`NSXMLNode attributeWithName:stringValue:`,
`namespaceWithName:stringValue:`, `textWithStringValue:`.

**Tree** — `parent`, `children`, `childCount`, `childAtIndex:`,
`nextSibling`, `previousSibling`, `index`, `level`, `rootElement`,
`setRootElement:`, `addChild:`, `insertChild:atIndex:`,
`removeChildAtIndex:`, `detach`, `copy` / `mutableCopy` (deep).

**Names** — `name`, `localName`, `prefix`, `URI`, `kind`
(`NSXMLElementKind`, `NSXMLAttributeKind`, `NSXMLTextKind`,
`NSXMLDocumentKind`, `NSXMLCommentKind`, `NSXMLProcessingInstructionKind`).

**Attributes and namespaces** — `attributes`, `attributeForName:`,
`addAttribute:`, `removeAttributeForName:`, `namespaces`,
`addNamespace:`, `namespaceForPrefix:`, `resolveNamespaceForName:`.

**Values and serialization** — `stringValue`, `setStringValue:`,
`XMLString`, `XMLStringWithOptions:`, `setVersion:`,
`setCharacterEncoding:`, the `NSXMLNodePreserveWhitespace` and
`NSXMLNodeIsCDATA` options.

Most of this is already implemented, in W3C-DOM spelling, by the DOM
being lifted from the previous project — see
[ios-port-dom-lift.md](ios-port-dom-lift.md) for what maps directly and
what the compatibility facade has to absorb (namespaces-as-attributes,
whitespace defaults, kind constants, `index` / `level` / `detach`).

**To delete rather than implement** — `nodesForXPath:`, used once at
[XFModel.m:272](../Sources/XFormsKit/XFModel.m#L272) and replaceable with the
project's own XPath engine or a two-line walk.

### Semantics that must match, not just compile

These are what the W3C suite will catch, and where the phase-1 estimate
spread comes from:

- `XMLString` escaping and attribute quoting, and where namespace
  declarations are emitted on serialization
- deep `copy` — `xf:insert`'s origin clone depends on it
- `detach` leaving a node usable and re-insertable
- document order and `index` / `level` (XPath axes and `indexOfObjectIdenticalTo:`)
- whitespace preservation — [XFXML.m](../Sources/XFormsKit/XFXML.m) has a
  `XFPreserveBodyWhitespace` path for host markup
- **stable object identity per node** — `XFNodeState` hangs MIP state off
  the node with `objc_setAssociatedObject`
  ([XFNodeState.m:28](../Sources/XFormsKit/XFNodeState.m#L28))

## 5. File-by-file disposition of `AppKit/`

| File | Lines | Disposition |
| --- | ---: | --- |
| [XFFormView.m](../Sources/XFormsKit/AppKit/XFFormView.m) | 924 | split: widget registry / badges / focus → per platform; design-introspection (`layoutFrameOfControl:`, `controlAtPoint:`) → portable once frames come from the layout pass |
| [XFFormView+Layout.m](../Sources/XFormsKit/AppKit/XFFormView+Layout.m) | 637 | ~80% becomes the portable layout pass; the rest is view instantiation |
| [XFFormView+Widgets.m](../Sources/XFormsKit/AppKit/XFFormView+Widgets.m) | 405 | per platform — this is the widget factory, table §1 |
| [XFFormView+Editing.m](../Sources/XFormsKit/AppKit/XFFormView+Editing.m) | 399 | per platform, but the commit logic (incremental timers, `commitControl:value:`) lifts into shared code |
| [XFTableAdapter.m](../Sources/XFormsKit/AppKit/XFTableAdapter.m) | 461 | replaced by a plain view grid on iOS; `XFTableModel` (engine) unchanged |
| [XFRichTextEditor.m](../Sources/XFormsKit/AppKit/XFRichTextEditor.m) | 392 | rewritten on `UITextView` |
| [XFRichText.m](../Sources/XFormsKit/AppKit/XFRichText.m) | 380 | portable after the font abstraction; moves to Core |
| [XFSVGView.m](../Sources/XFormsKit/AppKit/XFSVGView.m) | 1,404 | parse + render tree + hit test → Core on Core Graphics; `drawRect:` host per platform |
| [XFAppKitPriv.h](../Sources/XFormsKit/AppKit/XFAppKitPriv.h) | 277 | splits alongside the above |
