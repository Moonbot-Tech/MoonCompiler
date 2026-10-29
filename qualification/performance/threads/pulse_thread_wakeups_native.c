#define _GNU_SOURCE
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>

/* Native pthread reference for pulse_thread_wakeups.dpr paced-event.
   Same per-worker binary signal, numbered rounds, acknowledgement, pacing,
   and measurement boundaries. Not a replacement implementation of TEvent:
   concurrent destruction and the other RTL contracts are outside this probe. */
typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    bool set, manual;
} event;

typedef struct {
    pthread_t thread;
    event wake;
    uint64_t wakes, sequence_sum;
} worker;

static event gate, round_ack, main_wake;
static worker *workers;
static atomic_int ready, completed, round_done, published_round;
static int worker_count, rounds, period_ms, recursive_mutex;
static uint64_t dispatch_late_ns;

static void check(int error, const char *operation) {
    if (error) {
        fprintf(stderr, "%s: %s\n", operation, strerror(error));
        exit(1);
    }
}

static uint64_t wall_ns(void) {
    struct timespec stamp;
    if (clock_gettime(CLOCK_MONOTONIC, &stamp)) { perror("clock_gettime"); exit(1); }
    return (uint64_t)stamp.tv_sec * 1000000000 + stamp.tv_nsec;
}

static void sleep_ms(uint64_t milliseconds) {
    struct timespec delay = { milliseconds / 1000, (milliseconds % 1000) * 1000000 };
    while (nanosleep(&delay, &delay)) {
        if (errno != EINTR) { perror("nanosleep"); exit(1); }
    }
}

static void event_init(event *e, bool manual) {
    pthread_mutexattr_t ma;
    pthread_condattr_t ca;
    check(pthread_mutexattr_init(&ma), "mutexattr_init");
    if (recursive_mutex) check(pthread_mutexattr_settype(&ma, PTHREAD_MUTEX_RECURSIVE), "mutexattr_settype");
    check(pthread_mutex_init(&e->mutex, &ma), "mutex_init");
    check(pthread_mutexattr_destroy(&ma), "mutexattr_destroy");
    check(pthread_condattr_init(&ca), "condattr_init");
    check(pthread_condattr_setclock(&ca, CLOCK_MONOTONIC), "condattr_setclock");
    check(pthread_cond_init(&e->condition, &ca), "cond_init");
    check(pthread_condattr_destroy(&ca), "condattr_destroy");
    e->set = false;
    e->manual = manual;
}

static void event_set(event *e) {
    pthread_mutex_lock(&e->mutex);
    e->set = true;
    if (e->manual) pthread_cond_broadcast(&e->condition);
    else pthread_cond_signal(&e->condition);
    pthread_mutex_unlock(&e->mutex);
}

static bool event_wait(event *e, int timeout_ms) {
    pthread_mutex_lock(&e->mutex);
    if (timeout_ms < 0) {
        while (!e->set) check(pthread_cond_wait(&e->condition, &e->mutex), "cond_wait");
    } else if (!e->set) {
        uint64_t deadline = wall_ns() + (uint64_t)timeout_ms * 1000000;
        struct timespec stamp = { deadline / 1000000000, deadline % 1000000000 };
        while (!e->set) {
            int result = pthread_cond_timedwait(&e->condition, &e->mutex, &stamp);
            if (result == ETIMEDOUT) break;
            check(result, "cond_timedwait");
        }
    }
    bool signaled = e->set;
    if (!e->manual) e->set = false;
    pthread_mutex_unlock(&e->mutex);
    return signaled;
}

static void event_destroy(event *e) {
    check(pthread_cond_destroy(&e->condition), "cond_destroy");
    check(pthread_mutex_destroy(&e->mutex), "mutex_destroy");
}

static void *consume(void *argument) {
    worker *w = argument;
    atomic_fetch_add(&ready, 1);
    event_wait(&gate, -1);
    for (int step = 1; step <= rounds; ++step) {
        event_wait(&w->wake, -1);
        if (atomic_load(&published_round) != step) { fprintf(stderr, "lost/repeated round\n"); exit(1); }
        ++w->wakes;
        w->sequence_sum += step;
        if (atomic_fetch_add(&round_done, 1) + 1 == step * worker_count) event_set(&round_ack);
    }
    atomic_fetch_add(&completed, 1);
    event_set(&main_wake);
    return NULL;
}

static void *produce(void *unused) {
    (void)unused;
    event_wait(&gate, -1);
    uint64_t deadline = wall_ns();
    for (int step = 1; step <= rounds; ++step) {
        while (atomic_load(&round_done) < (step - 1) * worker_count) {
            if (!event_wait(&round_ack, 5000)) { fprintf(stderr, "consumer stalled\n"); exit(1); }
        }
        deadline += (uint64_t)period_ms * 1000000;
        uint64_t current = wall_ns();
        while (current < deadline) {
            sleep_ms((deadline - current + 999999) / 1000000);
            current = wall_ns();
        }
        if (current - deadline > dispatch_late_ns) dispatch_late_ns = current - deadline;
        atomic_store(&published_round, step);
        for (int i = 0; i < worker_count; ++i) event_set(&workers[i].wake);
    }
    return NULL;
}

static uint64_t timeval_ns(struct timeval value) {
    return (uint64_t)value.tv_sec * 1000000000 + (uint64_t)value.tv_usec * 1000;
}

int main(int argc, char **argv) {
    if (argc != 5 || (strcmp(argv[1], "normal") && strcmp(argv[1], "recursive"))) {
        fprintf(stderr, "usage: native_wakeups normal|recursive WORKERS ROUNDS PERIOD_MS\n");
        return 1;
    }
    recursive_mutex = !strcmp(argv[1], "recursive");
    worker_count = atoi(argv[2]); rounds = atoi(argv[3]); period_ms = atoi(argv[4]);
    if (worker_count < 1 || worker_count > 256 || rounds < 1 || rounds > 10000 || period_ms < 1 || period_ms > 1000)
        return 1;
    workers = calloc((size_t)worker_count, sizeof(*workers));
    if (!workers) { perror("calloc"); return 1; }
    event_init(&gate, true); event_init(&round_ack, false); event_init(&main_wake, false);
    for (int i = 0; i < worker_count; ++i) {
        event_init(&workers[i].wake, false);
        check(pthread_create(&workers[i].thread, NULL, consume, &workers[i]), "pthread_create");
    }
    pthread_t producer;
    check(pthread_create(&producer, NULL, produce, NULL), "pthread_create producer");
    uint64_t started = wall_ns();
    while (atomic_load(&ready) < worker_count) {
        sleep_ms(1);
        if (wall_ns() - started > 10000000000ULL) { fprintf(stderr, "startup timeout\n"); return 1; }
    }
    sleep_ms(20);
    struct rusage before, after;
    if (getrusage(RUSAGE_SELF, &before)) { perror("getrusage"); return 1; }
    started = wall_ns();
    event_set(&gate);
    while (atomic_load(&completed) < worker_count) {
        event_wait(&main_wake, 250);
        if (wall_ns() - started > (uint64_t)rounds * period_ms * 4000000 + 10000000000ULL) {
            fprintf(stderr, "completion timeout\n"); return 1;
        }
    }
    uint64_t elapsed = wall_ns() - started;
    if (getrusage(RUSAGE_SELF, &after)) { perror("getrusage"); return 1; }
    check(pthread_join(producer, NULL), "pthread_join producer");
    uint64_t wakes = 0, expected_sum = (uint64_t)rounds * (rounds + 1) / 2;
    for (int i = 0; i < worker_count; ++i) {
        check(pthread_join(workers[i].thread, NULL), "pthread_join");
        if (workers[i].wakes != (uint64_t)rounds || workers[i].sequence_sum != expected_sum) {
            fprintf(stderr, "incorrect work count\n"); return 1;
        }
        wakes += workers[i].wakes;
        event_destroy(&workers[i].wake);
    }
    event_destroy(&gate); event_destroy(&round_ack); event_destroy(&main_wake); free(workers);
    printf("NATIVE_WAKE mode=%s workers=%d rounds=%d period_ms=%d wall_ns=%" PRIu64
           " user_ns=%" PRIu64 " kernel_ns=%" PRIu64 " wakes=%" PRIu64
           " voluntary_switches=%ld involuntary_switches=%ld dispatch_late_ns=%" PRIu64 " verified=1\n",
           argv[1], worker_count, rounds, period_ms, elapsed,
           timeval_ns(after.ru_utime) - timeval_ns(before.ru_utime),
           timeval_ns(after.ru_stime) - timeval_ns(before.ru_stime), wakes,
           after.ru_nvcsw - before.ru_nvcsw, after.ru_nivcsw - before.ru_nivcsw, dispatch_late_ns);
    return 0;
}
