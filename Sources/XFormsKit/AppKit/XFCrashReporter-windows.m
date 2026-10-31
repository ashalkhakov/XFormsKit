/* XFCrashReporter-windows.m — see XFCrashReporter.h: an unhandled
   exception filter, CaptureStackBackTrace.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFCrashReporter.h"

#include <windows.h>
#include <stdlib.h>
#include <string.h>

/* What the filter does is as near async-safe as a crash report can be on
   Windows: WriteFile to the standard error handle, a stack walk, and
   module lookups by address; no malloc, no NSLog. Each frame is a module
   and an offset in it, which llvm-symbolizer (or addr2line) turns into a
   method and a line given the module: the DLLs carry DWARF, not PDBs, so
   DbgHelp would name nothing. */

static void XFWriteString(const char *s)
{
    HANDLE err = GetStdHandle(STD_ERROR_HANDLE);
    DWORD written;
    if (err != NULL && err != INVALID_HANDLE_VALUE) {
        WriteFile(err, s, (DWORD)strlen(s), &written, NULL);
    }
}

static void XFWriteHex(unsigned long long v)
{
    char buf[2 + sizeof(v) * 2 + 1];
    char *p = buf + sizeof(buf) - 1;
    *p = '\0';
    do {
        *--p = "0123456789abcdef"[v & 15];
        v >>= 4;
    } while (v);
    *--p = 'x';
    *--p = '0';
    XFWriteString(p);
}

static const char *XFExceptionName(DWORD code)
{
    switch (code) {
        case EXCEPTION_ACCESS_VIOLATION:      return "access violation";
        case EXCEPTION_ILLEGAL_INSTRUCTION:   return "illegal instruction";
        case EXCEPTION_INT_DIVIDE_BY_ZERO:    return "integer divide by zero";
        case EXCEPTION_STACK_OVERFLOW:        return "stack overflow";
        case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "array bounds exceeded";
        case EXCEPTION_PRIV_INSTRUCTION:      return "privileged instruction";
        case EXCEPTION_IN_PAGE_ERROR:         return "in-page error";
        default:                              return "exception";
    }
}

static void XFWriteFrame(void *frame)
{
    HMODULE module = NULL;
    char path[MAX_PATH];
    XFWriteString("  ");
    XFWriteHex((unsigned long long)(uintptr_t)frame);
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                                | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCSTR)frame, &module)
        || GetModuleFileNameA(module, path, sizeof(path)) == 0) {
        XFWriteString("\n");
        return;
    }
    const char *slash = strrchr(path, '\\');
    XFWriteString("  ");
    XFWriteString(slash ? slash + 1 : path);
    XFWriteString("  +");
    XFWriteHex((unsigned long long)((uintptr_t)frame - (uintptr_t)module));
    XFWriteString("\n");
}

static LONG WINAPI XFCrashFilter(EXCEPTION_POINTERS *pointers)
{
    const EXCEPTION_RECORD *record = pointers->ExceptionRecord;
    void *frames[64];
    USHORT n = CaptureStackBackTrace(0, 64, frames, NULL);
    XFWriteString("\n==== XFormsKit: fatal ");
    XFWriteString(XFExceptionName(record->ExceptionCode));
    XFWriteString(" (");
    XFWriteHex(record->ExceptionCode);
    XFWriteString(") at ");
    XFWriteHex((unsigned long long)(uintptr_t)record->ExceptionAddress);
    if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION
        && record->NumberParameters >= 2) {
        XFWriteString(record->ExceptionInformation[0] == 8 ? ", executing "
                      : record->ExceptionInformation[0] == 1 ? ", writing "
                                                             : ", reading ");
        XFWriteHex((unsigned long long)record->ExceptionInformation[1]);
    }
    XFWriteString(" -- backtrace, innermost first, as module +offset"
                  " (llvm-symbolizer --obj=<module> <offset>):\n");
    XFWriteFrame(record->ExceptionAddress);
    for (USHORT i = 0; i < n; i++) {
        XFWriteFrame(frames[i]);
    }
    XFWriteString("==== end of backtrace\n");

    /* Die the way the process would have without us: the default handling
       (Windows Error Reporting, a debugger if one is set) goes on. */
    return EXCEPTION_CONTINUE_SEARCH;
}

void XFInstallCrashReporter(void)
{
    if (getenv("XF_NO_CRASH_REPORT") != NULL) {
        return;
    }
    SetUnhandledExceptionFilter(XFCrashFilter);
}
