# XSLTForms → XFormsKit: implementation gaps

Generated 2026-08-30 by comparing the XSLTForms sources
(`src/js/{controls,actions,coreelts,xpathexpr,types,xmlevtmngt,main}` and the
`src/xslt/jsgen` / `src/xslt/elements` templates, which are the authoritative
list of attributes the JS engine reads) against `Sources/XFormsKit`.
Companion to `XSLTForms-mapping.md` (which documents what *is* mapped).

Each gap has an id (`G-nn`) so work can be scheduled by id. Priority:

- **P0** — wrong behaviour in already-supported features (bugs)
- **P1** — structural gaps that stop ordinary XSLTForms forms from working
- **P2** — attributes / events of supported elements that are not read
- **P3** — XPath functions, types, schema
- **P4** — XSLTForms extensions / browser-only features (port only if wanted)
- **n/a** — cannot or should not apply in an AppKit host

Status is as of the date above; when a gap is closed, mark it and move the
row to `XSLTForms-mapping.md`.

## Prioritized list

### P0 — bugs in supported features

| Id | Gap | Where | XSLTForms reference |
|---|---|---|---|
| G-01 | Change-list swap timing: `XFModel rebuild` swaps `nodesChanged`/`rebuilded` *before* recalculate/revalidate and never on the recalculate-only path → MIPs on existing nodes go stale after insert/delete (probe-confirmed: `required="count(../item) > 1"` stays false after an insert) and `nodesChanged` grows forever, defeating the `XFMIPBinding` cache | `XFModel.m` rebuild/swapChangeLists, `XFDeferredUpdates.m` | `globals.js refresh` (swap after UI refresh) |
| G-02 | Relevance/readonly inheritance is one-way: unbound descendants are only ever set non-relevant/readonly, never restored when the ancestor becomes relevant/readwrite again | `XFInstance.m` revalidate (~274) | `XFInstance.js validate_` else-branch |
| G-03 | **DONE 2026-08-30** — lexer tracks operand position (XFXPathLexer `_lastWasOperand`); also `and`/`or` as element names — XPath lexer: `-` followed by a digit is always a negative literal → `count(x)-1`, `last()-1`, `1-1`, `.-1` fail to parse | `XPath/XFXPathLexer.m` | `xp2js.xsl` |
| G-04 | **DONE 2026-08-30** — `+[XFXPath xpathWithString:element:error:]` registers prefixes from the host element (all bindings/actions pass their element); node tests fall back to the candidate node's in-scope declarations; `prefix:*` handled — Namespace prefixes in XPath are never registered (`XFNSResolver` always empty) → `my:item` matches only un-namespaced nodes | `XPath/XFExprContext.m`, binding creation | `js2ns.xsl`, `XsltForms_xpath.registerNS` |
| G-05 | **DONE 2026-08-30** — `XFNumberToString` (shortest round-trip, plain decimal) — `string(number)` uses `%g` (6 significant digits) → `string(1234.5678)` = "1234.57" | `XPath/XFXPathValue.m` | JS `""+n` |
| G-06 | **DONE 2026-08-30** — `event()` walks the context stack; arrays → node-set, `response-headers` → `<header><name/><value/></header>` nodes, XML `response-body` → parsed root — `event()` returns `[NSArray description]` for array-valued context keys (`inserted-nodes`, `deleted-nodes`, `origin-nodes`, `response-headers`) instead of a node-set; `response-body` never parsed to XML; only the top event context is searched (XSLTForms walks the stack) | `XPath/XFXPathCoreFunctions.m` event, `XFXMLEvents.m` | `XPathCoreFunctions.js event`, `requesteventlog` |
| G-07 | Submission HTTP verb: `urlencoded-post` / `multipart-post` / `form-data-post` sent verbatim as the HTTP method; `urlencoded-post` Content-Type defaults to `application/xml` | `XFSubmissionTransport.m`, `XFSubmission.m` | `XFSubmission.js submit` (`method.split("-").pop()`) |
| G-08 | `replace="instance"` without `@instance` targets the model default instead of the instance containing the submitted node | `XFSubmission.m targetInstance` | `XFSubmission.js func` |
| G-09 | No per-handler `openAction/closeAction` wrapper: each leaf action runs its own rebuild/recalculate/refresh cycle, so sibling actions in one `xf:action` see intermediate refreshes and MIP events | `XFListener.m invoke`, `XFAbstractAction.m` | `XsltForms_browser.run` |
| G-10 | Handler evaluation context is the *target control's* bound node, not the observer element's in-scope node → unbound triggers inside `group ref` / repeat items act on the default root | `XFAbstractAction.m handleXMLEvent` | `XFAbstractAction.js execute`, `IdManager.find` |
| G-11 | `xforms-value-changed` fired only from the UI path (even when unchanged), never when `setvalue`/`calculate`/insert change a control's node; no type `parse()`/no-op-if-unchanged in the commit path | `XFProcessor.m controlDidChangeValue:`, `XFControl.m` | `XFControl.js refresh / valueChanged` |
| G-12 | Empty value validity: XSLTForms treats `""` as valid until a validation error is pending (`changeProp`); XFormsKit shows required/typed empty fields as invalid (red) at load. Also xsd:* types accept empty in XFormsKit while XSLTForms only lets xf:* accept empty | `XFControl.m applyMIPsFromNode:`, `XFType.m` | `XFControl.js changeProp`, `TypeDefs.js` |
| G-13 | Insert into empty nodeset with `@context` appends as **last** child (XSLTForms: first child); non-numeric `@at` with `position="before"` off by one; delete rounds `@at` (JS doesn't) | `XFInsertAction.m`, `XFDeleteAction.m` | `XFInsert.js`, `XFDelete.js` |
| G-14 | **DONE 2026-08-30** — XPath 1.0 §3.4 comparison rules in XFBinaryExpr; `seconds()`/`months()` accept any xsd:duration; date/dateTime regex parser honours offsets, rejects 2020-02-30 — Node-set vs number compared as strings (`x = 1` with `<x>1.0</x>` false); `seconds()`/`months()` reject mixed durations; `days-from-date`/`seconds-from-dateTime` drop timezone offsets | `XPath/XFBinaryExpr.m`, `XFXPathCoreFunctions.m` | `BinaryExpr.js`, `XPathCoreFunctions.js` |
| G-15 | **DONE 2026-08-30** — parser treats text()/node()/comment()/processing-instruction() as steps everywhere — Leading `text()` / `node()` / `comment()` step parsed as a function call ("Function text() not found") | `XPath/XFXPathParser.m` | — |
| G-16 | MIP flips don't `addChange` the node; `XFMIPBinding disposeNode:` never called on delete (caches keep dead nodes) | `XFInstance.m`, `XFDeleteAction.m` | `XFInstance.js setProperty_`, `MIPBinding.nodedispose` |
| G-17 | `xf:header`: no `@combine`, no `@nodeset` iteration, only the first `xf:value`; later headers overwrite earlier ones | `XFSubmission.m` | `XFSubmission.js submit` |
| G-18 | `xforms-ready` dispatched synchronously per model with `ready` flipped per model (XSLTForms: once, async, after all models) | `XFProcessor.m` | `globals.init` |

### P1 — structural gaps

| Id | Gap | Where | XSLTForms reference |
|---|---|---|---|
| G-20 | Controls nested in host markup (`<p>`, `<td>`, `<div>`, `<svg>`) inside `xf:group` / `xf:repeat` / `xf:case` are dropped (only direct `xf:` children instantiated; top-level collector already recurses). Breaks 7 samples and all table-layout repeats | `XFGroup.m`, `XFRepeat.m`, `XFSwitch.m` | `node.xsl.xml`, `group.xsl.xml` |
| G-21 | `bind="id"` unsupported on UI controls, `setvalue`, `submission` (insert/delete copy the bind's nodeset text instead of using its evaluated nodes) | `XFControl.m bindingOnElement:` etc. | `toScriptBinding.xsl.xml` |
| G-22 | *partly done 2026-08-30: instance('id') searches all models and instance() without argument uses the context node's instance; @model attribute still open* — `model="id"` ignored everywhere; every control/action/bind is created against the first model; `instance('id')` cannot cross models; `instance()` with no arg returns model default instead of the context node's document | `XFProcessor.m`, `XFXPathCoreFunctions.m` | `toScriptBinding.xsl.xml`, `XPathCoreFunctions.js instance` |
| G-23 | Labels: `<xf:label ref=…>` on a control is read once as text (empty); inline markup / `<xf:output>` inside labels lost; `choices/label@ref` ignored | `XFControl.m labelForElement:`, `XFSelectControl.m` | `XFLabel.js`, `label.xsl.xml` |
| G-24 | Focus model: no `DOMFocusIn`/`DOMFocusOut`, focusing a control inside a repeat item doesn't set the repeat index, `xf:setfocus` doesn't move AppKit first responder; `xforms-focus` default action only sets a flag | `XFControl.m focus`, `UI/XFFormView.m` | `XFControl.js focus/blur`, `XsltForms_repeat.selectItem` |
| G-25 | Select/select1: no blank option for an empty value (NSPopUpButton shows item 1 as selected); `xforms-out-of-range`/`in-range` never fired; unknown value written verbatim; `xforms-select`/`deselect` target the select instead of the `xf:item`; itemset doesn't filter non-relevant nodes | `XFSelectControl.m`, `UI/XFFormView.m` | `XFSelect.js setValue/itemClick` |
| G-26 | `xf:switch/@ref` and `@caseref` ignored (switch created unbound); initial `xforms-select` not dispatched to the default case; case children only via `isControlElement:` | `XFSwitch.m` | `jsgen/switch.xsl`, `jsgen/case.xsl` |
| G-27 | Repeat index doesn't follow the node after rebuild (keeps the number) | `XFRepeat.m` | `XFRepeat.js build_` |
| G-28 | `xf:model` without `xf:instance` is an error (XSLTForms synthesises `<data>` from `//@ref`) | `XFModel.m` | `jsgen/model.xsl` |
| G-29 | Group non-relevant → children not refreshed (stale MIPs / no events while hidden) | `XFGroup.m refreshWithContext:` | `XFGroup.js refresh` |
| G-30 | Exception events never dispatched: `xforms-compute-exception`, `xforms-link-exception` (not even defined), `xforms-version-exception`, `xforms-binding-exception` (only from `send`) | `XFXMLEvents.m`, various | `globals.error` |

### P2 — attributes / children / events not read

| Id | Gap | Element | XSLTForms reference |
|---|---|---|---|
| G-40 | `@delay` (debounce for incremental) | input/secret/textarea | `XFInput.js keyUpIncremental` |
| G-41 | `@inputmode` (lowerCase/upperCase/titleCase/digits), `maxLength`/size from type facets, numeric right-align | input | `XsltForms_input.InputMode` |
| G-42 | Return in input / checkbox click → `DOMActivate` | input | `XFInput.js keyUpActivate` |
| G-43 | `appearance="compact"` (list box), `select` minimal (multi-select list), `trigger appearance="minimal"` (link), group `compact`/`table*` layouts | select/select1/trigger/group | `select1-select.xsl.xml`, `group.xsl.xml` |
| G-44 | `xf:output mediatype="application/xhtml+xml"` computed (`displaysHTML`) but rendered as raw text; type-formatted display (`type.format`) | output | `XFOutput.js setValue` |
| G-45 | `xf:range`: value readout, `incremental` (commit only on release), type format/parse | range | `XFRange.js` |
| G-46 | `xf:upload/@mediatype` as NSOpenPanel filter; `xforms-upload-done/error`; unexpected-type error | upload | `XFUpload.js` |
| G-47 | `xf:submit @if/@while/@iterate`; triggers should not emit MIP/value-changed events (`isTrigger`) | submit/trigger | `jsgen/submit.xsl`, `XFControl.js` |
| G-48 | `dispatch`: `xf:property` (event context), `@delay`/`xf:delay`, `xf:name`/`xf:targetid` children, default target model submission for `xforms-submit` | dispatch | `XFDispatch.js` |
| G-49 | `setvalue @context`; literal not `normalize-space`d | setvalue | `XFSetvalue.js` |
| G-50 | `load @show="new"|"replace"` has no host hook (should call a delegate to open the URL); `load-done`/`load-error` dispatched on the action not the target; `@target` alias | load | `XFLoad.js` |
| G-51 | `message @level` ignored and text only queued in `XFDeferredUpdates.messages` (no presentation); inline `xf:output` in message not evaluated | message | `XFMessage.js` |
| G-52 | `toggle` not wrapped in openAction; deselect fired only on the previously selected case (JS: all siblings) | toggle | `XFToggle.js` |
| G-53 | `rebuild/recalculate/…/reset @model`, action `@model` | model actions | `reaction.xsl.xml` |
| G-54 | `ev:phase` unknown value → should raise compute-exception; `ev:actiontype`/`ev:alink` aliases; `xforms-model-destruct` listeners never invoked (no `close()`) | events | `Listener.js`, `globals.close` |
| G-55 | `xf:instance/@resource` alias, `@readonly`, `@mediatype` (JSON/CSV/vCard → XML), response Content-Type override, `@src` errors → `xforms-link-exception` | instance | `XFInstance.js` |
| G-56 | `xf:model @schema`, `@functions`, `@version` (+ their exception events) | model | `XFModel.js ctor` |
| G-57 | `bind @type` resolved with hard-coded prefixes (not in-scope ns); `@calculate` result not type-normalised; `xsi:type` conflict error; `xsd:ID` handling | bind | `XFBind.js` |
| G-58 | `submission`: `@mode` default is sync (deliberate); `@serialization="none"` should default validate/relevant off; `@validate` skips attribute nodes; `@relevant` doesn't prune attributes; `@mediatype ;action=` → SOAPAction; default `Accept` header; `@show`; `@cdata-section-elements`; `error-type` context lacks `message`; `response-reason-phrase` synthesised | submission | `XFSubmission.js` |
| G-59 | `replace="text"` without `targetref` raises target-error (JS: no-op + submit-done) | submission | `XFSubmission.js func` |
| G-60 | `xforms-refresh` runs the UI refresh twice per cycle (default action + `closeChanges`) | deferred updates | `globals.js closeChanges` |
| G-61 | `xf:item/@id` not registered for `ev:observer`; `xf:choices` label `ref` | select | `jsgen/item.xsl` |
| G-62 | `xforms-help` UI (help never surfaced), `help/@href`, hint hover | controls | `field.xsl.xml` |
| G-63 | `navindex`, `accesskey`, `placeholder`, `rows`/`cols` pass-through | controls | `input.xsl.xml` |

### P3 — XPath functions, types, schema

| Id | Gap | XSLTForms reference |
|---|---|---|
| G-70 | **DONE 2026-08-30** — ends-with, compare, replace, upper-case, lower-case, string-join, tokenize, encode-for-uri, distinct-values (XFXPathExtraFunctions.m) — Missing string functions: `ends-with`, `compare`, `replace`, `upper-case`, `lower-case`, `string-join`, `tokenize`, `encode-for-uri`, `distinct-values` | `XPathCoreFunctions.js` |
| G-71 | **DONE 2026-08-30** — avg, min, max — Missing aggregates: `avg`, `min`, `max` | idem |
| G-72 | **DONE 2026-08-30** — format-number ported (default XSLT symbols; optional # digits trimmed) — `format-number` (full picture-string implementation) | idem :1578 |
| G-73 | **DONE 2026-08-30** — adjust-dateTime-to-timezone, nodeindex, fromtostep — `adjust-dateTime-to-timezone`, `nodeindex`, `fromtostep` (needed by repeat @from/@to) | idem |
| G-74 | **DONE 2026-08-30** — EXSLT math:* (13) — still looked up by local name — EXSLT `math:*` (abs, acos, asin, atan, atan2, constant, cos, exp, log, power, sin, sqrt, tan); function lookup ignores the namespace (`math:power` accidentally works) | idem :1862 |
| G-75 | `property()` extras (`xsltforms:*`, `xsl:*`), `digest`/`hmac` unknown algorithm should raise binding-exception | idem |
| G-76 | *partly done 2026-08-30: index() and current() now register dependencies; auto-position from repeat membership still open* — `index()`/`current()` register no dependencies (index-driven expressions don't refresh); no auto-position from repeat membership in context | `ExprContext.js` |
| G-77 | *partly done 2026-08-30: unbound `$x` evaluates to "" as in XSLTForms; xf:var/setvar still open* — Variables `$x`: `ctx.variables` never populated (every `$x` errors); `xf:var` / `setvar` | `VarRef.js`, `XFVar.js` |
| G-78 | *partly done 2026-08-30: unions in document order, reverse axes reported in document order, round() half-up; `*:name` still open* — Document-order sorting for unions / reverse axes (`unordered` flag); `round()` half-away-from-zero for negatives; `*:name` wildcard prefix | `XPath.js`, `unordered.xsl` |
| G-79 | Missing types: `xsd:IDREFS`, `xsd:NMTOKENS`, `xf:card-number`, `xf:HTMLFragment`, `xf:amount`, `xsltforms:shortDate`/eval types, `dcterms:W3CDTF`; Latin-1 letters in Name/NCName/ID; `anyURI`/`url` patterns | `TypeDefs.js` |
| G-80 | Facets not enforced: `enumeration`, `length`, `minLength`, `maxLength`, `minExclusive`, `maxExclusive`, `totalDigits`, `fractionDigits > 0`; `normalize`/`format`/`parse`; `hasBase` | `AtomicType.js` |
| G-81 | List and union types (`XFListType`, `XFUnionType`) | `ListType.js`, `UnionType.js` |
| G-82 | `xs:schema` support (inline in model or `@schema`): simpleType restriction/list/union, facets, per-schema prefix map, `xforms-link-exception` on duplicate targetNamespace; `bind/@type` referring to schema types | `schemas/*.xsl`, `Schema.js` |
| G-83 | `xsi:type` on instance nodes and validation of unbound typed nodes; `xsi:nil` | `browser.getType`, `XFInstance.js validate_` |
| G-84 | **DONE 2026-08-30** — is-valid() recurses attributes/descendants; id() takes a scope node — `is-valid()` should recurse into attributes/descendants; `id()` second argument / xsd:ID content match | `XPathCoreFunctions.js` |

### P4 — XSLTForms extensions

| Id | Gap | XSLTForms reference |
|---|---|---|
| G-90 | Subforms: `load show="embed"` / `@targetid`, `xf:unload`, `xforms-subform-ready`, `subform-instance()`, `subform-context()`, per-subform models/listeners | `subform.js`, `XFLoad.js`, `XFUnload.js`, `XFComponent.js` |
| G-91 | `xf:repeat @from/@to/@step` (numeric repeat via `fromtostep()`) | `jsgen/repeat.xsl` |
| G-92 | `xf:include/@src` (inline external XML/SVG) | `include.xsl.xml` |
| G-93 | `xf:dialog` + `xf:show`/`xf:hide` (events exist, no element/actions) | `dialog.xsl.xml`, `show-hide.xsl.xml` |
| G-94 | `xf:itext` / `itext()` translations; `ajx:setproperty` (language) | `jsgen/itext.xsl`, `AJXSetproperty.js` |
| G-95 | `ajx:tabs`, `xf:tree`, `xf:component/@resource`, `ajx:aid-button`, `ajx:confirm`, `xf:setnode`, `bind/@changed` propagation, `AJXTimer` (`ajx-time`) | various |
| G-96 | Per-repeat-item action instances / `IdManager.find` (cloned ids resolved to the current repeat item) | `IdManager.js` |
| G-97 | JSON / CSV / zip instance and submission bodies (`json2xml`, `xml2json`, `csv2xml`) | `XFInstance.js`, `XFSubmission.js` |

### n/a in an AppKit host

AVTs in HTML attributes, `@class`/CSS styling, `xf:script`/`js-eval`,
`transform`/`serialize`, HTML `<script>` pass-through, TinyMCE/CKEditor
`mediatype="application/xhtml+xml"` editors, `xml-urlencoded-post` hidden
form, `local://`/`opener://`/`javascript:` schemes, IE quirks, status panel,
`replace="all"` document rewrite (kept as `lastAllReplacement`), table/SVG
layout (XFFormView is a vertical stack; a table-aware layout is a renderer
project, not an engine gap).

---

## Appendix A — Controls (detail)

Legend: **impl** / **partial** / **missing**; "n/a in XSLTForms" = XSLTForms does not read it either.

### Cross-cutting: binding & control discovery

| Feature | XSLTForms source | XFormsKit | Notes |
|---|---|---|---|
| `ref` / `nodeset` / `value` binding | `toScriptBinding.xsl.xml` | impl | `XFControl bindingOnElement:` |
| `bind="id"` on any UI control | `toScriptBinding.xsl.xml` | missing | G-21 |
| `model="id"` on binding controls | `toScriptBinding.xsl.xml`, `jsgen/attributes.xsl.xml` | missing | G-22 |
| Controls nested inside HTML inside `xf:group` / `xf:repeat` / `xf:case` | `elements/node.xsl.xml`, `named-templates/group.xsl.xml`, `tr-repeat.xsl.xml`, `table-repeat.xsl.xml` | missing | G-20 |
| `xf:include/@src` | `include.xsl.xml` | missing | G-92 |
| AVTs `{expr}` in HTML attributes | `avt.xsl.xml`, `XFAVT.js` | n/a | |
| `xf:var` | `XFVar.js`, `jsgen/var.xsl.xml` | missing | G-77 |
| `xf:itext` / `itext()` | `jsgen/itext.xsl.xml` | missing | G-94 |
| `xf:component/@resource` | `XFComponent.js` | missing | G-95 |
| `xf:load show="embed"` (subforms) | `jsgen/load.xsl.xml` | missing | G-90 (`XFLoadAction` reads `show`/`targetid` but only replace/instance paths run) |
| `xf:dialog` + `xf:show`/`xf:hide` | `dialog.xsl.xml`, `show-hide.xsl.xml` | missing | G-93 |
| `ajx:tabs`, `xf:tree` | `tabs.xsl.xml`, `tree.xsl.xml`, `AJXTree.js` | missing | G-95 |
| Unknown `xf:*` element → alert | `ignored.xsl.xml` | partial | XFormsKit silently ignores |

### XFControl base behaviour (`XFControl.js`)

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| MIP → `xforms-enabled/disabled/readonly/readwrite/required/optional/valid/invalid` | `changeProp`/`eventDispatch` | impl | suppressed before `ready`, like XSLTForms |
| `notvalid` treated as valid when value is `""` and no validation error pending | `changeProp` | missing | G-12 |
| `xforms-value-changed` timing | `refresh()` on any displayed-value change | partial | G-11 |
| `valueChanged`: type `parse()` before write; no-op if unchanged | `valueChanged` | missing | G-11 |
| `focus()` → `DOMFocusIn`, repeat item selection, `xforms-focus` | `focus`, `focusHandler` | missing | G-24 |
| `blur()` → `DOMFocusOut` + commit | `blurHandler`, `globals.blur` | partial | commit yes, event no |
| `xforms-help` / `xforms-hint` UI | `field.xsl.xml` | partial | G-62 |
| `xf:alert` when invalid, required `*` | `field.xsl.xml` | impl | tooltip + red caption |
| `ajx:aid-button` | `field.xsl.xml` | missing | G-95 |
| `xforms-binding-exception` on missing bind id | `evaluateBinding` | partial | G-30 |

### `xf:label`

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| Inline text label | `label.xsl.xml` | impl | |
| `label/@ref`, `@bind`, `@value` | `jsgen/output.xsl.xml` | partial | G-23 (standalone labels OK; captions read once) |
| Inline markup / `xf:output` inside label | `label.xsl.xml` | missing | G-23 |
| `choices/label@ref` | `jsgen/choices.xsl.xml` | missing | G-61 |
| Group label by appearance (title/tab/legend) | `group.xsl.xml` | partial | NSBox title only |

### `xf:input` / `xf:secret` / `xf:textarea`

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `ref`, text field, `incremental` | `XFInput.js` | impl | |
| `delay` | `keyUpIncremental` | missing | G-40 |
| `inputmode` | `InputMode` | missing | G-41 |
| `mediatype="application/xhtml+xml"` RTE | `initInput` | n/a | |
| boolean → checkbox; date/dateTime → picker | `initInput`, `Calendar.js` | impl | XFormsKit also handles `xsd:time` |
| numeric class right-align, `step` from `fractionDigits`, `maxLength`/`size` | `initInput`, type facets | missing | G-41 |
| Return → commit + `DOMActivate`; checkbox click → `DOMActivate` | `keyUpActivate`, `click` | partial | G-42 |
| readonly → disabled | `changeReadonly` | impl | disabled rather than read-only (text not selectable) |
| HTML attribute pass-through (`accesskey`, `placeholder`, `rows`, `cols`, `navindex`) | `copy-of @*` | missing | G-63 |

### `xf:output`

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `ref` / `value` | | impl | MIPs from context node for `value` |
| `mediatype="image/*"` | `setValue` | impl | NSImageView |
| `image/svg+xml` inline | `setValue` | partial | NSImage decodes SVG only on macOS |
| `application/xhtml+xml` | `setValue` | partial | G-44 |
| type-formatted display | `refresh` (`type.format`) | missing | G-44 |

### `xf:select` / `xf:select1`

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `xf:item` literal / `@ref` label & value | `XFItem.js` | impl | |
| `xf:itemset` nodeset/ref + label/value/copy | `XFItemset.js` | impl | rebuilt on each refresh |
| `itemset/@model` | `toScriptBinding` | missing | G-22 |
| `xf:choices` | `choices.xsl.xml` | impl | disabled header rows |
| `appearance="full"` radio/checkbox | | impl | |
| `appearance="compact"` list box; `select` minimal multi-list | | partial | G-43 |
| `incremental` default true | `jsgen/select*.xsl.xml` | impl | |
| Empty value → blank option, nothing selected | `setValue` | missing | G-25 |
| Unknown value → `xforms-out-of-range` / back → `in-range` | `setValue` | missing | G-25 |
| `xforms-select`/`deselect` target = item | `itemClick`, `normalChange` | partial | G-25 |
| value formatting via `schtyp.format` | `setValue` | missing | G-44 |
| readonly → disabled | `changeReadonly` | impl | |
| itemset relevance filtering (full appearance) | `jsgen/item.xsl.xml` | missing | G-25 |

### `xf:range`, `xf:upload`, `xf:trigger`/`xf:submit`

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| range `start`/`end`/`step` | `XFRange.js` | impl | NSSlider, step via altIncrement only |
| range incremental / value readout / type format | `XFRange.js` | partial/missing | G-45 |
| upload by bound type (anyURI/string/base64/hex), `xf:filename`, `xf:mediatype` | `XFUpload.js change` | impl | |
| upload `@mediatype` filter, Plupload `xforms-upload-*`, unexpected-type error | `XFUpload.js` | missing | G-46 |
| trigger click → `DOMActivate`, `ref` relevance/readonly | `XFTrigger.js` | impl | |
| trigger `appearance="minimal"` link; label markup | `trigger-submit.xsl.xml` | partial | G-43 |
| `submit/@submission` | `jsgen/submit.xsl.xml` | impl | |
| `submit @if/@while/@iterate/@ajx:synchronized`; no MIP events on triggers | `jsgen/submit.xsl.xml`, `XFControl.js` | missing/partial | G-47 |

### `xf:group`, `xf:switch`, `xf:repeat`

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| group `ref` → context + relevance | `XFGroup.js` | impl | |
| group `bind`/`model` | | missing | G-21/G-22 |
| group children refreshed while non-relevant | `refresh` | partial | G-29 |
| group appearance variants, `navindex`, tabs | `group.xsl.xml` | partial/missing | G-43, G-63, G-95 |
| `case/@selected`, toggle → select/deselect | `switch.xsl.xml`, `XFToggle.js` | impl | |
| initial `xforms-select` on default case; `switch/@ref`; `@caseref` | `jsgen/switch.xsl`, `jsgen/case.xsl` | missing | G-26 |
| repeat nodeset/ref + cloned controls; non-relevant filtered | `build_` | impl | |
| repeat `@from/@to/@step` | `jsgen/repeat.xsl.xml` | missing | G-91 |
| repeat `bind`/`model` | | missing | G-21/G-22 |
| index follows node after rebuild | `build_` | partial | G-27 |
| setindex marks changes; scroll-first/last; insert/delete index update | | impl | |
| focus in item → index; `xforms-repeat-item-selected` | `focus` → `selectItem` | missing | G-24 |
| table repeats (`<table><xf:repeat><tr>`, `tr-repeat`) | `table-repeat.xsl.xml` | missing | G-20 |
| `xf:item/@id` for observers | `jsgen/item.xsl.xml` | missing | G-61 |

## Appendix B — Actions, events, globals (detail)

### Common action machinery

| Feature | XSLTForms source | XFormsKit | Notes |
|---|---|---|---|
| `@if` / `@while` / `@iterate` | `XFAbstractAction.js` | impl | `while` has a 1000-iteration guard; `iterate`+`while` conflict silently prefers iterate (JS: compute-exception) |
| `evt.stopped` short-circuit | `execute` | impl | |
| Default context = observer's in-scope node | `execute`, `browser.run` | partial | G-10 |
| Per-repeat-item action instances / `IdManager.find` | `IdManager.js` | missing | G-96 |
| Handler wrapped in one open/closeAction | `browser.run` | missing | G-09 |
| `@mode="synchronous"` | `listeners.xsl.xml` | missing | harmless |
| `varResolver` propagation | `XFAction.js run` | missing | G-77 |
| `@model` on actions | `toScriptBinding`, `reaction.xsl.xml` | missing | G-22/G-53 |

### Per action element

| Feature | XSLTForms source | XFormsKit | Notes |
|---|---|---|---|
| `xf:action` grouping | `XFAction.js` | impl | |
| `setvalue @ref` / text / `@value` | `XFSetvalue.js` | impl | literal not normalize-space'd (G-49) |
| `setvalue @bind`, `@context`, `@model` | `toScriptBinding`, `XFSetvalue.js` | missing | G-21, G-49, G-22 |
| `insert` nodeset/ref/bind/at/position/origin/context | `XFInsert.js` | impl | `@bind` by textual copy (G-21); also reads `xf:origin/@value`, `xf:context/@value` |
| insert `@at` rounding / NaN, empty nodeset + context position | `XFInsert.js run` | partial | G-13 |
| insert attribute origin, document-node nodeset, repeat update, `xforms-insert` context | `XFInsert.js` | impl | `event('inserted-nodes')` unusable (G-06) |
| `delete` nodeset/ref/bind/at/context, repeat update, `xforms-delete` | `XFDelete.js` | impl | `@at` rounded (G-13) |
| `dispatch @name`, `@targetid|@target` | `XFDispatch.js` | impl | |
| `dispatch` `xf:name`/`xf:targetid` children, `xf:property`, `@delay`/`xf:delay`, default target for `xforms-submit` | `dispatch.xsl.xml`, `XFDispatch.js` | missing | G-48 |
| `load @resource`, `xf:resource`, `@ref` | `XFLoad.js` | impl | |
| `load @show="new"/"replace"` host hook | `XFLoad.js` | partial | G-50 |
| `load @show="embed"` / `@targetid` (subform) | `XFLoad.js` | missing | G-90 |
| `load @instance` | `load.xsl.xml` | XFormsKit-only | XForms 2 load-into-instance |
| `message @ref`, inline, `@level` | `XFMessage.js` | partial | G-51 |
| `setindex @repeat`, `@index` | `XFSetindex.js` | impl | |
| `toggle @case`, `xf:case/@value` | `XFToggle.js` | impl | G-52 |
| `setfocus @control`, `xf:control/@value` | `setfocus.xsl.xml` | impl | dispatches `xforms-focus` (see G-24) |
| `send @submission` | `send.xsl.xml` | impl | lookup only in first model (G-22) |
| `rebuild/recalculate/revalidate/refresh/reset` (+ `@model`) | `reaction.xsl.xml` | partial | G-53 |
| `show`/`hide @dialog` | `show-hide.xsl.xml` | missing | G-93 |
| `xf:setnode`, `xf:var`/`setvar`, `xf:script`, `xf:unload`, `ajx:confirm`, `ajx:setproperty` | various | missing | G-95, G-77, n/a, G-90, G-95, G-94 |

### `ev:*` attributes / listeners

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `ev:event` (+ `ev:actiontype` alias) | `listeners.xsl.xml` | impl | alias not read (G-54); also accepts un-namespaced `event=` |
| `ev:observer` (default parent) | | impl | |
| `ev:target` filter | `Listener.js` | impl | |
| `ev:phase` capture/default | `Listener.js` | partial | unknown → fallback, no compute-exception (G-54) |
| `ev:propagate="stop"`, `ev:defaultAction="cancel"` (+ `ev:alink`) | | impl | alias not read |
| `ev:listener` element | — | XFormsKit-only | |
| listener restricted to action elements | `listeners.xsl.xml` | impl (broader) | |
| `xforms-model-destruct` listeners invoked on close | `globals.close` | partial | never called (G-54) |

### Event registry differences

All XSLTForms registry entries exist in `XFXMLEvents` with identical bubbles/cancelable flags. Differences:

| Event | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `xforms-ready` | once, async after all models | partial | G-18 |
| `xforms-model-destruct` | `globals.close` | missing | G-54 |
| `xforms-refresh` | model no-op; UI refresh in `closeChanges` | impl (double refresh) | G-60 |
| `xforms-focus` | `XFControl.focus` → DOMFocusIn, repeat item | partial | G-24 |
| `DOMActivate` | trigger click, input Enter | impl | submit fires `xforms-submit` directly (cannot be cancelled by a DOMActivate handler); not wrapped in openAction |
| `DOMFocusIn` / `DOMFocusOut` | focus/blur | missing | G-24 |
| `xforms-value-changed` | `XFControl.refresh` | partial | G-11 |
| `xforms-in-range` / `out-of-range` | `XFSelect.setValue` | missing | G-25 |
| `xforms-compute-exception`, `xforms-link-exception`, `xforms-version-exception`, `xforms-binding-exception` | `globals.error` | missing/partial | G-30 |
| `xforms-load-done`/`-error` on target; `xforms-unload-done` | `XFLoad.js` | partial | G-50/G-90 |
| `xforms-upload-done`/`-error` | `XFUpload.js` | missing | G-46 |
| `ajx-start`/`-stop`/`-time` | `AJXTimer.js` | partial | defined, no timer (G-95) |
| `xforms-help`/`xforms-hint` | — | XFormsKit-only | |
| `xforms-subform-ready` | `subform.js` | missing | G-90 |

### Event context / `event()`

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `type`, `targetid`, `bubbles`, `cancelable` on every event | `makeEventContext` | impl | |
| `event(name)` searches the context stack | `XPathCoreFunctions.js event` | partial | G-06 |
| node-set values (`inserted-nodes`, `response-body`, `response-headers`…) | idem | missing | G-06 |
| DOMActivate / DOMFocusIn extra context | `XFTrigger.click`, `XFControl.focus` | missing | |

### Globals / deferred updates

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| open/closeAction nesting, `closeChanges` loop | `globals.js` | impl | |
| `refresh()` swap of change lists after UI build | `globals.refresh` | partial | G-01 |
| `changes` list of changed *elements* (models, repeats, trees) | `globals.addChange` | partial | only models |
| `building` flag during control refresh | `globals.build` | partial | only around bind refresh |
| `bindErrMsgs` → single binding-exception | `globals.refresh` | missing | G-30 |
| `close()` / `dispose()` | `globals.close` | missing | no teardown API; singletons |
| `error()` | `globals.error` | missing | G-30 |
| focus/blur/posibleBlur | `globals.blur` | missing | G-24 |
| subforms | `subform.js` | missing | G-90 |
| `IdManager.cloneId`/`find` | `IdManager.js` | missing | G-96 |

## Appendix C — Model, instance, bind, submission (detail)

### xf:model

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `@id`, default model | `XFModel.js` | impl | |
| `@schema`, `@functions`, `@version` (+ exceptions) | `XFModel.js ctor` | missing | G-56 |
| inline `xsd:schema` | `jsgen/model.xsl`, `Schema.js` | missing | G-82 |
| model without instance → synthesised | `jsgen/model.xsl` | missing | G-28 |
| construct → construct-done → ready | `construct` | partial | G-18 |
| rebuild/recalculate/revalidate/refresh/reset default actions | `XMLEvents.js` | impl | |
| `rebuild` swap timing | `XFModel.js rebuild` vs `globals.refresh` | partial | G-01 |
| `refresh` refreshes all models' controls, no swap | `globals.refresh` | partial | G-01 |
| `addChange` auto-registers model with deferred updates | `XFModel.js addChange` | partial | callers must `addChangedModel:` (`XFUploadControl`, `XFSelectControl.notifyModel` don't) — G-16 |
| `findInstance` | | impl | falls back to default instead of nil |
| multiple models, `@model`, cross-model `instance('id')` | `globals.js`, `jsgen` | partial | G-22 |
| error events | `globals.error` | partial | G-30 |

### xf:instance

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `@id`, inline XML | | impl | |
| `@src` (sync GET; `local://`, `opener://`, `javascript:`, JSONP) | `construct` | partial | file/http only, errors swallowed (G-55) |
| `@resource`, `@mediatype` (JSON/CSV/vCard/zip), `@readonly`, response Content-Type | `XFInstance.js` | missing | G-55, G-97 |
| reset / store / preserveOld | | impl | |
| replacement via submission, `targetref` | `setDoc`, `loadNode` | impl | |
| revalidate walk incl. attributes, inheritance | `validation_` | partial | G-02 |
| `validate_` formula (required/relevant/readonly/type/constraint, `xsi:nil`, multi-bind) | `validate_` | partial | `xsi:nil` missing (G-83); kit ORs required / ANDs constraint across binds, JS last-bind-wins |
| type validation of unbound nodes (`xsi:type`) | `validate_` else-branch | missing | G-83 |
| `setProperty_` → `addChange` | | missing | G-16 |

### xf:bind

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `@nodeset`/`@ref` (default `.`), `@id` | `XFBind.js` | impl | |
| `@type` → schema lookup, `xsi:type` conflict, `xsd:ID` | `XFBind.js` | partial | G-57 |
| builtin xsd/xf types | `TypeDefs.js` | impl/partial | G-79 |
| schema-derived types | `Schema.js` | missing | G-82 |
| readonly/required/relevant/constraint MIP bindings | `MIPBinding.js` | impl | |
| `@calculate` (type-normalised) | `recalculate` | partial | G-57 |
| calculate ⇒ readonly | `validate_` | impl | |
| nested binds | `refresh` | impl | |
| `@changed`/propagate (extension) | `XFBind.js propagate` | missing | G-95 |
| deps capture (`depsNodes`, `depfor`) | `bind_evaluate` | partial | filled, unused |
| MIPBinding cache invalidation (deleted-node check, global changes) | `MIPBinding.evaluate` | partial | G-01/G-16 |
| `nodedispose` on delete | `MIPBinding.nodedispose` | missing | G-16 |

### xf:submission

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `@id`, default submission, `@ref` | | impl | |
| `@bind`, `@value` (extension) | `jsgen/submission.xsl` | missing | G-21 / G-95 |
| `@resource`/`@action`/`xf:resource`, `@method`/`xf:method` | | impl | |
| compound method → HTTP verb / Content-Type | `submit` | missing | G-07 |
| get/delete query serialization | `toUrl_` | impl | |
| multipart-post / form-data-post | `saveNode` | impl | richer than JS |
| `@mode` default | `jsgen/submission.xsl` | partial | default sync (deliberate) — G-58 |
| async ordering (replace → rebuild → submit-done) | `func` | impl | |
| `@replace="all"` / `@show` | `submit` | partial | `lastAllReplacement`; `@show` unread |
| `@replace="instance"` target | `func` | partial | G-08 |
| `@replace="text"` without targetref | `func` | partial | G-59 |
| `@replace="none"`, `@targetref`, `@instance`, `@separator` | | impl | |
| `@serialization="none"` defaults | | partial | G-58 |
| `@validate` incl. attributes; `@relevant` incl. attributes | `validate_`, `saveNode` | partial | G-58 |
| `@mediatype` (`;action=` SOAPAction, charset), default `Accept` | `submit` | partial/missing | G-58 |
| `@encoding`/`@version`/`@indent`/`@omit-xml-declaration`/`@standalone`/`@includenamespaceprefixes` | ctor (stored, unused) | missing | same as JS |
| `@cdata-section-elements` | `saveNode` | missing | G-58 |
| `xf:header` name/value (literal/`@value`) | | impl | |
| `xf:header/@nodeset`, `@combine`, multiple `xf:value` | `submit` headers loop | missing | G-17 |
| JSON/CSV/zip bodies | `xml2data` | missing | G-97 |
| `xforms-submit` default action, in-progress guard, `no-data`, `resource-error`, `parse-error` | | impl | |
| `xforms-submit-serialize` (`submission-body` override) | `submit` | partial | same limitation as JS |
| submit-error context `message` | `issueSubmitException_` | partial | G-58 |
| `requesteventlog` headers as node-set, body parsed | `requesteventlog` | partial | G-06 |
| `AJXTimer` | `AJXTimer.js` | missing | G-95 |

## Appendix D — XPath, parser, types, schema (detail)

### XPath functions

XSLTForms registers 93 functions keyed `"<ns> <name>"`; XFormsKit's table is keyed by local name (prefix stripped, namespace ignored). 48 match, 4 partial, 41 absent.

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| fn core (`last`…`ceiling`, 23 functions) | `XPathCoreFunctions.js` | impl | lenient on arg count |
| `normalize-space`, `lang`, position in filters, dedup in path expr | | impl (better than JS) | |
| `round` | | partial | half-away-from-zero for negatives (G-78) |
| `id` | | partial | G-84 |
| leading `text()`/`node()`/`comment()` | | missing | G-15 |
| `array`, `map`, `entry`, `is-non-empty-array`, `fromtostep`, `invalid-id` | | missing | Fleur/UI extensions; `fromtostep` needed by G-91 |
| `ends-with`, `compare`, `replace`, `upper-case`, `lower-case`, `string-join`, `tokenize`, `encode-for-uri`, `distinct-values` | | missing | G-70 |
| `avg`, `min`, `max` | | missing | G-71 |
| `format-number` | | missing | G-72 |
| `subform-instance`, `subform-context`, `itext`, `alert`, `js-eval` | | missing | G-90/G-94/n/a |
| `context`, `current` | | partial | no deps (G-76) |
| `instance` | | partial | G-22 |
| `index` | | partial | no deps (G-76) |
| `nodeindex`, `adjust-dateTime-to-timezone` | | missing | G-73 |
| `if`, `choose`, `boolean-from-string`, `count-non-empty`, `power`, `random`, `now`, `local-date`, `local-dateTime`, `days-to-date`, `seconds-to-dateTime` | | impl | |
| `property` | | partial | G-75 |
| `seconds`, `months`, `days-from-date`, `seconds-from-dateTime` | | partial | G-14 |
| `is-valid` | | partial | G-84 |
| `is-card-number`, `digest`, `hmac` | | impl | unknown algorithm → MD5 (G-75) |
| `event` | | partial | G-06 |
| `transform`, `serialize` | | n/a | |
| `math:*` (13) | | missing | G-74 |
| unknown function → JS global | `FunctionCallExpr.js` | n/a | |

### Parser / evaluator semantics

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| `-` before digit after an operand | `xp2js.xsl` | bug | G-03 |
| unary minus on non-literals | | impl (superset) | |
| `and`/`or` as element names | | minor | lexer always tokenises as operators |
| `*:name`, `?key`, backticks, `entry()`… | `getLocationPath.xsl` | missing | Fleur (G-78) |
| variables `$x` | `VarRef.js` | unusable | G-77 |
| namespace prefixes | `js2ns.xsl`, `NodeTestName.js` | unusable | G-04 |
| number → string | JS `""+n` | partial | G-05 |
| arithmetic rounding to 1e-6 | `BinaryExpr.js` | not replicated | fine |
| `number(boolean)`; string arithmetic/concat quirk; lexical `<` on strings | `utils.js`, `BinaryExpr.js` | spec | XSLTForms quirks not replicated |
| `=`/`!=` node-set vs number | `BinaryExpr.js` | partial | G-14 |
| document order for unions / reverse axes | `unordered.xsl` | missing | G-78 |
| `namespace::` axis | | missing (same) | |
| ExprContext: auto-position from repeat, `parent`, `root`, `depsId` cleanup | `ExprContext.js` | partial | G-76 |
| dependency collection for `current()`/`index()` | | missing | G-76 |
| expression cache | `XsltForms_xpath.expressions` | impl | cached resolver empty (G-04) |

### Types

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| 39 xsd primitives/derived | `TypeDefs.js` | impl | pattern differences (year range, Latin-1 names, anyURI) — G-79 |
| `xsd:IDREFS`, `xsd:NMTOKENS` | | missing | G-79 |
| xf:* mirrors accept empty (xsd:* don't) | | partial | G-12 |
| `xf:dayTimeDuration`, `yearMonthDuration`, `email`, `card-number`, `url` | | impl/partial | `url` pattern missing |
| `xf:IDREFS/NMTOKENS/amount/HTMLFragment`, `xsltforms:*`, `dcterms:W3CDTF` | | missing | G-79 |
| type lookup prefixes / unknown → xsd:string | `Schema.js prefixes` | partial | G-57 |
| whitespace facet | `Type.js` | impl (more lenient) | |
| `pattern` (inherited) | `AtomicType.js` | impl | |
| `enumeration`, `length`, `min/maxLength`, `min/maxExclusive`, `totalDigits`, `fractionDigits>0` | `AtomicType.js validate` | missing | G-80 |
| `min/maxInclusive` | | impl | |
| `normalize`/`format`/`parse`/`class`/`displayLength`/`hasBase` | `AtomicType.js`, `TypeDefs.js` | missing | G-80 |
| list / union types | `ListType.js`, `UnionType.js` | missing | G-81 |
| `xsi:type`, unbound-node validation, `xsi:nil` | `browser.getType`, `validate_` | missing | G-83 |

### Schema

| Feature | XSLTForms | XFormsKit | Notes |
|---|---|---|---|
| inline `xs:schema` / `@schema` → `XsltForms_schema` | `schemas/schema.xsl`, `Schema.js` | missing | G-82 |
| `xs:simpleType/xs:restriction` (+anonymous), facets incl. `maxScale`/`minScale`, `xsltforms:rte`, appinfo | `restriction.xsl` | missing | G-82 |
| `xs:list`, `xs:union` | `list.xsl`, `union.xsl` | missing | G-81/G-82 |
| per-schema prefix map, duplicate targetNamespace → link-exception | `Schema.js` | missing | G-82 |
