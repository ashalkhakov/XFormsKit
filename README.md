# XFormsKit

An XForms 1.1 engine for Cocoa and GNUstep. The processor reads an
XHTML+XForms host document, maintains XML instances, evaluates XPath 1.0
bindings, and maps controls onto AppKit.

This is an independent implementation. XSLTForms
(https://github.com/AlainCouthures/xsltforms) is used as a *behavior*
reference, not as a source to translate.

## Status

First vertical slice:

- Load a well-formed XHTML+XForms document
- One `xf:model` / `xf:instance`
- `xf:input` (`ref`) and `xf:output` (`value`)
- XPath 1.0 subset: location paths, string/number literals, `concat()`,
  `string()`, `name()`, `local-name()`, `instance()`
- AppKit host view (`XFFormView`)
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

GNU Lesser General Public License 2.1. See `LICENSE` and `COPYING.LIB`.
The implementation is original so a later relicensing is still possible
if all contributors agree.
