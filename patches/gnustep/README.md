# GNUstep notes for running XFormsKit on Linux

XFormsKit's test suite (and the apps) exercise gnustep-base harder than
most projects in two places: heavy NSXML mutation, and run-loop-driven
asynchrony. The notes below are what a fresh Linux setup needs to know;
the one patch this directory used to carry is now upstream.

## 1. The NSXML detached-attribute bug (fixed upstream — nothing to do)

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

Worth knowing either way: built against XFDOM (`XF_PORTABLE_DOM=1`) the
engine never touches gnustep-base's NSXML at all, so this class of
gnustep-base XML bug cannot reach it.

## 2. Run-loop asynchrony without GS_USE_LIBDISPATCH_RUNLOOP

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

## 3. Run-loop mode gotcha (engine-internal, for the record)

GNUstep takes `NSRunLoopCommonModes` literally — a timer added ONLY for
that "mode" never fires, because no run loop ever runs a mode by that
name (Apple expands it to the common-mode set). Timers meant to fire on
both platforms are registered for `NSDefaultRunLoopMode` AND
`NSRunLoopCommonModes`.
