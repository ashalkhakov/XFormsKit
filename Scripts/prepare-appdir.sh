#!/bin/bash
# Assemble AppDir. Ported from RDLKit's Scripts/prepare-appdir.sh, which came
# from UDQuakeTools and is known to work; the differences are marked.
#
#   GNUSTEP_PREFIX=/path/to/gnustep ./Scripts/prepare-appdir.sh
#
# Exit immediately if a command exits with a non-zero status
set -e

WORKSPACE_DIR=$(pwd)
# The prefix is built in the same job rather than unpacked into /opt, so it is
# passed in. The default keeps the original behaviour.
LOCAL_PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"

# 1. Recreate clean AppDir structural root
rm -rf AppDir
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/lib
mkdir -p AppDir/usr/etc
mkdir -p AppDir/usr/local/bin

# 2. Source GNUstep environment once
. "${LOCAL_PREFIX}/System/Library/Makefiles/GNUstep.sh"

# 3. Install into the prefix.
# DIFFERENCE from RDLKit: the framework and the two XCTest bundles share one
# GNUmakefile here, so BUNDLE_NAME is overridden to nothing -- a command line
# variable beats the assignment in the makefile. A plain `make install` would
# put the test bundles in the image, and nothing in it runs tests.
make BUNDLE_NAME=
make BUNDLE_NAME= install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
for app in XFormsViewer XFormsDesigner XFormsLauncher; do
    make -C "Apps/$app"
    make -C "Apps/$app" install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
done

if [ -d "${LOCAL_PREFIX}/System/Library/Themes" ]; then
mkdir -p AppDir/usr/System/Library/Themes
cp -Rp "${LOCAL_PREFIX}/System/Library/Themes/"* AppDir/usr/System/Library/Themes/
fi

# 4. Dynamically locate the background tools
for tool in gdnc gpbs make_services; do
FOUND_TOOL=$(find "${LOCAL_PREFIX}" -type f -name "$tool" 2>/dev/null | head -n 1 || true)
if [ -n "$FOUND_TOOL" ]; then
    cp -p "$FOUND_TOOL" AppDir/usr/lib/
    cp -p "$FOUND_TOOL" AppDir/usr/local/bin/
fi
done

# 5. Pull BOTH System and Local hierarchies into AppDir/usr/
if [ -d "${LOCAL_PREFIX}/System" ]; then
mkdir -p AppDir/usr/System
cp -Rp "${LOCAL_PREFIX}/System/"* AppDir/usr/System/
fi
if [ -d "${LOCAL_PREFIX}/Local" ]; then
mkdir -p AppDir/usr/Local
cp -Rp "${LOCAL_PREFIX}/Local/"* AppDir/usr/Local/
fi

# Bundle libobjc from the prefix base lib directory
for libobjc in "${LOCAL_PREFIX}"/lib/libobjc.so.*.*; do
if [ -f "$libobjc" ]; then
    soname=$(basename "$libobjc")
    cp -p "$libobjc" AppDir/usr/lib/
    ln -sf "$soname" "AppDir/usr/lib/${soname%.*}"
    ln -sf "$soname" AppDir/usr/lib/libobjc.so
fi
done

# Bundle libdispatch and its BlocksRuntime dependency safely
echo "=== Manually staging libdispatch and BlocksRuntime ==="
if ls "${LOCAL_PREFIX}/lib"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
elif ls "${LOCAL_PREFIX}/lib64"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib64"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib64"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
fi

# 6. Maintain versioned and unversioned fallback bundle linking
BACKEND_BUNDLE=$(find AppDir/usr -name "libgnustep-back-*.bundle" 2>/dev/null | head -n 1 || true)
if [ -n "$BACKEND_BUNDLE" ]; then
BUNDLE_DIR=$(dirname "$BACKEND_BUNDLE")
# not BUNDLE_NAME: that is the make variable this script overrides above
BACKEND_NAME=$(basename "$BACKEND_BUNDLE")
ln -sfv "$BACKEND_NAME" "$BUNDLE_DIR/libgnustep-back.bundle" || true
ln -sfv "$BACKEND_NAME" "$BUNDLE_DIR/back.bundle" || true
fi

# --- BUNDLE FONTS FOR PORTABILITY ---
# A form's CSS names the fonts its author had, and the host tree is laid out in
# whatever the machine can find. See the README.
mkdir -p AppDir/usr/etc/fonts
cp Scripts/appimage/fonts.conf AppDir/usr/etc/fonts/fonts.conf
for dir in /usr/share/fonts/truetype/dejavu /usr/share/fonts/truetype/liberation \
           /usr/share/fonts/truetype/msttcorefonts; do
if [ -d "$dir" ]; then
    mkdir -p "AppDir/usr/share/fonts/truetype/$(basename "$dir")"
    cp -Rp "$dir"/* "AppDir/usr/share/fonts/truetype/$(basename "$dir")/"
fi
done

# Clean up residual folders
find AppDir -maxdepth 1 -type d ! -name "AppDir" ! -name "usr" -exec rm -rf {} + 2>/dev/null || true

echo "AppDir assembled:"
du -sh AppDir
# All three, or the image is not what it says it is.
missing=0
for app in XFormsViewer XFormsDesigner XFormsLauncher; do
    found=$(find AppDir/usr -maxdepth 5 -name "$app.app" | head -n 1)
    if [ -n "$found" ]; then
        echo "  $found"
    else
        echo "  MISSING: $app.app" >&2
        missing=1
    fi
done
exit $missing
