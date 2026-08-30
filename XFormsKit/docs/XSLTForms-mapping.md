# XSLTForms → XFormsKit mapping

Reference for the Cocoa/GNUstep port. XSLTForms lives under
`src/js/{coreelts,controls,actions,xpathexpr,xmlevtmngt,types,main}`
([AlainCouthures/xsltforms](https://github.com/AlainCouthures/xsltforms), LGPL-2.1).
XFormsKit interprets XHTML+XForms at runtime with NSXML + AppKit; it does
**not** port the XSLT-to-HTML compiler.

Prefix: XSLTForms uses `XsltForms_*`. We use `XF`.

---

## Host / main

| XSLTForms | XFormsKit | Notes |
|---|---|---|
| `main/globals.js` `XsltForms_globals` | `XFDeferredUpdates`, bits on `XFModel` / `XFProcessor` | `openAction` / `closeAction` / `closeChanges` → `XFDeferredUpdates`. `ready` → `XFModel.ready`. |
| `main/Binding.js` `XsltForms_binding` | `XFBinding` | Compiled XPath + evaluate / bound node / string value. |
| `main/MIPBinding.js` | `XFMIPBinding` | Per-MIP XPath + dependency nodes. |
| `main/IdManager.js` | `XFXML elementWithID:inNode:` | xml:id or `id`. |
| `main/subform.js` | — | Not ported (XSLTForms extension). |
| `main/fleur.js` | — | XPath 3 / Fleur not ported. |
| XSLT compiler + HTML DOM | `XFProcessor` + `XFFormView` | Runtime NSXML walk; stock AppKit widgets. |

`XFProcessor` is the document host (load URL/string, collect models/controls/actions, construct/ready, refresh). There is no single `XsltForms` object.

---

## XML Events — `xmlevtmngt`

| XSLTForms | XFormsKit |
|---|---|
| `Listener.js` `XsltForms_listener` | `XFListener` |
| `XMLEvents.js` `XsltForms_xmlevents` | `XFXMLEvents` |
| `REGISTRY` | `XFXMLEvents.registry` / `XFEventRegistration` |
| `EventContexts` | `eventContexts` / `currentEventContext` |
| `define` / `dispatch` / `dispatchList` / `makeEventContext` | same selectors on `XFXMLEvents` |
| host DOM `Event` | `XFEvent` (`type`, `target`, `phase`, `context`, `stopPropagation`, `preventDefault`) |
| XSLT-emitted `new XsltForms_listener(...)` | `installListenersInDocument:` (`ev:listener` + `ev:*`) |
| `element.addEventListener` | associated-object listener arrays on `NSXMLElement` |
| IE capture/target/bubble walk | `dispatch:name:` walks ancestors |

Default actions for model events (`xforms-rebuild`, …) call through to `XFModel` when the target responds to `rebuild` / `recalculate` / ….

---

## XPath — `xpathexpr`

| XSLTForms | XFormsKit |
|---|---|
| `XPath.js` | `XFXPath` |
| `XPathLexer` (inline) | `XFXPathLexer` |
| parser in `XPath.js` | `XFXPathParser` |
| `ExprContext.js` | `XFExprContext` (`currentNode` = XForms `current()`) |
| `NSResolver.js` | `XFNSResolver` |
| `LocationExpr` / `StepExpr` / `FilterExpr` / `PathExpr` / `UnionExpr` / `BinaryExpr` / `PredicateExpr` / `FunctionCallExpr` / `VarRef` | same names under `Sources/XFormsKit/XPath/` |
| `NodeTestAny` / `Name` / `PI` / `Type` | `XFNodeTests.m` |
| `XPathFunction.js` | `XFXPathFunction` |
| `XPathCoreFunctions.js` | `XFXPathCoreFunctions` |
| `XPath.js` `XsltForms_xpathCoreFunctions[...]` | `+[XFXPathCoreFunctions functionNamed:]` |
| `utils.js` node helpers | `XFRootNode`, `XFNodeInArray`, `XFXML` |

XSLTForms compiles expressions in XSLT. We parse at runtime (`xpathWithString:error:`).

### Functions implemented

XPath 1.0 core: `last`, `position`, `count`, `id`, `local-name`, `namespace-uri`, `name`, `string`, `concat`, `starts-with`, `contains`, `substring-before`/`after`, `substring`, `string-length`, `normalize-space`, `translate`, `boolean`, `not`, `true`, `false`, `lang`, `number`, `sum`, `floor`, `ceiling`, `round`.

XForms 1.1: `instance`, `index`, `context`, `current`, `event`, `if`, `choose`, `boolean-from-string`, `count-non-empty`, `power`, `random`, `property`, `now`, `local-date`, `local-dateTime`, `days-from-date`, `days-to-date`, `seconds-from-dateTime`, `seconds-to-dateTime`, `seconds`, `months`, `is-valid`, `is-card-number`, `digest`, `hmac`, `adjust-dateTime-to-timezone`, `nodeindex`.

XSLTForms extras (`XPath/XFXPathExtraFunctions.m`): `ends-with`, `compare`, `replace`, `upper-case`, `lower-case`, `string-join`, `tokenize`, `encode-for-uri`, `distinct-values`, `avg`, `min`, `max`, `format-number`, `fromtostep`, EXSLT `math:abs/acos/asin/atan/atan2/constant/cos/exp/log/power/sin/sqrt/tan`. Functions are looked up by local name (the namespace prefix is ignored, as `functionNamed:` strips it).

Not ported: Fleur/XPath 2–3 (`array`, `map`, `entry`, `*:name`), `js-eval`, `transform`, `serialize`, `itext`, `subform-instance`, `subform-context`, `alert`, `invalid-id`.

Semantics: number→string is the shortest round-trip decimal (`XFNumberToString`); comparisons follow XPath 1.0 §3.4 (node-set vs number compares numerically); unions and reverse axes come back in document order; an unbound `$var` is `""` (VarRef.js); `event()` walks the whole `EventContexts` stack and returns node-sets for node arrays, `response-headers` and XML `response-body`. Namespace prefixes are registered per expression from the element that carries it (`xpathWithString:element:error:` = js2ns.xsl), with a fallback to the candidate node's in-scope declarations. `digest`/`hmac` use CommonCrypto on Apple and OpenSSL (`-lcrypto`) on GNUstep.

---

## Types — `types`

| XSLTForms | XFormsKit |
|---|---|
| `Type.js` / `AtomicType.js` | `XFType` |
| `Schema.js` + `TypeDefs.js` | `+[XFType typeNamed:]` builtin registry |
| `ListType` / `UnionType` | — (atomic only so far) |
| `validate(value)` | `-validateValue:` |
| whitespace preserve/replace/collapse | `XFWhitespace` + `canonicalValue:` |

Namespaces: `xsd`/`xs` → `http://www.w3.org/2001/XMLSchema`, `xf`/`xforms` → XForms. Applied in `XFInstance revalidate` together with required + constraint. Empty values are type-valid unless `required`.

---

## Core elements — `coreelts`

| XSLTForms | XFormsKit | Methods |
|---|---|---|
| `XFCoreElement.js` | (no base; common bits on model/instance) | |
| `XFModel.js` `XsltForms_model` | `XFModel` | `construct`, `rebuild`, `recalculate`, `revalidate`, `refresh`, `reset`, `addChange`, `defaultInstance`, `instanceWithIdentifier:`, `bindWithIdentifier:`, `repeatWithIdentifier:` |
| `XFInstance.js` | `XFInstance` | `construct` (loads `@src`), `reset`, `revalidate` / `validateNode:`, `replaceWithXMLString:`, `documentElement` |
| `XFBind.js` | `XFBind` | `refresh` (nodeset), `recalculate` (`@calculate` + MIP exprs), nested binds |
| `XFSubmission.js` | `XFSubmission` | `submit`, `finishWithResponse:error:context:`, `applyReplacement:`, `serializeNode:method:`, `relevantCopy:`, multipart |
| `AJXTimer.js` | — | extension, not ported |

`XsltForms_browser.getMeta` / `setBoolMeta` → `XFNodeState` associated with `NSXMLNode`.

Dependency tracking is XSLTForms-style (not a W3C MDG): `XFBind.depsNodes`, `XFMIPBinding` per-node cache, `XFModel.nodesChanged` ancestor walk in `addChange:`.

Multiple `xf:model` → `XFProcessor.models` (`.model` is the first). `xf:instance/@src` resolved against `baseURL`.

---

## Actions — `actions`

| XSLTForms | XFormsKit |
|---|---|
| `XFAbstractAction.js` | `XFAbstractAction` (`if` / `while` / `iterate`, `execute`) |
| `XFAction.js` | `XFAction` (group of children) |
| `XFSetvalue.js` | `XFSetvalueAction` |
| `XFDispatch.js` | `XFDispatchAction` |
| `XFMessage.js` | `XFMessageAction` (appends to `XFDeferredUpdates.messages`) |
| `rebuild` / `recalculate` / `revalidate` / `refresh` / `reset` | `XFModelAction` |
| `XFInsert.js` | `XFInsertAction` |
| `XFDelete.js` | `XFDeleteAction` |
| `XFLoad.js` | `XFLoadAction` |
| `XFSetindex.js` | `XFSetindexAction` |
| `XFToggle.js` | `XFToggleAction` |
| `xf:send` | `XFSendAction` |
| `xf:setfocus` | `XFSetfocusAction` |
| `XFScript.js` / `XFSetnode.js` / `XFSetvar.js` / `XFUnload.js` | — |
| `AJXConfirm.js` / `AJXSetproperty.js` | — |

Factory: `+[XFAbstractAction actionWithElement:model:error:]`.

---

## Controls — `controls`

| XSLTForms | XFormsKit | AppKit |
|---|---|---|
| `XFElement.js` / `XFComponent.js` | `XFControl` | |
| `XFControl.js` `refresh` / `changeProp` / `eventDispatch` | `refreshWithContext:` / `applyMIPsFromBoundNode` / `recordMIP:` | |
| `XFInput.js` | `XFInputControl` (+ date helpers) | `NSTextField` / `NSDatePicker` |
| `XFOutput.js` | `XFOutputControl` | `NSTextField` (static) |
| `secret` / `textarea` (via input) | `XFSecretControl` / `XFTextareaControl` | `NSSecureTextField` / `NSTextView` |
| `XFTrigger.js` | `XFTriggerControl` / `XFSubmitControl` | `NSButton` |
| `XFSelect.js` | `XFSelectControl` | `NSPopUpButton` / checkbox / radio |
| `XFItem.js` / `XFItemset.js` | `XFItem` + templates in `XFSelectControl` | |
| `xf:choices` | `XFSelectTemplateChoices` (`XFItem.groupLabel`) | disabled popup headers |
| `xf:copy` | `XFItem.copyNode` + `writeSelection:` | |
| `XFRange.js` | `XFRangeControl` | `NSSlider` |
| `XFGroup.js` | `XFGroup` | `NSBox` / stack |
| `XFRepeat.js` | `XFRepeat` (`index`, `startindex`, `index()`, scroll-first/last) | stacked clones |
| `xf:switch` / `xf:case` | `XFSwitch` | one visible case |
| `XFLabel.js` | `XFLabelControl` (standalone only) | `NSTextField` |
| `XFUpload.js` | `XFUploadControl` | `NSButton` + `NSOpenPanel` |
| `XFAVT.js` | — | no HTML AVTs |
| `XFVar.js` | — | XForms 2 / extension |
| `AJXTree.js` / `Calendar.js` | — / `NSDatePicker` | |

`XFControl` support children: `xf:hint` / `xf:help` / `xf:alert` (literal or `ref`/`value`). MIP flips after `model.ready` dispatch:

| MIP | true event | false event |
|---|---|---|
| relevant | `xforms-enabled` | `xforms-disabled` |
| readonly | `xforms-readonly` | `xforms-readwrite` |
| required | `xforms-required` | `xforms-optional` |
| valid | `xforms-valid` | `xforms-invalid` |

`showHelp` / `showHint` dispatch `xforms-help` / `xforms-hint`; default action appends text to `XFDeferredUpdates.messages`. UI: tooltip = hint (+ alert if invalid), required marks `*`, invalid caption is red.

---

## Submission / transport

| XSLTForms | XFormsKit |
|---|---|
| `XsltForms_submission.submit` | `-[XFSubmission submit]` |
| `synchr` / `mode` | `asynchronous` (`mode="asynchronous"` uses GCD; omitted `@mode` stays sync for tests) |
| `targetref` + `replace=instance` | `replaceNode:withXMLString:` on the bound node |
| `targetref` + `replace=text` | `XFXML setStringValue:ofNode:` |
| `replace=all` | `lastAllReplacement` (no host-document rewrite) |
| `issueSubmitException_` | `fail:type:` (`validation-error`, `resource-error`, `parse-error`, `no-data`, `submission-in-progress`, `target-error`) |
| `requesteventlog` | context keys `response-status-code`, `response-body`, `response-headers`, `response-reason-phrase` |
| serialize XML / urlencoded | `serializeNode:method:` |
| relevant pruning | `relevantCopy:` |
| multipart (limited in JS) | `multipart/form-data`, `multipart/related`, `application/octet-stream` |
| `XMLHttpRequest` | `XFHTTPSubmissionTransport` (`NSURLConnection` sync) |
| test fake | `XFMapSubmissionTransport` |
| request object | `XFSubmissionRequest` (`body`, `bodyData`, `mediaType`, `headers`) |

Upload metadata on the bound node (`XFNodeState.fileName` / `mediaType` / `fileData`) drives file parts.

---

## UI host

| Role | Class |
|---|---|
| Control tree → widgets | `XFFormView` |
| Document-based 3-pane app | `Apps/XFormsViewer` (`XFFormDocument`, `XFDocumentWindowController`) |
| Samples | `Samples/*.xhtml` (XSLTForms samples without the XSLT PI) |

There is no HTML DOM, so CSS class toggles (`xforms-invalid`, …) become AppKit state (enabled, hidden, tooltip, label color).

---

## Tests ↔ XSLTForms suites

Not a 1:1 port of the XSLTForms testsuite. XCTest fixtures:

| File | Covers |
|---|---|
| `XFXPathTests` | parser + core / XForms functions |
| `XFInstanceTests` / `XFModelBindTests` | instance, binds, calculate, MIPs |
| `XFTypeTests` | schema types + revalidate |
| `XFXMLEventsTests` | capture/bubble, ev:listener |
| `XFActionTests` | setvalue, dispatch, deferred updates |
| `XFRepeatGroupTests` / `XFInsertDeleteTests` | group/repeat/insert/delete |
| `XFSubmissionTests` | submit, load, multipart |
| `XFUIControlTests` | widgets, dates, label, select/itemset/copy, upload, hint/help/alert |
| `XFHelloFormTests` | first-slice hello form |

---

## Deliberately not mapped

- XSLT preprocessing and HTML DOM ids (`xsltforms_id`, cloned repeat markup)
- Subforms, `xf:script`, `xf:var`, AJAX extras (`ajx:*`)
- Fleur / XPath 3, maps, arrays
- Plupload path inside `XFUpload.js`
- CSS / XHTML styling (replaced by AppKit)

When adding a feature, prefer the XSLTForms JS method names in comments (`// XsltForms_control.changeProp`) so this table stays the index.
