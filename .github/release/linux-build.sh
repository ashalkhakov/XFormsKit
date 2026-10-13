#!/bin/bash
# On the stack in $PREFIX, what CI ran: every framework import GNUstep lacks
# is guarded, the framework, its unit tests and the W3C conformance suite
# (under Xvfb: the widget tests and some W3C cases need a display), and the
# apps, which linux-install.sh then installs.
set -eo pipefail
tree="Sources Tests Apps/XFormsViewer Apps/XFormsDesigner Apps/XFormsLauncher"
unguarded=0
for framework in Cocoa UIKit QuartzCore; do
  files=$(grep -rlE "^[[:space:]]*#[[:space:]]*(import|include)[[:space:]]*[<\"]${framework}/" \
            --include="*.h" --include="*.m" $tree || true)
  for f in $files; do
    if ! grep -q "__has_include(<${framework}/${framework}.h>)" "$f"; then
      echo "::error file=$f::imports $framework without a __has_include guard"
      unguarded=1
    fi
  done
done
[ "$unguarded" -eq 0 ] || exit 1
echo "every framework import GNUstep lacks is guarded"

# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
make
xvfb-run -a make check
xvfb-run -a make w3ccheck
make apps
