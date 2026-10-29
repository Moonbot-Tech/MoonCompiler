#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

/* Only the test process is affected. Never change the machine's clock. */
int clock_gettime(clockid_t id, struct timespec *stamp) {
    const char *mode = getenv("MOON_TICK_TEST");
    if (mode && id == CLOCK_MONOTONIC) {
        if (!strcmp(mode, "fixed")) {
            stamp->tv_sec = 6000000;
            stamp->tv_nsec = 123456789;
            return 0;
        }
        if (!strcmp(mode, "fail")) {
            errno = EIO;
            return -1;
        }
    }
    int (*real_clock)(clockid_t, struct timespec *) = dlsym(RTLD_NEXT, "clock_gettime");
    if (!real_clock) abort();
    return real_clock(id, stamp);
}

int gettimeofday(struct timeval *stamp, void *zone) {
    const char *mode = getenv("MOON_CALENDAR_TEST");
    if (mode && !strcmp(mode, "fixed")) {
        stamp->tv_sec = 1700000123;
        stamp->tv_usec = 456000;
        return 0;
    }
    if (mode && !strcmp(mode, "fail")) {
        errno = EIO;
        return -1;
    }
    int (*real_time)(struct timeval *, void *) = dlsym(RTLD_NEXT, "gettimeofday");
    if (!real_time) abort();
    return real_time(stamp, zone);
}
