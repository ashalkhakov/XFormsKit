#!/bin/bash
# The framework (without its XCTest bundles: BUNDLE_NAME emptied on the command line beats the makefile), the designer's editor and the three apps into the prefix's System domain, where gnustep-release-actions'
# appimage takes them from.
set -eo pipefail
# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
make BUNDLE_NAME= install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C Sources/XFormsDesignKit install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
for app in XFormsViewer XFormsDesigner XFormsLauncher; do
  make -C "Apps/$app" install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
done
