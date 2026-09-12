# GNUstep notes for running XFormsKit on Linux

XFormsKit exercises the GNUstep stack harder than most projects in three
places: heavy NSXML mutation, run-loop-driven asynchrony, and — since the
SVG renderer moved to CoreGraphics — Opal. The notes below are what a
fresh Linux setup needs to know.

This directory carries two patches, both applied by
`.github/scripts/dependencies.sh`: one to gnustep-base (section 1) and one
to Opal (section 2). A third, older one is now upstream (section 3).

## 1. gnustep-base: the NSXML addAttribute: use-after-free (patch applied)

`gnustep-base-nsxmlelement-addattribute-value-doc.patch` — applied to
libs-base by `.github/scripts/dependencies.sh` before building, and needed
by any hand-built gnustep-base too. `nsxml-addattribute-dangling-doc.m`
beside it is a Foundation-only reproduction that exits 1 on an unpatched
library and shows the invalid read under valgrind.

Symptom: `make check` (NSXML configuration) segfaults in
`XFUIControlTests testActionAuthoring` on Ubuntu 24.04 —

```
xmlDictOwns (dict=…, str="DOMActivate") at dict.c:1223
adoptString → setTreeDoc → -[NSXMLNode detach] → -[XFHostEdit deleteElement:]
```

— and passes on a workstation whose gnustep-base was built against
libxml2 2.12 or newer. It is not flaky in the usual sense: the dangling
pointer is created deterministically, and only whether *reading* it
crashes depends on what the allocator has since put in the freed chunk.

Mechanism: `-[NSXMLNode setName:]` with a prefix it cannot resolve (an
`ev:event` attribute built before its element is in the document) makes a
placeholder `xmlNs` with no href and a private `xmlDoc` to hold it.
`-[NSXMLElement addAttribute:]` then moves the attribute into the element
with `xmlDOMWrapAdoptNode()`, which refuses a namespace without an href —
after setting `attr->doc`, before walking the value nodes — and returns
-1. `addAttribute:` ignores the result and frees the private document, so
the attribute's text node still points at it. Every libxml2 from 2.9 to
2.13 fails the adoption the same way; the difference is that a gnustep-base
compiled against 2.12+ uses its own `updateTreeDocManually()` when the
element is later inserted, which rewrites every pointer under the element
and repairs the attribute by accident, whereas against 2.9.x it uses
`xmlDOMWrapAdoptNode()` again, whose source-document sanity check skips
exactly the node that needs fixing.

The patch checks the result of `xmlDOMWrapAdoptNode()` and, when it fails,
moves the attribute subtree with `xmlSetTreeDoc()` before the private
document is freed. gnustep-base's own NSXML suites (524 tests) pass with it
on libxml2 2.9.14 and 2.13.8; the XFormsKit suites pass on both.

This is distinct from the `xmlns:`-attribute crash RDLKit carries a patch
for (a placeholder namespace with the reserved `xmlns` prefix, torn down
through `-detach`); both live in the same "fake the namespace, fix it
later" corner of NSXMLNode, and neither is upstream yet.

## 2. Opal: CGRectUnion returns the far edges as the size (patch applied)

`opal-cgrectunion-size.patch` — applied to libs-opal by
`.github/scripts/dependencies.sh` before building.

`CGRectUnion` in `Source/OpalGraphics/CGGeometry.m` takes the minimum of
the two origins, and then stores the maximum of the two far edges
**directly into `size`**. Those are absolute coordinates; the size has to
be that far edge minus the origin just chosen. Rectangles at the origin
come out right, which is why it survives casual use; everything else
comes out far too large.

XFormsKit's SVG renderer meets it in `-[XFSVGDocument frameOfElement:]`,
which maps a shape's bounding box through its transform and unions the
four mapped corners. A 20×20 rect under `translate(100,10)` answered a
width of 320 rather than 20 (origin and height-origin were right, which
is the tell: only the size was wrong). `testSVGPaintServersUseAndHitTesting`
catches it.

This one is worth sending upstream; unlike section 3 it is not fixed
there yet.

## 3. gnustep-base: the NSXML detached-attribute bug (fixed upstream — nothing to do)

This project used to carry
`gnustep-base-nsxmlnode-detached-attribute-dict-strings.patch`, which had
to be applied to gnustep-base before building. **It has been upstreamed**,
so a current libs-base needs no patch and none is applied by
`.github/scripts/dependencies.sh`. The patch and its reproduction have
been deleted; this note stays because the failure is worth recognising if
you ever build against an older gnustep-base.

`setTreeDoc()` in `Source/NSXMLNode.m` adopted dictionary-interned strings
for text and element nodes when a node moved between documents, but had no
`XML_ATTRIBUTE_NODE` branch. A directly detached attribute
(`-removeAttributeForName:`, or the subnode detach `-dealloc` performs)
therefore kept its name interned in the OLD document's libxml2 dictionary,
and `xmlFreeProp` later freed an interior pointer of it. Depending on heap
layout that is a `free(): invalid pointer` / `munmap_chunk(): invalid
pointer` abort, a segfault at autorelease-pool drain — or silent luck. In
this project the designer's host-XML editing (XFHostEdit
setAttribute/removeAttribute, e.g. `testItemsetAuthoring`) was a reliable
trigger on some machines and quiet corruption on others.

The fix came from the FreeCoreData project (PR #27), which hit the same bug
through Core Data's model files.

Worth knowing either way: the engine is built against XFDOM everywhere
now, so it never touches gnustep-base's NSXML at all and this class of
gnustep-base XML bug cannot reach it. Section 1's patch is still applied
because `XFDOMTests` uses NSXML as a reference oracle, and because a
gnustep-base built without it is broken for anyone else's NSXML code —
but the engine no longer depends on it.

## 4. Run-loop asynchrony without GS_USE_LIBDISPATCH_RUNLOOP

gnustep-base only drains the libdispatch MAIN queue from NSRunLoop when
it was configured with libdispatch development headers available
(`GS_USE_LIBDISPATCH_RUNLOOP` in the installed
`GNUstepBase/GSConfig.h`). On Ubuntu there is no packaged
`libdispatch-dev`, so a fresh gnustep-base build usually has it OFF —
and then anything scheduled with `dispatch_async(dispatch_get_main_queue(),…)`
or `dispatch_after(…, dispatch_get_main_queue(), …)` NEVER runs, no
matter how long the run loop spins.

XFormsKit does not depend on that integration (since mac state 64):
asynchronous submissions land back on the main thread through
`performSelectorOnMainThread:` and `xf:dispatch delay=` uses an NSTimer
on the main run loop — both work on any gnustep-base build and on
Apple. (`dispatch_once` and background-queue work need only libdispatch
itself, which the build already links via `-ldispatch`.)

If you saw these two failures on a fresh install, they are this issue on
an engine older than mac state 64:

```
testAsyncModeCompletesOnRunLoop FAILED   (async submission did not finish)
testDispatchChildrenPropertiesDelayAndDefaultSubmitTarget FAILED
```

To check a gnustep-base build:
`grep GS_USE_LIBDISPATCH_RUNLOOP $(gnustep-config --variable=GNUSTEP_SYSTEM_HEADERS)/GNUstepBase/GSConfig.h`

## 5. Run-loop mode gotcha (engine-internal, for the record)

GNUstep takes `NSRunLoopCommonModes` literally — a timer added ONLY for
that "mode" never fires, because no run loop ever runs a mode by that
name (Apple expands it to the common-mode set). Timers meant to fire on
both platforms are registered for `NSDefaultRunLoopMode` AND
`NSRunLoopCommonModes`.
