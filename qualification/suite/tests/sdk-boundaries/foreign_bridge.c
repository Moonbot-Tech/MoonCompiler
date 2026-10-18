#include <unistd.h>
__attribute__((visibility("default"), noinline))
long foreign_bridge(void (*callback)(void)) {
    callback();
    return (long)getpid();
}
