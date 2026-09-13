/* XFCrashReporter.h — a backtrace on a fatal signal, for builds that run
   where no debugger can follow (the AppImage: gdb loaded against the
   image's libraries does not start).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import <Foundation/Foundation.h>

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
/// `-rdynamic`, by address otherwise. Set XF_NO_CRASH_REPORT to leave
/// the signals alone (a debugger is attached, say).
FOUNDATION_EXPORT void XFInstallCrashReporter(void);

NS_ASSUME_NONNULL_END
