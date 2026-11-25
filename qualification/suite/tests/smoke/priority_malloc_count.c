#include <stddef.h>

static _Thread_local int tracking;
static _Thread_local unsigned int calls;

extern void *__real_malloc(size_t);

void *__wrap_malloc(size_t size)
{
    if (tracking)
        ++calls;
    return __real_malloc(size);
}

void begin_count(void)
{
    calls = 0;
    tracking = 1;
}

unsigned int end_count(void)
{
    tracking = 0;
    return calls;
}
