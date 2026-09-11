# Lifting the DOM from the previous XFormsKit

Assessment of reusing the Objective-C DOM in
`/Volumes/ExtraSSD/Projects/XFormsKit` (the previous iteration of this
project) as the portable XML tree this port needs. Companion to
[ios-port-plan.md](ios-port-plan.md), which explains why a portable DOM is
the critical path: `NSXMLDocument` / `NSXMLElement` / `NSXMLNode` do not
exist on iOS.

> **Decision: not adopted.** The DOM is being written clean-room instead,
> as `XFDOM*` in [Sources/XFormsKit/DOM/](../Sources/XFormsKit/DOM/) — no
> ESXML, no Xfolite translation. This assessment is kept because its
> measurements still hold and explain the choice: the lift would have
> saved roughly a week of typing while inheriting a broken serialiser, a
> W3C-DOM API the engine cannot call, and three semantic gaps that the
> facade would have had to paper over anyway. Writing to the NSXML shape
> directly skips the facade entirely. The gap analysis in §"Semantic gaps"
> became the specification for the new implementation's tests.

**Original verdict: yes, lift it.** The tree, the namespace model and the parser
are sound and land on iOS almost untouched. The serializer has to be
rewritten, and an NSXML-shaped facade has to go on top. That is a
meaningful head start on the riskiest part of the port — though less of a
schedule saving than it first looks, because the facade and serialization
fidelity are where most of the work lives either way.

## What is there

`XFormsKit/DOM/` — 1,864 lines across 12 class pairs:

    DOMNode  DOMElement  DOMAttr  DOMNamedNode  DOMCharacterData
    DOMText  DOMCDATASection  DOMComment  DOMDocument
    DOMParser  DOMSerializer  DOMError

A W3C-DOM-shaped implementation (`nodeType`, `childNodes`,
`appendChild:error:`, `cloneNode:`, `lookupNamespaceURI:`,
`getAttributeNS:localName:`, `adoptNode:`). Nodes are real Objective-C
objects under ARC, with `strong` child arrays and `weak` parent/sibling
back-pointers.

`XFormsKitTests/` carries 27 DOM tests (parser, serializer, modification,
document factory) that come along with the lift.

## The spike that was run

Copied `DOM/*.{h,m}` to a scratch directory, made exactly two cuts, and
compiled.

**Cut 1** — `DOMNode.h` imported `../XPath/XPXPathNSResolver.h` and
declared conformance to that protocol. Removed both.

**Cut 2** — `DOMNode` carried a DOM Events tail (`addEventListener:…`,
`dispatchEvent:…`, `notify*EventListeners:`), which pulled in
`../Events/DOMEvent.h`. Removed the declarations and the implementation
block. This project has its own event layer
([XFXMLEvents](../Sources/XFormsKit/XFXMLEvents.h) / `XFListener`), so
none of it is wanted.

Results:

| Check | Result |
| --- | --- |
| Compile, macOS (`arc`, SDK 26) | 12/12 files, 0 errors (warnings only) |
| **Compile, iOS arm64 (iOS 15 target)** | **12/12 files, 0 errors** |
| Parse a namespaced instance | correct: structure, prefixes, namespace URIs, entity decoding |
| `lookupNamespaceURI:@"xf"` from a descendant | correct |
| `cloneNode:YES` | correct, distinct object identity |
| `serializeToXML(…)` | **returns nil for any document with a default namespace** |

Two dependencies beyond Foundation: `NSXMLParser` (present on iOS) for
parsing and `libxml2` (ships on iOS, `-lxml2`) for the serializer's
`xmlTextWriter`. Nothing else — the `external/ESXML` directory in that
project is unrelated and unreferenced by the DOM.

## The one real defect: the serializer

`serializeToXML()` is 111 lines over `xmlTextWriter` and is not usable as
it stands. Measured against five inputs:

| Input | Output |
| --- | --- |
| `<data><a>1</a></data>` | `<data xmlns="">\n  <a xmlns="">1</a>\n</data>` |
| `<data xmlns=""><a>1</a></data>` | **nil** |
| `<data xmlns="urn:x"><a>1</a></data>` | **nil** |
| `<data xmlns:xf="…"><a>1</a></data>` | emits a bogus `xmlns:xmlns="http://www.w3.org/2000/xmlns/"` |

Three separate faults:

1. **Fails on default namespaces.** Every XForms instance has one, so
   this is total for the use case. The cause is that namespace
   declarations are stored as ordinary attributes (see below) and are
   then written back through `xmlTextWriterWriteAttributeNS`, which
   rejects them.
2. **Spurious `xmlns=""` on every element**, from passing an empty
   (non-`NULL`) URI to `xmlTextWriterStartElementNS`.
3. **`xmlTextWriterSetIndent(writer, 1)`** pretty-prints. Indentation
   injected into instance data would corrupt submission output and break
   the W3C suite, which compares serialized instances.

That the serializer is the weak spot is not a surprise in hindsight: it
is the newest and least-exercised file in the directory (its header is
dated 10/31, the rest 9/20–9/21), it is the one piece with no counterpart
to work from — Xfolite serialized through xmlpull's `IXmlSerializer`,
which has no Objective-C equivalent — and its own header carries a TODO
about replacing it after "switching to pure libxml2".

Rewriting it is the right call, and it is also where NSXML parity has to
be earned: `XMLString` escaping, attribute quoting, where namespace
declarations are emitted, and details like Apple's NSXML writing
`<empty></empty>` rather than `<empty/>`. Budget a week including test
iteration, not an afternoon.

## Semantic gaps to close in the facade

The engine is written against NSXML's shapes, not W3C DOM's. None of
these are defects in the lifted code — they are differences the
compatibility layer has to absorb.

| Concern | Lifted DOM | NSXML (what the engine expects) |
| --- | --- | --- |
| Namespace declarations | ordinary attributes in the `xmlns` namespace — `attributeCount` on a root with `xmlns` + `xmlns:xf` is **2** | separate: `attributes` = 0, `namespaces` = 2. `XFSubmission` and `XFHostEdit` depend on the split |
| Whitespace-only text | **preserved** — `<data>\n <a>1</a>\n</data>` has 5 children | hidden — 2 children. The engine compensates with `<!--xf:ws-->` markers ([XFProcessor.m:73](../Sources/XFormsKit/XFProcessor.m#L73)); the facade must strip by default or that hack double-counts |
| Node kind constants | W3C (`ELEMENT_NODE` = 1, `TEXT_NODE` = 3) | `NSXMLElementKind` = 2, `NSXMLTextKind` = 7 — mechanical mapping |
| Processing instructions | not implemented (no class, no parser callback) | `NSXMLProcessingInstructionKind`, used twice in the engine |
| Document children | `childCount` counts only the root element; comments outside the root are appended but not counted | document children include comments and PIs |
| Position | no `index` / `level` | both used, incl. by XPath document order |
| Detach | `removeChild:error:` on the parent | `detach` on the node itself, used 42 times |

The good news on the whitespace row: the lifted DOM keeps whitespace-only
text nodes *natively*, which is exactly what the `<!--xf:ws-->` marker
hack was invented to work around. Once the portable DOM is the only DOM,
that workaround can be deleted — a cleanup, not part of this port.

## Work items

| # | Item | Size |
| --- | --- | ---: |
| 1 | Lift `DOM/*` into `Sources/XFormsKit/DOM/`, rename `DOM*` → `XFDOM*`, apply the two cuts, drop the `elementParsed:` / `childrenParsed:` XForms callbacks (the previous author's own TODO) and the parser's two calls to them | 2 d |
| 2 | Processing instructions, document-level children, `index` / `level`, `detach` | 2–3 d |
| 3 | Rewrite the serializer for NSXML `XMLString` parity | 1 w |
| 4 | NSXML-compatibility facade: ~30 selectors, kind mapping, the namespaces/attributes split, NSXML whitespace default, the 10 factory methods | 1–1.5 w |
| 5 | Rename ~1,200 engine references behind `XF_PORTABLE_DOM`; get the existing 630 engine tests green in both configurations | 1 w + tail |
| 6 | Port the 27 DOM tests from the old project | 0.5 d |

**Revised phase 1: 2–3.5 weeks** (was 2–4 greenfield). The honest read:
the lift saves perhaps a week of typing, and its real value is that the
subtle part — a correct namespaced tree with clone and namespace lookup,
already exercised by 27 tests — exists and is known to work. Items 3, 4
and the item 5 tail are unchanged by the lift and still dominate.

## Before lifting

- **Provenance.** Per the author, the DOM implementation is his own work,
  originally seeded from another pre-existing iOS DOM project and then
  rewritten. What was translated from
  [Xfolite](https://github.com/okoskimi/Xfolite) — Nokia's J2ME XForms
  client — is mainly the XPath engine, the MIPs and the incremental
  evaluation machinery, not the DOM.

  The DOM's *API shape* does follow Xfolite's
  `com.nokia.xfolite.xml.dom` closely, which is what one would expect
  given it had to interoperate with the parts that were translated: the
  class set matches one for one (`Node`, `Element`, `Attr`, `NamedNode`,
  `CharacterData`, `Text`, `CDATASection`, `Comment`, `Document`), as do
  the `elementParsed` / `childrenParsed` / `removingElement` lifecycle
  (Xfolite has a `WidgetFactory` and a `ParseListener` that explain the
  "widget factory" wording), the `NodeFilter` forward declaration, and
  the `XPathNSResolver` conformance that had to be cut for this lift.

  Licensing is comfortable either way: Xfolite is
  "Copyright (c) 2010 Nokia Corporation and/or its subsidiary(-ies)",
  LGPL-2.1-**or-later**, and this project is LGPL-2.1, so anything
  derived from it can be carried here as long as the copyright notice
  survives and the translation is marked as a modification. A header on
  the lifted files crediting Xfolite for the design, with Nokia's
  copyright line, costs nothing and settles the question.

- **The other iOS DOM base: identified, and harmless.** It is
  [ESXML](https://github.com/tracy-e/ESXML) — "a DOM based XML Parser for
  Objective-C", **MIT licensed**, Copyright (c) 2013 TracyYih
  (file headers: Copyright (c) 2012 EsoftMobile.com). The old repository
  carries it as a **git submodule** at `external/ESXML`, pinned to
  `4e949c2`, added in the same commit (`965ab07`) that introduced
  `DOM/` — and never referenced since: zero mentions in the sources and
  zero in the Xcode project. Nothing to vendor into this repository.

  What survives from it is shape, not code: the weak `parentNode` /
  `previousSibling` / `nextSibling` back-pointer memory model, the
  selector spellings (`insertBefore:refChild:`, `replaceChild:oldChild:`,
  `removeChild:`, `appendChild:`) and the W3C node-type enum. The
  implementations differ throughout — ESXML's `insertBefore:refChild:`
  works off `_firstChild` / `_lastChild` ivars and neither validates the
  owning document nor handles a nil `refChild`, while the rewrite is
  index-based, checks `ownerDocument` and returns `DOMWrongDocumentErr` /
  `DOMNotFoundErr`. ESXML also has no `Attr`, `NamedNode`,
  `CharacterData`, `CDATASection` or `Comment` classes, no namespace
  support, no `cloneNode:` and no error model, all of which the lifted
  DOM has in the Xfolite shape.

  MIT is compatible with LGPL-2.1, so this raises nothing. A credit line
  naming both ESXML (starting point) and Xfolite (design) on the lifted
  files is accurate and sufficient.

  Note that the history itself will not show the derivation: `DOM/`
  arrived fully formed in `965ab07` ("Various changes.", 72 files,
  7,909 insertions), at essentially its present size.
- **GNUstep.** The facade should build there too, so the portable DOM can
  be tested on all three platforms. Nothing in the lifted code is
  Apple-specific apart from `NSXMLParser` behaviour, which GNUstep also
  provides.
