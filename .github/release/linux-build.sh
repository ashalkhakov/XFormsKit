#!/bin/bash
# The version stamped; linux-install.sh builds and installs the framework,
# the viewer and the designer.
set -euo pipefail
./Scripts/stamp-version.sh "$APP_VERSION"
