#define _GNU_SOURCE
#include <dlfcn.h>
#include <iconv.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

static _Atomic unsigned utf8_opens;

unsigned moon_utf8_open_count(void)
{
    return atomic_load_explicit(&utf8_opens, memory_order_relaxed);
}

iconv_t iconv_open(const char *to, const char *from)
{
    iconv_t (*real_open)(const char *, const char *) = dlsym(RTLD_NEXT, "iconv_open");
    if (!real_open)
        abort();
    if ((!strncmp(to, "UTF-8", 5) && !strcmp(from, "UTF-16LE")) ||
        (!strcmp(to, "UTF-16LE") && !strncmp(from, "UTF-8", 5)))
        atomic_fetch_add_explicit(&utf8_opens, 1, memory_order_relaxed);
    return real_open(to, from);
}
