#! /usr/bin/env sh
#
# Build the GNUstep stack XFormsKit needs, from source, into $INSTALL_PATH.
#
# Ported from the RDLKit project's CI, which follows the recipe from the
# gnustep-build repository. The four things that matter and that a
# Foundation-only CI script would leave out:
#
#   --with-layout=gnustep    the cohesive System/Local hierarchy rather than
#                            the flattened bin/lib/share one.
#   --enable-objc-arc        XFormsKit is ARC throughout.
#   CPPFLAGS/LDFLAGS         point the compiler at the prefix so configure
#                            actually detects the libobjc2 built a step
#                            earlier, instead of falling back silently.
#   standalone.conf          makes libs-base read its config from the prefix,
#                            so the tree can be moved.
#
# XFormsKit needs more of the stack than a Foundation-only project would:
# XFFormView draws through AppKit, so libs-gui and a graphics backend are
# required, both test bundles are XCTest, so tools-xctest is too, the SVG
# renderer draws through Opal (and Opal through libs-corebase), and the
# packaged apps ship with the Eau theme, which has to be built against the
# same gui it will be loaded into.
#
# Expects: CC, CXX, LIBRARY_COMBO, RUNTIME_VERSION, DEPS_PATH, INSTALL_PATH.
set -ex

# Captured before anything cds away: the patches below are named relative
# to the checkout.
WORKSPACE_DIR=$(pwd)

mkdir -p "$DEPS_PATH"

# With --with-layout=gnustep this is where tools-make puts the makefiles.
GNUSTEP_SH="$INSTALL_PATH/System/Library/Makefiles/GNUstep.sh"

# libobjc2 and libdispatch are installed by cmake into $INSTALL_PATH/lib, which
# under this layout is *not* one of the GNUstep library roots -- those are under
# System/Library/Libraries. Nothing would add it to the loader path otherwise,
# and configure would decide the runtime is missing.
export LD_LIBRARY_PATH="$INSTALL_PATH/lib:${LD_LIBRARY_PATH:-}"
export C_INCLUDE_PATH="$INSTALL_PATH/include:${C_INCLUDE_PATH:-}"
export CPLUS_INCLUDE_PATH="$INSTALL_PATH/include:${CPLUS_INCLUDE_PATH:-}"

install_libobjc2() {
    echo "::group::libobjc2"
    cd "$DEPS_PATH"
    git clone -q --recursive https://github.com/gnustep/libobjc2.git
    cd libobjc2
    mkdir -p build && cd build
    cmake -DTESTS=off \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DGNUSTEP_INSTALL_TYPE=NONE \
          -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_PATH" \
          -DCMAKE_C_COMPILER="$CC" \
          -DCMAKE_CXX_COMPILER="$CXX" \
          ../
    make install
    echo "::endgroup::"
}

install_libdispatch() {
    echo "::group::libdispatch"
    cd "$DEPS_PATH"
    git clone -q https://github.com/swiftlang/swift-corelibs-libdispatch.git libdispatch
    mkdir -p libdispatch/build && cd libdispatch/build
    # -Wno-error=void-pointer-to-int-cast works around a -Werror build failure
    # in queue.c; taken from libs-gui's script.
    cmake -DBUILD_TESTING=off \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_PATH" \
          -DCMAKE_C_FLAGS="-Wno-error=void-pointer-to-int-cast" \
          -DINSTALL_PRIVATE_HEADERS=1 \
          -DBlocksRuntime_INCLUDE_DIR="$INSTALL_PATH/include" \
          -DBlocksRuntime_LIBRARIES="$INSTALL_PATH/lib/libobjc.so" \
          ../
    make install
    echo "::endgroup::"
}

install_tools_make() {
    echo "::group::GNUstep Make"
    cd "$DEPS_PATH"
    git clone -q -b ${TOOLS_MAKE_BRANCH:-master} https://github.com/gnustep/tools-make.git
    cd tools-make
    ./configure --prefix="$INSTALL_PATH" \
                --with-layout=gnustep \
                --with-library-combo="$LIBRARY_COMBO" \
                --with-runtime-abi="$RUNTIME_VERSION" \
                --enable-objc-arc \
                CPPFLAGS="-I$INSTALL_PATH/include" \
                LDFLAGS="-L$INSTALL_PATH/lib -Wl,-rpath,$INSTALL_PATH/lib" \
                CC="$CC" CXX="$CXX" || cat config.log
    make install
    . "$GNUSTEP_SH"
    gnustep-config --objc-flags
    echo "::endgroup::"
}

install_libs_base() {
    echo "::group::GNUstep Base"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_BASE_BRANCH:-master} https://github.com/gnustep/libs-base.git
    cd libs-base
    # Required for this project: -[NSXMLElement addAttribute:] frees the
    # private document of a prefixed attribute while the attribute's value
    # nodes still point at it, and the next -detach reads freed memory. With
    # the libxml2 2.9.x Ubuntu ships that is a segfault in the designer's
    # host-XML editing (testActionAuthoring); a libs-base built against
    # libxml2 2.12+ repairs the pointer by accident, which is why the crash
    # is invisible on a workstation. See patches/gnustep/README.md, which
    # also carries a standalone reproduction. (The earlier detached-attribute
    # patch this project carried has been upstreamed and is not applied.)
    #
    # Only the default (NSXML) configuration depends on this. Built against
    # XFDOM the engine never touches gnustep-base's NSXML at all.
    patch -p1 < "$WORKSPACE_DIR/patches/gnustep/gnustep-base-nsxmlelement-addattribute-value-doc.patch"
    # The reference recipe names $PREFIX/etc/GNUstep.conf here. This
    # gnustep-make writes it to $PREFIX/etc/GNUstep/GNUstep.conf instead, and
    # when the named file does not exist libs-base falls back to the built-in
    # standalone.conf defaults, which put every root at ./ relative to it --
    # so gnustep-gui looks for the backend in $PREFIX/etc and reports
    #
    #   Did not find correct version of backend (libgnustep-back-032.bundle)
    #   NSApplication.m:306 Assertion failed ... Unable to find backend back
    #
    # while the bundle sits in Local/Library/Bundles. Ask gnustep-make where
    # it actually put the file rather than naming a path.
    ./configure --prefix="$INSTALL_PATH" \
                --with-config-file="$(gnustep-config --variable=GNUSTEP_CONFIG_FILE)" \
                --with-default-config=standalone.conf || cat config.log
    make
    make install
    echo "::endgroup::"
}

install_libs_gui() {
    echo "::group::GNUstep GUI"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_GUI_BRANCH:-master} https://github.com/gnustep/libs-gui.git
    cd libs-gui
    # -[GSCSTableau removeRowForVariable:] uses a row expression after the
    # row dictionary, its only owner, has released it, so every resize of a
    # window that has a layout engine is a use-after-free. See
    # patches/gnustep/README.md, which also carries a standalone
    # reproduction. The viewer no longer engages the engine on GNUstep (it
    # skipped -layoutSubtreeIfNeeded), so XFormsKit itself does not depend
    # on this patch -- but anything drawn by gnustep-gui that does use
    # Auto Layout, and the AppImage's users, do.
    patch -p1 < "$WORKSPACE_DIR/patches/gnustep/gnustep-gui-gscstableau-removerow-use-after-free.patch"
    ./configure --prefix="$INSTALL_PATH" || cat config.log
    make install
    echo "::endgroup::"
}

# Without a backend nothing draws, and XFFormView's tests build real widgets.
install_libs_back() {
    echo "::group::GNUstep Back (cairo)"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_BACK_BRANCH:-master} https://github.com/gnustep/libs-back.git
    cd libs-back
    ./configure --prefix="$INSTALL_PATH" --enable-graphics=cairo || cat config.log
    make install
    # gnustep-gui asks for the backend by version -- libgnustep-back-032.bundle
    # -- and master's gui and back do not always agree on it, which reports as
    #
    #   Did not find correct version of backend (libgnustep-back-032.bundle)
    #   NSApplication.m:306 Assertion failed ... Unable to find backend back
    bundle=$(find "$INSTALL_PATH" -name 'libgnustep-back-*.bundle' | head -n 1)
    if [ -n "$bundle" ]; then
        dir=$(dirname "$bundle")
        name=$(basename "$bundle")
        ln -sfv "$name" "$dir/libgnustep-back.bundle"
        ln -sfv "$name" "$dir/back.bundle"
    fi
    echo "::endgroup::"
}

# CoreGraphics and CoreText for GNUstep. The SVG renderer draws through
# both, and they are the one drawing API present on all three targets --
# see docs/ios-port-plan.md phase 2. Built after libs-back so it can pick
# up the same cairo the backend uses.
#
# libs-corebase first: Opal falls back to stub CF types without it, and
# the renderer wants real CFStringRef for font names.
install_libs_corebase() {
    echo "::group::GNUstep CoreBase"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q https://github.com/gnustep/libs-corebase.git
    cd libs-corebase
    # corebase's toll-free bridge probe is AC_CHECK_HEADERS(objc/runtime.h)
    # followed by AC_SEARCH_LIBS(objc_getClass, [objc objc2]). The runtime
    # built in the first step lives in this prefix, and neither probe looks
    # there on its own -- C_INCLUDE_PATH covers the header but the link test
    # needs a -L, and LD_LIBRARY_PATH is a RUNTIME path, not a link one.
    # Without these it fails with "Objective-C library not found!".
    ./configure --prefix="$INSTALL_PATH" \
                CPPFLAGS="-I$INSTALL_PATH/include" \
                LDFLAGS="-L$INSTALL_PATH/lib -Wl,-rpath,$INSTALL_PATH/lib" \
                || cat config.log
    make
    make install
    echo "::endgroup::"
}

install_libs_opal() {
    echo "::group::Opal (CoreGraphics + CoreText)"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q https://github.com/gnustep/libs-opal.git
    cd libs-opal
    # No configure script: Opal is a plain gnustep-make project. Only the
    # Source subproject is built -- the aggregate also builds Tests, which
    # is a set of example tools this build has no use for and would only
    # add ways to fail.
    # CGRectUnion stores the union's far edges as its SIZE instead of
    # subtracting the origin it just chose, so any union away from the
    # origin comes out far too large. See patches/gnustep/README.md.
    patch -p1 < "$WORKSPACE_DIR/patches/gnustep/opal-cgrectunion-size.patch"
    make -C Source
    # OpalGraphics/GNUmakefile.postamble finishes the install by copying the
    # ImageIO headers into GNUSTEP_SYSTEM_HEADERS with a bare `cp -r`: no
    # mkdir, and regardless of the installation domain, which here is LOCAL
    # (Opal's own headers land in Local/Library/Headers/CoreGraphics). The
    # System headers directory does not exist in this prefix, so the copy
    # fails and takes the install down with it. Creating the directory it
    # assumes is cheaper than carrying a patch for headers nothing here
    # uses -- XFormsKit imports CoreGraphics and CoreText, not ImageIO.
    mkdir -p "$(gnustep-config --variable=GNUSTEP_SYSTEM_HEADERS)"
    make -C Source install
    echo "::endgroup::"
}

# The look users expect on Linux. It is a theme bundle that gnustep-gui
# dlopens at runtime, so it has to be inside the AppImage and it has to be
# selected -- Scripts/appimage/AppRun does the selecting. Built here rather
# than shipped prebuilt because a theme links against the same gui it will be
# loaded into.
install_eau_theme() {
    echo "::group::Eau theme"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q --depth 1 https://github.com/gershwin-desktop/gershwin-eau-theme.git Eau
    cd Eau
    # The theme uses blocks, and nothing in a theme bundle's link line pulls
    # the runtime in on its own. BlocksRuntime is only a separate library when
    # libdispatch built its own; ours is told to use libobjc's, so ask for it
    # only if it is there.
    ldflags="-L$INSTALL_PATH/lib -Wl,-rpath,$INSTALL_PATH/lib -ldispatch"
    if [ -e "$INSTALL_PATH/lib/libBlocksRuntime.so" ]; then
        ldflags="$ldflags -lBlocksRuntime"
    fi
    make ADDITIONAL_LDFLAGS="$ldflags"
    make install
    echo "::endgroup::"
}

install_tools_xctest() {
    echo "::group::tools-xctest"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q https://github.com/gnustep/tools-xctest.git
    cd tools-xctest
    make install
    echo "::endgroup::"
}

# Order matters: the runtime is built before tools-make, because configuring
# tools-make with --with-runtime-abi=gnustep-2.0 probes for it, and libdispatch
# needs BlocksRuntime from it. Everything after that needs GNUstep.sh, which
# tools-make installs.
install_libobjc2
install_libdispatch
install_tools_make
install_libs_base
install_libs_gui
install_libs_back
install_libs_corebase
install_libs_opal
install_eau_theme
install_tools_xctest

echo "=== the prefix ==="
find "$INSTALL_PATH" -maxdepth 3 -type d | sort
