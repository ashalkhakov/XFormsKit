#!/bin/bash
# The version stamped; prepare-appdir.sh (linux-package.sh) builds the
# framework, the viewer and the designer.
set -euo pipefail
./Scripts/stamp-version.sh "$APP_VERSION"
