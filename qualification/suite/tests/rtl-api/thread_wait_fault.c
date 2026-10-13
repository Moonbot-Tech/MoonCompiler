#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <errno.h>
typedef void *(*lookup_fn)(void *, const char *);
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
