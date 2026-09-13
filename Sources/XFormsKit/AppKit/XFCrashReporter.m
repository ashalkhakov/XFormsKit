/* XFCrashReporter.m — see XFCrashReporter.h.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1   /* dladdr, dl_iterate_phdr */
#endif
#import "XFCrashReporter.h"

#include <execinfo.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#if defined(__linux__) && !defined(__ANDROID__)
#include <dlfcn.h>
#include <elf.h>
#include <fcntl.h>
#include <link.h>
#include <sys/mman.h>
#include <sys/stat.h>
#define XF_HAVE_ELF_SYMTAB 1
#endif

/* Everything in the handler is async-signal-safe or as near as a crash
   report can be: write(2), backtrace(3) (safe once the unwinder has been
   pulled in, which the install does by taking one backtrace up front), the
   signal calls, and lookups in symbol tables mapped at install time. No
   malloc, no NSLog. */

static void XFWriteString(const char *s)
{
    (void)!write(STDERR_FILENO, s, strlen(s));
}

static void XFWriteHex(unsigned long v)
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

static void XFWriteDecimal(unsigned long v)
{
    char buf[24];
    char *p = buf + sizeof(buf) - 1;
    *p = '\0';
    do {
        *--p = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    XFWriteString(p);
}

static const char *XFSignalName(int sig)
{
    switch (sig) {
        case SIGSEGV: return "SIGSEGV";
        case SIGBUS:  return "SIGBUS";
        case SIGABRT: return "SIGABRT";
        case SIGFPE:  return "SIGFPE";
        case SIGILL:  return "SIGILL";
        default:      return "signal";
    }
}

#if XF_HAVE_ELF_SYMTAB

/* Objective-C methods are local symbols (`t _i_NSView__setFrame_`): they
   are in a library's .symtab but not in its dynamic symbol table, which is
   all backtrace_symbols and dladdr consult. So every loaded module's
   .symtab / .strtab is mapped once, at install, and the handler resolves
   frames against those: the difference between
   "libgnustep-gui.so.0(+0x1c358c)" and "-[NSView removeSubview:]". */

typedef struct {
    uintptr_t base;          /* load address (dlpi_addr) */
    const Elf64_Sym *syms;
    size_t nsyms;
    const char *strs;
    size_t strsSize;
} XFModule;

#define XF_MAX_MODULES 256
static XFModule XFModules[XF_MAX_MODULES];
static int XFModuleCount;

static void XFMapSymbols(const char *path, uintptr_t base)
{
    if (XFModuleCount >= XF_MAX_MODULES) {
        return;
    }
    for (int i = 0; i < XFModuleCount; i++) {
        if (XFModules[i].base == base) {
            return;
        }
    }
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < (off_t)sizeof(Elf64_Ehdr)) {
        close(fd);
        return;
    }
    void *map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED) {
        return;
    }
    const char *file = (const char *)map;
    const Elf64_Ehdr *eh = (const Elf64_Ehdr *)file;
    if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 || eh->e_ident[EI_CLASS] != ELFCLASS64
        || eh->e_shoff == 0 || eh->e_shentsize != sizeof(Elf64_Shdr)
        || eh->e_shoff + (size_t)eh->e_shnum * sizeof(Elf64_Shdr) > (size_t)st.st_size) {
        munmap(map, (size_t)st.st_size);
        return;
    }
    const Elf64_Shdr *sh = (const Elf64_Shdr *)(file + eh->e_shoff);
    for (int i = 0; i < eh->e_shnum; i++) {
        if (sh[i].sh_type != SHT_SYMTAB || sh[i].sh_link >= eh->e_shnum) {
            continue;
        }
        const Elf64_Shdr *strsec = &sh[sh[i].sh_link];
        if (sh[i].sh_offset + sh[i].sh_size > (size_t)st.st_size
            || strsec->sh_offset + strsec->sh_size > (size_t)st.st_size) {
            break;
        }
        XFModule *m = &XFModules[XFModuleCount++];
        m->base = base;
        m->syms = (const Elf64_Sym *)(file + sh[i].sh_offset);
        m->nsyms = sh[i].sh_size / sizeof(Elf64_Sym);
        m->strs = file + strsec->sh_offset;
        m->strsSize = strsec->sh_size;
        return;   /* the mapping stays: the handler reads from it */
    }
    munmap(map, (size_t)st.st_size);   /* stripped: nothing to keep */
}

static int XFVisitModule(struct dl_phdr_info *info, size_t size, void *data)
{
    (void)size;
    (void)data;
    const char *path = info->dlpi_name;
    if (path == NULL || path[0] == '\0') {
        path = "/proc/self/exe";
    }
    XFMapSymbols(path, (uintptr_t)info->dlpi_addr);
    return 0;
}

/// The .symtab function symbol covering `addr`, in the module loaded at
/// `base`; NULL when there is none (a stripped module, or a gap).
static const char *XFSymbolFor(uintptr_t base, uintptr_t addr, unsigned long *offset)
{
    for (int i = 0; i < XFModuleCount; i++) {
        const XFModule *m = &XFModules[i];
        if (m->base != base) {
            continue;
        }
        uintptr_t rel = addr - base;
        const Elf64_Sym *best = NULL;
        for (size_t s = 0; s < m->nsyms; s++) {
            const Elf64_Sym *sym = &m->syms[s];
            if (ELF64_ST_TYPE(sym->st_info) != STT_FUNC || sym->st_value == 0
                || sym->st_name >= m->strsSize) {
                continue;
            }
            if (sym->st_value <= rel && (sym->st_size == 0 ? rel - sym->st_value < 4096
                                                            : rel < sym->st_value + sym->st_size)) {
                if (best == NULL || sym->st_value > best->st_value) {
                    best = sym;
                }
            }
        }
        if (best == NULL) {
            return NULL;
        }
        *offset = rel - best->st_value;
        return m->strs + best->st_name;
    }
    return NULL;
}

static void XFWriteFrame(void *frame)
{
    Dl_info dli;
    uintptr_t addr = (uintptr_t)frame;
    XFWriteString("  ");
    XFWriteHex(addr);
    if (dladdr(frame, &dli) == 0 || dli.dli_fname == NULL) {
        XFWriteString("\n");
        return;
    }
    XFWriteString("  ");
    const char *slash = strrchr(dli.dli_fname, '/');
    XFWriteString(slash ? slash + 1 : dli.dli_fname);
    unsigned long offset = 0;
    /* backtrace() gives return addresses: look one byte back so a call at
       the very end of a method is not filed under the method after it. */
    const char *name = XFSymbolFor((uintptr_t)dli.dli_fbase, addr - 1, &offset);
    if (name == NULL && dli.dli_sname != NULL) {
        name = dli.dli_sname;
        offset = addr - (uintptr_t)dli.dli_saddr;
    }
    if (name != NULL) {
        XFWriteString("  ");
        XFWriteString(name);
        XFWriteString("+");
        XFWriteHex(offset + (name == dli.dli_sname ? 0 : 1));
    } else {
        XFWriteString("  +");
        XFWriteHex(addr - (uintptr_t)dli.dli_fbase);
    }
    XFWriteString("\n");
}

#endif /* XF_HAVE_ELF_SYMTAB */

static void XFCrashHandler(int sig, siginfo_t *info, void *context)
{
    (void)context;
    void *frames[64];
    int n = backtrace(frames, 64);
    XFWriteString("\n==== XFormsKit: fatal ");
    XFWriteString(XFSignalName(sig));
    XFWriteString(" (");
    XFWriteDecimal((unsigned long)sig);
    XFWriteString(")");
    if (sig == SIGSEGV || sig == SIGBUS) {
        XFWriteString(" at address ");
        XFWriteHex((unsigned long)info->si_addr);
    }
    XFWriteString(" -- backtrace, innermost first (_i_Class__sel_ is -[Class sel:], _c_ a class method):\n");
#if XF_HAVE_ELF_SYMTAB
    /* Modules loaded after the install (a theme, a backend bundle) are
       picked up here; mmap at crash time is a risk worth the names. */
    dl_iterate_phdr(XFVisitModule, NULL);
    for (int i = 0; i < n; i++) {
        XFWriteFrame(frames[i]);
    }
#else
    backtrace_symbols_fd(frames, n, STDERR_FILENO);
#endif
    XFWriteString("==== end of backtrace\n");

    /* Die the way the process would have without us: same signal, default
       action, so a core dump still happens where the system keeps them. */
    signal(sig, SIG_DFL);
    raise(sig);
}

void XFInstallCrashReporter(void)
{
    if (getenv("XF_NO_CRASH_REPORT") != NULL) {
        return;
    }
    /* Load the unwinder now (it dlopens libgcc_s the first time), so the
       call in the handler does not allocate. */
    void *warm[4];
    (void)backtrace(warm, 4);
#if XF_HAVE_ELF_SYMTAB
    dl_iterate_phdr(XFVisitModule, NULL);
#endif

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = XFCrashHandler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
    sigemptyset(&sa.sa_mask);
    static const int signals[] = { SIGSEGV, SIGBUS, SIGABRT, SIGFPE, SIGILL };
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
        sigaction(signals[i], &sa, NULL);
    }
}
