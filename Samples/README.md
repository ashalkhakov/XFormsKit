# Samples

The complete [XSLTForms](https://github.com/AlainCouthures/xsltforms)
`testsuite/samples` set, plus a few XFormsKit extras that exercise groups,
repeats, switch, range, upload and incremental textareas.

XSLTForms files are copied verbatim except for: the `xml-stylesheet`
processing instruction is dropped (XFormsKit interprets the XHTML+XForms host
document directly), the BOM is removed, CRLF is normalized, and
`bookmarks.xhtml` is re-encoded from ISO-8859-1 to UTF-8. Supporting files
(`counties.xml`, `XMLSchemaTypeCode.xml`, `flag.svg`, `textarea.css`) sit next
to the forms so relative `src` / `resource` references resolve against the
host URL.

Open any `.xhtml` file with **XFormsViewer** (File ▸ Open Sample lists them).

## Catalogue

| File | Title | Origin | Exercises |
| --- | --- | --- | --- |
| address.xhtml | Address | XFormsKit port | group/@ref, inputs |
| balance-table.xhtml | Balance-Table | XSLTForms | repeat, bind/@calculate, table layout |
| balance.xhtml | Balance | XSLTForms | repeat, insert/delete, bind/@calculate |
| bind.xhtml | Calculate bind | XFormsKit port | bind/@calculate |
| bookmarks.xhtml | Bookmarks | XSLTForms | nested repeat, insert/delete/@at, setvalue, switch |
| books.xhtml | Books | XSLTForms | repeat, insert/delete, used as a subform by writers.xhtml |
| button.xhtml | Button | XFormsKit port | trigger, setvalue |
| calculator.xhtml | Calculator | XSLTForms | many triggers/setvalue, bind/@calculate, XPath |
| checkbox.xhtml | Boolean input | XFormsKit port | boolean input |
| choices.xhtml | choices / itemset | XFormsKit extra | select1 choices, itemset |
| colors.xhtml | Background Colors | XSLTForms | select1, output/@value with CSS class |
| date.xhtml | Date input | XFormsKit port | bind/@type xsd:date |
| deep-copy.xhtml | Deep Copy between instances | XSLTForms | insert/@origin across instances, instance/@id |
| first-field.xhtml | Initial Cursor Positioning | XSLTForms | setfocus on xforms-ready |
| flags.xhtml | Colored Flags | XSLTForms | repeat over attributes, xf:include (SVG) |
| gantt.xhtml | SVG Gantt | XSLTForms | repeat/@from/@to inside SVG, date functions |
| hello.xhtml | Hello World | XFormsKit port | input, output/@value |
| incremental-textarea.xhtml | Incremental input | XFormsKit extra | input/textarea @incremental, relevance |
| incremental.xhtml | Many to one | XSLTForms | input/select1 @incremental |
| input-width.xhtml | Controlling Input Field Width | XSLTForms | input/@class, bind/@type sizing |
| input.xhtml | XForms inputs with labels | XSLTForms | input, label placement |
| output-image.xhtml | output image | XFormsKit extra | output/@mediatype image |
| piechart.xhtml | SVG Pie Charts | XSLTForms | repeat inside SVG, XPath math |
| range.xhtml | Range | XFormsKit extra | range start/end/step |
| readonly.xhtml | Readonly MIP | XFormsKit port | bind/@readonly |
| relevant.xhtml | Relevant MIP | XFormsKit port | bind/@relevant |
| repeat.xhtml | Repeat | XFormsKit extra | repeat, setindex |
| secret.xhtml | Secret | XFormsKit port | secret |
| select-from-file.xhtml | Select List From File | XSLTForms | instance/@src (XMLSchemaTypeCode.xml), itemset/@model |
| select-model.xhtml | Selection List Data From the Model | XSLTForms | itemset over a second instance |
| select-multi-col.xhtml | Select County | XSLTForms | instance/@src (counties.xml), itemset/@model |
| select.xhtml | Radio Button Using xf:Select | XSLTForms | select appearance="full", @selection |
| select1-drop.xhtml | Demonstration of XForms Select1 | XSLTForms | select1 minimal/full, itemset |
| select1.xhtml | Select1 | XFormsKit port | select1 items |
| spreadsheet.xhtml | Spreadsheet like Update | XSLTForms | repeat, bind/@calculate chains |
| switch.xhtml | Switch | XFormsKit extra | switch/case/toggle |
| textarea-styled.xhtml | textarea demo | XSLTForms | textarea/@class, external CSS |
| textarea.xhtml | Textarea | XFormsKit port | textarea |
| tinymce.xhtml | TinyMCE Support | XSLTForms | textarea mediatype="application/xhtml+xml" → built-in rich text editor (no TinyMCE/WebKit) |
| upload.xhtml | upload | XFormsKit extra | upload, filename/mediatype |
| uploads.xhtml | Uploads and types | XSLTForms | upload, bind/@type base64/hex, submission |
| wikipediasearch.xhtml | WIKIPEDIA OpenSearch | XSLTForms | submission GET replace="instance", input/@delay (needs network) |
| writers.xhtml | Writers (Subforms) | XSLTForms | xforms:load show="embed" / xforms:unload subforms (`xforms:` prefix) |
| dialog.xhtml | Dialog, variables, itext, numeric repeat | XFormsKit extra | xf:dialog + show/hide, xf:var, itext(), repeat @from/@to |
| xf.xhtml | Template | XSLTForms | switch/case, toggle, message |
| xpath.xhtml | XPath | XSLTForms | XPath 1.0 / XForms function coverage |

## Known gaps (first pass, 2026-08-30)

Every sample above loads and lays out in XFormsViewer; the calculator
computes (the `=` cell follows the switch's selected case) and the
spreadsheet's `xsltforms:decimal` columns evaluate their arithmetic. Attributes and
elements used by the samples that the engine does not yet interpret:

- **Host markup** (G-20): controls nested in `<p>`, `<div>`, `<td>`, `<span>` …
  inside `xf:group` / `xf:repeat` / `xf:case` are instantiated and laid out
  where the markup puts them (blocks stack, inline runs wrap, fieldset →
  box, headings, pre, lists, br/hr); every `<table>` becomes a cell-based
  NSTableView (repeat rows, thead titles, tfoot). Still pending: SVG
  rendering (`[SVG]` placeholder)
- `xf:include/@src` (flags.xhtml) — the included SVG is inlined (G-92) but SVG rendering is pending
- `xf:itemset/@model` (select-from-file, select-multi-col) — itemset bound to another model
- `xf:repeat/@from` / `@to` (gantt.xhtml) — done (G-91); gantt still waits for SVG
- `xforms:load/@show="embed"` + `xforms:unload` (writers.xhtml) — done (G-90): selecting a
  writer embeds books.xhtml into the `subform` group, deselecting unloads it
- `xf:select/@selection="open"` (select.xhtml)
- `xf:input/@delay` (wikipediasearch.xhtml) — XSLTForms incremental delay
- `@class` on controls (input-width, textarea-styled, colors) — CSS
  styling has no AppKit equivalent; widths could map to a hint
- `xf:submission` `xforms-submit-done` / `-error` handlers exist; `@mode`
  and `@serialization` are parsed but not all combinations are exercised
- SVG based samples (gantt, piechart, flags) wait for the SVG phase of G-20
