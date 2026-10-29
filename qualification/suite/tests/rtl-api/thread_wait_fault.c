#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <errno.h>
typedef void *(*lookup_fn)(void *, const char *);
typedef int (*clock_fn)(clockid_t, struct timespec *);
static _Thread_local int deny_clock;
int wait_deny_clock(void) {
    deny_clock = 1;
    return 0;
}
int clock_gettime(clockid_t clock, struct timespec *stamp) {
    /* Fail the calling thread's actual libc/vDSO provider. A syscall-only
       seccomp filter cannot inject an error into a successful vDSO read. */
    if (deny_clock) {
        errno = EPERM;
        return -1;
    }
    clock_fn real = (clock_fn)dlsym(RTLD_NEXT, "clock_gettime");
    return real(clock, stamp);
}
static int broken_join(pthread_t t, void **v, clockid_t c, const struct timespec *d) {
    (void)t; (void)v; (void)c; (void)d;
    return EINVAL;
}
void *dlsym(void *h, const char *name) {
    lookup_fn real = (lookup_fn)dlvsym(RTLD_NEXT,"dlsym","GLIBC_2.2.5");
    const char *mode=getenv("MOON_WAIT_FAULT");
    if (mode && !strcmp(name,"pthread_clockjoin_np")) {
        if (!strcmp(mode,"native-error")) return (void*)broken_join;
        return NULL;
    }
    if (mode && !strcmp(mode,"no-provider") && !strcmp(name,"pthread_tryjoin_np")) return NULL;
    return real(h,name);
}
