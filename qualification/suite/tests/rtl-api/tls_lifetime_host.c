/* A native host controls the order: Pascal call returns, dlclose, thread exit.
   Neither the host's thread runtime nor its loader is compiled by Moon. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static atomic_int cleaned, finalized;
static const char *path;
static void *library;
static int ready, proceed, hold_loader, detach_first;
static int (*touch)(void);

static void require(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "TLS lifetime: %s\n", message);
        exit(1);
    }
}

static void notify(int event) {
    if (event == 1) atomic_fetch_add(&cleaned, 1);
    if (event == 2) atomic_fetch_add(&finalized, 1);
}

static void wait_for_release(void) {
    pthread_mutex_lock(&lock);
    ready = 1;
    pthread_cond_broadcast(&changed);
    while (!proceed) pthread_cond_wait(&changed, &lock);
    pthread_mutex_unlock(&lock);
}

static void *load(void *unused) {
    (void)unused;
    library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    require(library != NULL, "load library");
    void (*configure)(void (*)(int)) = dlsym(library, "Configure");
    touch = dlsym(library, "Touch");
    require(configure && touch, "resolve exports");
    configure(notify);
    require(touch() == 1001, "fresh module and initial-thread state");
    if (detach_first) {
        void (*detach)(void) = dlsym(library, "Detach");
        require(detach != NULL, "resolve explicit detach");
        detach();
        require(atomic_load(&cleaned) == 1, "explicit DoneThread cleans once");
        require(touch() == 2001, "reattach after explicit DoneThread");
    }
    if (hold_loader) wait_for_release();
    return NULL;
}

static void *foreign(void *unused) {
    (void)unused;
    require(touch() == (detach_first ? 3001 : 2001), "foreign-thread state");
    wait_for_release();
    return NULL;
}

static int available_keys(void) {
    pthread_key_t keys[4096];
    int count = 0, result;
    while (count < 4096 && (result = pthread_key_create(&keys[count], NULL)) == 0)
        ++count;
    require(count < 4096 && result == EAGAIN, "measure TLS key capacity");
    for (int i = 0; i < count; ++i)
        require(pthread_key_delete(keys[i]) == 0, "release probe keys");
    return count;
}

int main(int argc, char **argv) {
    require(argc == 2, "library path argument");
    path = argv[1];
    int keys = available_keys();
    for (int iteration = 0; iteration < 9; ++iteration) {
        pthread_t loader, worker;
        atomic_store(&cleaned, 0);
        atomic_store(&finalized, 0);
        ready = proceed = 0;
        hold_loader = iteration % 3 == 1;
        detach_first = iteration % 3 == 2;
        require(pthread_create(&loader, NULL, load, NULL) == 0, "start loader");
        if (!hold_loader) {
            require(pthread_join(loader, NULL) == 0, "join initial thread");
            require(atomic_load(&cleaned) == 1 + detach_first, "initial thread cleaned while DSO remains live");
            require(pthread_create(&worker, NULL, foreign, NULL) == 0, "start foreign thread");
        }
        pthread_mutex_lock(&lock);
        while (!ready) pthread_cond_wait(&changed, &lock);
        require(dlclose(library) == 0, "release host library reference");
        require(atomic_load(&finalized) == 0, "active TLS pins the library");
        proceed = 1;
        pthread_cond_broadcast(&changed);
        pthread_mutex_unlock(&lock);
        require(pthread_join(hold_loader ? loader : worker, NULL) == 0, "join last TLS owner");
        require(atomic_load(&cleaned) == (hold_loader ? 1 : 2 + detach_first), "each TLS block cleaned once");
        /* glibc collects a DSO unpinned at thread exit on a subsequent dlclose. */
        void *remaining = dlopen(path, RTLD_NOW | RTLD_NOLOAD);
        if (remaining) require(dlclose(remaining) == 0, "collect unpinned module");
        require(atomic_load(&finalized) == 1, "real finalization on a different thread");
        require(available_keys() == keys, "no pthread key leak after unload");
    }
    puts("TLS_LIBRARY_LIFETIME_OK");
    return 0;
}
