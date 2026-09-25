# XFormsKit

A native XForms 1.1 engine in Objective-C for macOS, iOS and Linux
(GNUstep): it reads an XHTML+XForms document and runs it as a real native
form. `Sources/XFormsKit/` is the engine, `Apps/` holds the viewer, designer,
launcher and the mobile shell.

## GNUstep patches live elsewhere

Fixes to GNUstep itself are not kept here. They live in `../gnustep-patches`,
which this machine's GNUstep projects share, and `.github/scripts/dependencies.sh`
clones that repository at the commit pinned by `GNUSTEP_PATCHES_REF` and
applies what it carries for libs-base, libs-gui and Opal.

If a bug here turns out to be GNUstep's, work in that repository and read its
`CLAUDE.md` first: reproduce in the docker container, fix, turn the
reproduction into a test in GNUstep's own suite, and push it there — that is
where patches are kept and where they are sent upstream from.

## Testing

GNUstep builds and tests run in docker; the macOS side builds against Cocoa.
`Apps/XFormsViewer/Tests/xfviewer-resize-smoke.m` is an end-to-end smoke
test that opens a sample the way the Samples menu does, sweeps a real
pointer over the window, types into fields, maximizes and shrinks it — the
shape worth copying for the other apps. It needs a display, so run it under
`xvfb-run -a`; its own header carries the build recipe.
