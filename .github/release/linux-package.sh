#!/bin/bash
# XFormsKit-<version>-x86_64.AppImage: the launcher, XFormsViewer and
# XFormsDesigner, with the GNUstep runtime, in one file.
set -euo pipefail
GNUSTEP_PREFIX="$PREFIX" ./Scripts/prepare-appdir.sh
GNUSTEP_PREFIX="$PREFIX" ./Scripts/package-appimage.sh
