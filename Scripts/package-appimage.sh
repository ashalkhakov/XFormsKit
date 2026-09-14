#!/bin/bash
# Turn AppDir into an AppImage. Ported from RDLKit's
# Scripts/package-appimage.sh, which came from UDQuakeTools'.
#
#   APP_VERSION=1.2.3 ./Scripts/package-appimage.sh
set -euo pipefail

WORKSPACE_DIR=$(pwd)
LOCAL_PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"
LINUXDEPLOY="${LINUXDEPLOY:-/usr/local/lib/linuxdeploy/AppRun}"

# 1. Copy tracked AppImage metadata/runtime assets into AppDir.
"${WORKSPACE_DIR}/Scripts/appimage/install-assets.sh" "${WORKSPACE_DIR}" "AppDir"

# 2. Gather executable inputs for linuxdeploy.
mapfile -t ELF_BINS < <("${WORKSPACE_DIR}/Scripts/appimage/collect-elf-binaries.sh" "AppDir")
ELF_ARGS=()
for bin in "${ELF_BINS[@]}"; do
    ELF_ARGS+=(--executable "$bin")
done

# 3. Run the linuxdeploy process.
export OUTPUT="XFormsKit-Linux-${APP_VERSION:-dev}-$(uname -m).AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_VALIDATE=1
# Keep the symbol tables: a crash inside the image reports its own
# backtrace (XFCrashReporter.h), and Objective-C methods are named only in
# .symtab, which linuxdeploy's strip would remove. Costs some tens of MB.
export NO_STRIP="${NO_STRIP:-1}"
export LDAI_RUNTIME_FILE="${LDAI_RUNTIME_FILE:-/tmp/appimage-runtime/runtime-x86_64}"

LD_LIBRARY_PATH="${LOCAL_PREFIX}/System/Library/Libraries:${LOCAL_PREFIX}/Local/Library/Libraries:${WORKSPACE_DIR}/AppDir/usr/lib:${LD_LIBRARY_PATH:-}" \
    "$LINUXDEPLOY" --appdir AppDir "${ELF_ARGS[@]}" --output appimage

echo "built $OUTPUT"
