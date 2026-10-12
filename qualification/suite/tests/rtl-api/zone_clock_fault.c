#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>

/* Test-only fault injection into the real libc clock entry point. */
int clock_gettime(clockid_t id, struct timespec *stamp) {
    if (id == CLOCK_MONOTONIC && getenv("MOON_ZONE_CLOCK_FAIL")) {
        errno = EIO;
        return -1;
    }
    int (*real_clock)(clockid_t, struct timespec *) = dlsym(RTLD_NEXT, "clock_gettime");
    if (!real_clock) abort();
    return real_clock(id, stamp);
}
