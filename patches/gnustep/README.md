# GNUstep notes for running XFormsKit on Linux

XFormsKit's test suite (and the apps) exercise gnustep-base harder than
most projects in two places: heavy NSXML mutation, and run-loop-driven
asynchrony. Two things about the gnustep-base build decide whether a
fresh Linux setup passes `make check`.

## 1. The NSXML detached-attribute patch (required)

`gnustep-base-nsxmlnode-detached-attribute-dict-strings.patch` — apply to
the gnustep-base source tree before building:

```sh
cd libs-base
patch -p1 < .../patches/gnustep/gnustep-base-nsxmlnode-detached-attribute-dict-strings.patch
make -j$(nproc) && sudo -E make install
```

Without it, adding or removing ATTRIBUTES on elements of a parsed
NSXMLDocument frees interior pointers of the document's libxml2
dictionary: `setTreeDoc()` in Source/NSXMLNode.m adopts
dictionary-interned strings for text and element nodes when a node moves
between documents, but has no XML_ATTRIBUTE_NODE branch, so a directly
detached attribute (`-removeAttributeForName:`, or the subnode detach
`-dealloc` performs) keeps its name interned in the OLD document's
dictionary and `xmlFreeProp` later frees an interior pointer of it.
Depending on heap layout this is `free(): invalid pointer` /
`munmap_chunk(): invalid pointer` aborts, a segfault at autorelease-pool
drain — or silent luck. In this project the designer's host-XML editing
(XFHostEdit setAttribute/removeAttribute paths, e.g.
`testItemsetAuthoring`) is a reliable trigger on some machines and quiet
corruption on others: `nsxml-detached-attribute-repro.m` beside the patch
is a 30-line standalone reproduction (crashes unpatched, prints
"drained OK" patched; `valgrind -q` shows two deterministic Invalid
free reports unpatched).

The patch comes from the FreeCoreData project (PR #27), which hit the
same bug through Core Data's model files. Upstreaming it to
gnustep/libs-base is the real fix; until then it travels here.

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
