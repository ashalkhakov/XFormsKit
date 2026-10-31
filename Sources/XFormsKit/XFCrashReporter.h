/* XFCrashReporter.h — a backtrace on a fatal signal, for builds that run
   where no debugger can follow (the AppImage: gdb loaded against the
   image's libraries does not start; the Windows installer's runtime).
   XFCrashReporter-posix.m is Linux's, XFCrashReporter-windows.m Windows'.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import <Foundation/Foundation.h>

/* XFormsKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef XFORMSKIT_EXPORT
#define XFORMSKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

/// Installs handlers for SIGSEGV, SIGBUS, SIGABRT, SIGFPE and SIGILL that
/// write the signal, the faulting address and a symbolised backtrace to
/// stderr, then restore the default action and re-raise, so the process
/// still dies (and still dumps core) the way it would have.
///
/// The names come from the dynamic symbol tables, which is what the
/// GNUstep libraries and the XFormsKit framework export their methods
/// through (`_i_NSView__removeSubview_` is `-[NSView removeSubview:]`);
/// an application's own methods show by name when it is linked with
/// `-rdynamic`, by address otherwise. On Windows an unhandled exception
/// filter writes the exception, its address and the frames as module and
/// offset (the DLLs carry DWARF, which llvm-symbolizer reads), and the
/// default handling goes on. Set XF_NO_CRASH_REPORT to leave the signals
/// alone (a debugger is attached, say).
XFORMSKIT_EXPORT void XFInstallCrashReporter(void);

NS_ASSUME_NONNULL_END
