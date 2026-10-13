#!/bin/bash
# XFormsKit's sources, checked before its tests (make check, on GNUstep and
# on the Mac), from the repository's root:
#   * every framework import GNUstep lacks (Cocoa, UIKit, QuartzCore) is
#     guarded by __has_include;
#   * XFDOMTests still compares XFDOM against NSXML: a rename that pointed
#     both sides at XFDOM would leave it green, testing nothing;
#   * the viewer offers every sample: its Samples menu is a hand-written list,
#     and the GNUstep build copies the same files by name.
set -euo pipefail
failed=0
tree="Sources Tests Apps/XFormsViewer Apps/XFormsDesigner Apps/XFormsLauncher"
for framework in Cocoa UIKit QuartzCore; do
  files=$(grep -rlE "^[[:space:]]*#[[:space:]]*(import|include)[[:space:]]*[<\"]${framework}/" \
            --include="*.h" --include="*.m" $tree || true)
  for f in $files; do
    grep -q "__has_include(<${framework}/${framework}.h>)" "$f" \
      || { echo "$f: imports $framework without a __has_include guard"; failed=1; }
  done
done
grep -q "NSXMLDocument" Tests/XFormsKitTests/XFDOMTests.m \
  || { echo "Tests/XFormsKitTests/XFDOMTests.m: no longer references NSXML; it is no longer differential"; failed=1; }
for f in Samples/*.xhtml; do
  name=$(basename "$f")
  grep -q "\"$name\"" Apps/XFormsViewer/main.m \
    || { echo "Apps/XFormsViewer/main.m: $name is not in the Samples menu"; failed=1; }
  grep -q "Samples/$name" Apps/XFormsViewer/GNUmakefile \
    || { echo "Apps/XFormsViewer/GNUmakefile: $name is not copied into the GNUstep bundle"; failed=1; }
done
[ "$failed" = 0 ] && echo "check-sources: imports guarded, XFDOMTests differential, every sample offered"
exit "$failed"
