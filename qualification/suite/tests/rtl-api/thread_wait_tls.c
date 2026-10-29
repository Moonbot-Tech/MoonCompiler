#define _GNU_SOURCE
#include <pthread.h>
#include <stdatomic.h>
#include <unistd.h>
#include <stdlib.h>
static pthread_key_t key;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static atomic_int state, released;
static int key_created;
static void teardown(void *p) {
    (void)p;
    atomic_store(&state,1);
    while (!atomic_load(&released)) usleep(1000);
    atomic_store(&state,2);
}
static void init(void) {
    if (pthread_key_create(&key,teardown)) abort();
    key_created=1;
}
void wait_tls_arm(void) {
    pthread_once(&once,init);
    if (pthread_setspecific(key,(void*)1)) abort();
}
void wait_tls_release(void) { atomic_store(&released,1); }
int wait_tls_state(void) { return atomic_load(&state); }
__attribute__((destructor)) static void cleanup(void) { if (key_created) pthread_key_delete(key); }
