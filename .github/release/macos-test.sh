#!/bin/bash
# Each app carries the frameworks it links: XFormsKit, and the designer its
# editor's, XFormsDesignKit.
set -euo pipefail
app=$1 name=$(basename "$1" .app)
test -d "$app/Contents/Frameworks/XFormsKit.framework" \
  || { echo "::error::$name.app does not embed XFormsKit.framework"; exit 1; }
if [ "$name" = XFormsDesigner ]; then
  test -d "$app/Contents/Frameworks/XFormsDesignKit.framework" \
    || { echo "::error::$name.app does not embed XFormsDesignKit.framework"; exit 1; }
fi
