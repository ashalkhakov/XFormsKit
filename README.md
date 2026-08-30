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

## Layout

    Sources/XFormsKit/     engine + AppKit views
    Apps/XFormsViewer/    document-based host (3-pane navigator / form / inspector)
    Samples/               ported XSLTForms `testsuite/samples` forms
    Tests/XFormsKitTests/  XCTest cases (Apple XCTest or gnustep/tools-xctest)
    Tests/Fixtures/        sample forms

## Building

### Xcode (macOS)

    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit -configuration Debug build
    xcodebuild -project XFormsKit.xcodeproj -scheme XFormsKit -configuration Debug test

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

## License

GNU Lesser General Public License 2.1. See `COPYING.LIB`.
The implementation is original so a later relicensing is still possible
if all contributors agree.
