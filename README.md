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
- AppKit host view (`XFFormView`)
- XML Events (`XFListener` / `XFXMLEvents`), translated from XSLTForms
  `xmlevtmngt`: registry, EventContexts stack, capture/target/bubble
  dispatch, `ev:listener` and `ev:*` attributes
- No schema, no repeats, no submission, no XSLTForms extensions yet

## Layout

    Sources/XFormsKit/     engine + AppKit views
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

## License

GNU Lesser General Public License 2.1. See `COPYING.LIB`.
The implementation is original so a later relicensing is still possible
if all contributors agree.
