/* Random bits, on every platform the engine builds for.
   arc4random is in libc on Apple's platforms and in glibc from 2.36; glibc
   before that (Ubuntu 22.04's 2.35, which the AppImage is built on) does
   not declare it, and a call compiled without a declaration returns int,
   so the high bit came back as a sign: XPath's random() answered -0.3.
   There getrandom(2) gives the same bits.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#include <stdint.h>
#include <stdlib.h>

#if defined(__GLIBC__)
#  if !__GLIBC_PREREQ(2, 36)
#    define XF_RANDOM_GETRANDOM 1
#    include <sys/random.h>
#  endif
#endif

/// 32 random bits.
static inline uint32_t XFRandomUInt32(void)
{
#if defined(XF_RANDOM_GETRANDOM)
    uint32_t value = 0;
    if (getrandom(&value, sizeof value, 0) != (ssize_t)sizeof value) {
        value = (uint32_t)random() ^ ((uint32_t)random() << 16);
    }
    return value;
#else
    return arc4random();
#endif
}
