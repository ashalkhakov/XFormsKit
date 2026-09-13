#!/bin/bash
# Put the AppImage's own metadata into AppDir: the launcher, the desktop
# entries and the icons. linuxdeploy insists on a launcher, one desktop file
# and an icon named by it.
#
# The image carries two apps. AppImage has room for one desktop entry at the
# top level, so the VIEWER is the one a desktop launcher starts -- it is what
# opens a form. The designer's entry goes in usr/share/applications, where a
# desktop that reads the mounted image (or an extracted copy) finds it, and it
# is always reachable as `./XFormsKit-Linux-*.AppImage designer`.
set -euo pipefail
workspace_dir=${1:-$(pwd)}
appdir=${2:-AppDir}

mkdir -p "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"

install -m 0755 "$workspace_dir/Scripts/appimage/AppRun" "$appdir/AppRun"
install -m 0644 "$workspace_dir/Scripts/appimage/XFormsViewer.desktop" \
        "$appdir/xformsviewer.desktop"
install -m 0644 "$workspace_dir/Scripts/appimage/XFormsViewer.desktop" \
        "$appdir/usr/share/applications/xformsviewer.desktop"
install -m 0644 "$workspace_dir/Scripts/appimage/XFormsDesigner.desktop" \
        "$appdir/usr/share/applications/xformsdesigner.desktop"

# Each app's own icon, under the name its desktop entry asks for. One file per
# app: the icon in the About panel, on GNUstep's windows and in the launcher is
# the same picture and cannot drift from itself.
install -m 0644 "$workspace_dir/Apps/XFormsViewer/XFormsViewer.png" \
        "$appdir/xformsviewer.png"
install -m 0644 "$workspace_dir/Apps/XFormsViewer/XFormsViewer.png" \
        "$appdir/usr/share/icons/hicolor/256x256/apps/xformsviewer.png"
install -m 0644 "$workspace_dir/Apps/XFormsDesigner/XFormsDesigner.png" \
        "$appdir/usr/share/icons/hicolor/256x256/apps/xformsdesigner.png"

# The opener, under both names GNUstep asks for: "open" is what the
# GSUnknownFileTool default names, "xdg-open" is NSWorkspace's built-in
# fallback. Both go in the bundle's GNUstep tools directory, which
# [NSTask launchPathForTool:] searches before $PATH, and in usr/bin for
# anything that goes through $PATH instead.
mkdir -p "$appdir/usr/System/Tools" "$appdir/usr/bin"
for name in open xdg-open; do
    install -m 0755 "$workspace_dir/Scripts/appimage/open" "$appdir/usr/System/Tools/$name"
    install -m 0755 "$workspace_dir/Scripts/appimage/open" "$appdir/usr/bin/$name"
done
