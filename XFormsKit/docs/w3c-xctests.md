# W3C XForms 1.1 suite as XCTest assertions

`Tests/W3CTests` translates the W3C XForms 1.1 Edition 1 test suite
(TestSuite/XForms1.1/Edition1) case by case into XCTest methods, run with

    make w3ccheck

Each suite form states in its instruction labels what a human tester must
see; the corresponding test asserts that behavior programmatically —
widget state through the real `XFFormView`/`XFControl` layer (values,
relevance, readonly, validity), model state through XPath, and event
behavior through the engine's trace sink (`XFXMLEvents` + a per-test
message handler). Interactions go through the real paths: triggers via
`activateControl:`, edits via `setValue:ofControl:`, selections via
`selectValue:`. No pixels are asserted.

The harness (`XFW3CTestCase`) mirrors `Tools/xftestrun`: host hooks
capturing messages and load requests, a dead transport (non-file URLs
fail instantly — the W3C echo endpoints are long gone; the deliberate
bad-URL cases observe exactly that), plus an opt-in echo transport
(`useEchoTransport`) so replace="instance"/"none" submissions can
SUCCEED offline; URLs containing "invalid" still fail. The trace sink is
installed before load, so construction-time dispatches (model-construct,
exceptions raised while building) are observed even though they predate
the message handler.

## Policy: spec-true, red is information

Assertions state what the SPEC demands. A case the engine gets wrong
stays red — `make w3ccheck` is a conformance report, not a regression
gate; `make check` (the unit bundle) remains the always-green gate.
Fixing a red here is engine work; when it is fixed the test flips green
by itself.

## Conversion status

| Chapter | cases | converted | green | red (engine gaps) |
|---|---|---|---|---|
| 2 Introduction to XForms | 4 | 4 | 4 | 0 |
| 3 Document Structure | 37 | 37 | 28 | 9 |
| 4 Processing Model | 67 | 66 (4.5.3.a absent upstream) | 56 | 10 |
| 5 Datatypes | 15 | 15 | 15 | 0 |
| 6 Model Item Properties | 11 | 11 | 9 | 2 |
| 7 XPath Expressions | 62 | 62 | 50 | 12 |
| 8 Form Controls | 59 | 59 | 53 | 6 |
| 9 Container Form Controls | 21 | 21 | 16 | 5 |
| 10 XForms Actions | 70 | 70 | 70 | 0 |
| 11 The XForms Submit Module | 85 | 85 | 85 | 0 |
| B Insert/Delete Recipes | 15 | 15 | 15 | 0 |
| G XForms 1.1 CSS | 10 | 10 | 9 | 1 |
| H Complete Examples | 3 | 3 | 2 | 1 |

The first gap-fix round (mac state 76) closed the chapter 10, 11, 2, B
and H gaps wholesale — the fixed families are struck through below with
a note on the fix; what remains open is the exception-raising family and
assorted singletons in chapters 3, 4, 6, 7, 8, 9 and G.

Chapter 1 ("Differences between XForms 1.1 and 1.0") defines no forms of
its own: its manifest's 43 cases are all cross-references into chapters
3, 5, 7, 8, 10 and 11, each already asserted by that chapter's class —
so there is no chapter-1 test file, and the suite is fully converted.

## Open engine gaps the red tests document

Chapter 3: label/`@src` content not loaded (3.2.2.a, non-normative);
invalid `model` IDREF raises no xforms-binding-exception (3.2.3.f — the
invalid `bind` IDREF case 3.2.3.e works); itemset `@bind` yields no items
(3.2.4.a, 3.2.4.c) and itemset bad model/bind IDREFs raise nothing
(3.2.4.e/f); lazy authoring — a document with no xf:model refuses to
load (3.3.1.a2); malformed inline instance (two top-level nodes) is
accepted silently instead of xforms-link-exception (3.3.2.g, 3.3.2.h —
h also wants event('resource-uri') in the handler).

Chapter 4: a space-separated multi-schema `@schema` list raises a
spurious link-exception (4.2.1.b1 — a single schema works); the illegal
lazy-`/car` ref raises no binding-exception (4.2.2.c2); range controls
never dispatch xforms-in-range / xforms-out-of-range (4.4.16/17, also
g.1.e); binding exceptions missing for: invalid `model` IDREF
(4.5.1.a1, 4.7.e2), illegal binding expression `ref="%"` (4.5.1.a5); a
non-compiling calculate hard-fails the load with no
xforms-compute-exception dispatch (4.5.2.a — the known finding); a
failed instance link does not halt processing (4.5.4.a renders "Hello
world!"); unknown output mediatype dispatches no xforms-output-error
(4.5.5.a). **FIXED (ms76)**: xforms-scroll-first on a negative setindex
(4.4.18 — the NSUInteger wrap), the invalid `submission` IDREF
(4.5.1.a3) and the invalid submission `instance` IDREF (4.5.1.a4,
4.7.e3) now raise xforms-binding-exception.

Chapter 6: a readonly node still accepts `setValue:ofControl:` — the
model must refuse the edit, not just gray out the widget (6.1.2.a); an
inline `xsd:schema` simpleType (minLength) is not applied to
`bind/@type` (6.2.1.a).

Chapter 7: a group's `model` attribute does not reroute its children's
context model (7.2.c shows 1, not 3); evaluation errors inside MIP
expressions raise xforms-binding-exception where the spec wants
xforms-compute-exception (7.5.a, 7.8.3.c/d, 7.8.4.c/d/e);
`property('invalid')` raises nothing (7.8.2.c); `current()` inside a
repeat's `value=` yields nothing (7.10.2.b); the two-argument `id()` is
ignored (7.10.3.b); `xsi:type="xsd:ID"` content is not ID-registered
(7.10.3.c); a computed trigger label (`label ref="."`) does not compute
(7.10.4.a — the `context()` function itself works). The digest/hmac
vector suites (7.8.3/7.8.4 a/b/f) are fully green.

Chapter 8: datatype binding restrictions are not enforced — range and
upload bound to xsd:string raise no binding exception (8.1.1.a,
8.1.6.d); the `xf:mediatype` child element does not override the
mediatype attribute (8.1.5.1.a); an upload commit dispatches
xforms-upload-done but no xforms-value-changed (8.1.6.b);
`selection="open"` is not honored — free values flag out-of-range
(8.1.10.a, 8.1.11.a). **FIXED (ms76)**: the select-commit family —
XFSelectControl now routes its commit through the processor's
value-change pipeline, and a leak was found underneath it: a SUCCESSFUL
synchronous submission never closed its deferred-update action, so
every later recalculate/revalidate/refresh silently stalled
(regression test testSyncSubmissionLeavesDeferredQueueBalanced). That
one leak was also hiding the inline-schema pattern validation in 2.3.a.

Chapter 9: a switch inside a repeat does not keep per-item
state (9.3.1.f, 9.3.4.a); `xf:copy` items copy nothing — items build
and label but usesCopy is unset, selecting inserts no subtree, and
copy-into-attribute raises no binding exception (9.3.6.a, 9.3.7.a/b).
**FIXED (ms76)**: 9.2.1.a2 (the select-commit family, see chapter 8).

**Chapter 10 — ALL FIXED (ms76)**: the insert/delete `context`/`model`
attributes now switch the evaluation context first (XFAbstractAction
actionTargetModel + the bind_evaluate keep-if-owned rule); an insert
whose specified `origin` selects nothing terminates with no effect;
actions after `xf:reset` re-resolve a stale context node to the default
instance root (XFAbstractAction liveContextNode — the reset swaps the
instance document); deleting an instance root is a no-op; insert and
delete `@at` clamp (<1 → 1, >size/NaN → size/last); a negative setindex
lands on scroll-first+1 instead of wrapping through NSUInteger; nested
repeats re-initialize to their startindex when the outer index moves or
the indexed item is replaced (XFRepeat resetNestedRepeatIndexes — also
fixes h.2); a programmatic setfocus no longer re-selects the item
owning the resolved control object (only a real UI click moves the
repeat index). 10.7.a's final index assert was a test bug (the suite
form resets the index to 1 itself).

**Chapter 11 — ALL FIXED (ms76)**: relative submission
`@action`/`@resource` URIs resolve against the document base URL
(XFSubmission.baseURL, set beside instance @src; subform submissions
resolve against the subform's URL); a targetref that names nothing
fails with target-error instead of replacing the whole instance; an
`@instance` IDREF naming no instance raises xforms-binding-exception
(also flips 4.5.1.a4/4.7.e3); the XML serialization carries an XML
declaration with @encoding (default UTF-8) and @standalone,
suppressed by @omit-xml-declaration; a NAMESPACED attribute
(xsi:type) serializes with its prefixed name — GNUstep's
addAttribute: of a URI-carrying copy declared the namespace as default
xmlns AND corrupted the source element (relevantCopy: rebuilds the
attribute and re-declares the prefix); writes into
event('submission-body') during xforms-submit-serialize replace the
serialization; get/delete send NO body (the data is in the URI); the
SOAP rules are complete (action= param → SOAPAction + text/xml
fallback, @encoding charset appended, SOAP-over-get moves the content
type into Accept).

**Chapter 2 — ALL FIXED (ms76)**: the select-commit and
deferred-queue-leak fixes flipped 2.3.a entirely (the inline schema
pattern was enforced all along — the stalled pipeline never
revalidated); an xf:submit now resolves its `@submission` IDREF across
ALL models, and one that names nothing raises
xforms-binding-exception (also flips 4.5.1.a3).

**Appendix B — FIXED (ms76)**: the insert reference node now picks the
parent (b.15.a's heterogeneous `chapter/*` nodeset spans sibling
parents).

Appendix G: the state behind `:out-of-range` is never announced — the
range bound to -100 in [0,2000] dispatches no xforms-out-of-range
(g.1.e — the ch4 4.4.16/17 family; the MIP pseudo-class states
relevance/required/validity/readonly and the repeat-index styling hooks
are all green).

**Appendix H — FIXED (ms76)**: h.2 flowed from the nested-repeat index
and delete-@at-clamp fixes.

## Partial-coverage notes (not red — the rest is asserted)

4.2.4.a: the destruct-after-replace-all leg needs a navigating host;
the test covers DOMActivate + xforms-submit. 4.3.6.b: navindex keyboard
order is untestable headless; the test asserts load + hidden-bind
non-relevance. 4.8.1.a/b: getInstanceDocument is a scripting-DOM API —
no scripting host; the tests assert the forms load. 3.3.2.f: `@src`
precedence is non-normative and conditional — either consistent
data set passes.

## Conventions for the next chapters

One class per chapter (`XFW3CChapterNNTests`), one method per case named
`test_<case-id>_<ShortTitle>` with dots as underscores. New files go in
`Tests/W3CTests/`, get added to `XFW3CTests_OBJC_FILES` in the root
GNUmakefile AND to the Xcode target (an anchor script per round in the
`tools/addw3cchapters789.py` pattern — a build-file plus file-ref pair
per file in the 000003 id family;
`tools/addw3cchapters1011.py` covered chapters 10-11;
`tools/addw3cfinal.py` covered chapter 2 and appendices B/G/H — the
suite is now fully converted, next free ids AA…10+/BB…1A+). Harness notes: the control walk must treat
`XFCase` explicitly (it is NOT an `XFGroup`) or case content is
invisible — `Tools/xftestrun` still has that blind spot. `XFFormView`'s
initializer installs its own `focusRequestHandler`, so the harness
installs its focus capture AFTER building the form view, chained onto
the view's handler — installed before, it is silently clobbered (the
same applies to any host embedding the view). For chapter 11 the echo
transport records every `XFSubmissionRequest`
(`submittedRequests`/`lastRequest`), and `submissionWithID:` reaches a
submission object directly.

## Running under Xcode

`tools/addw3ctarget.py` registers the `XFW3CTests` unit-test-bundle
target (run the script on both pbxprojs; idempotent). It mirrors the
XFormsKitTests target — links XFormsKit.framework, same header search
paths — and bakes the suite location in via
`XFW3C_SUITE_ROOT="$(SRCROOT)/TestSuite/XForms1.1/Edition1"` in
GCC_PREPROCESSOR_DEFINITIONS, because Xcode runs test bundles from
DerivedData where the harness's working-directory walk cannot find the
suite. Product ⇢ Test on the XFW3CTests scheme = `make w3ccheck`.
