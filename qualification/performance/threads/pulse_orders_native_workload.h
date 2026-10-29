#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#ifdef ORDER_CPP_EVENT
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
typedef std::atomic<int> atomic_int;
#define atomic_load(p) ((p)->load())
#define atomic_init(p,v) ((p)->store(v))
#define atomic_store(p,v) ((p)->store(v))
#define atomic_fetch_add(p,v) ((p)->fetch_add(v))
#else
#include <stdatomic.h>
#endif

/* Same sparse protocol as pulse_order_workers.dpr. Events outlive all users:
   this harness does not implement the RTL concurrent-destruction contract.
   C and C++ share pthread OS-thread startup, calendar and queue code, isolating
   pthread condition variables versus std::condition_variable. */
static void require(bool value, const char *reason) {
    if (!value) { fprintf(stderr, "%s\n", reason); exit(1); }
}
static void checked(int error, const char *reason) { require(error == 0, reason); }
static uint64_t wall_ns(void) {
    struct timespec t;
    require(clock_gettime(CLOCK_MONOTONIC, &t) == 0, "monotonic clock");
    return (uint64_t)t.tv_sec * 1000000000 + (uint64_t)t.tv_nsec;
}
static void sleep_ms(int milliseconds) {
    struct timespec t = { milliseconds / 1000, (milliseconds % 1000) * 1000000L };
    while (nanosleep(&t, &t)) require(errno == EINTR, "nanosleep");
}
typedef struct {
#ifdef ORDER_CPP_EVENT
    std::mutex mutex;
    std::condition_variable condition;
#else
    pthread_mutex_t mutex;
    pthread_cond_t condition;
#endif
    bool set, manual;
} event;
static void event_init(event *e, bool manual) {
#ifndef ORDER_CPP_EVENT
    checked(pthread_mutex_init(&e->mutex, NULL), "mutex init");
    pthread_condattr_t attr;
    checked(pthread_condattr_init(&attr), "condition attr");
    checked(pthread_condattr_setclock(&attr, CLOCK_MONOTONIC), "condition clock");
    checked(pthread_cond_init(&e->condition, &attr), "condition init");
    checked(pthread_condattr_destroy(&attr), "condition attr destroy");
#endif
    e->set = false;
    e->manual = manual;
}
static void event_set(event *e) {
#ifdef ORDER_CPP_EVENT
    { std::lock_guard<std::mutex> lock(e->mutex); e->set = true; }
    if (e->manual) e->condition.notify_all(); else e->condition.notify_one();
#else
    checked(pthread_mutex_lock(&e->mutex), "event lock");
    e->set = true;
    checked(pthread_mutex_unlock(&e->mutex), "event unlock");
    checked(e->manual ? pthread_cond_broadcast(&e->condition) : pthread_cond_signal(&e->condition), "event notify");
#endif
}
static bool event_wait(event *e, int ms) {
#ifdef ORDER_CPP_EVENT
    std::unique_lock<std::mutex> lock(e->mutex);
    bool ok = true;
    if (ms < 0) e->condition.wait(lock, [&]{ return e->set; });
    else ok = e->condition.wait_for(lock, std::chrono::milliseconds(ms), [&]{ return e->set; });
    if (ok && !e->manual) e->set = false;
    return ok;
#else
    checked(pthread_mutex_lock(&e->mutex), "wait lock");
    struct timespec deadline = {0, 0};
    if (ms >= 0 && !e->set) {
        uint64_t ns = wall_ns() + (uint64_t)ms * 1000000;
        deadline.tv_sec = ns / 1000000000;
        deadline.tv_nsec = ns % 1000000000;
    }
    while (!e->set) {
        int result = ms < 0 ? pthread_cond_wait(&e->condition, &e->mutex) :
            pthread_cond_timedwait(&e->condition, &e->mutex, &deadline);
        if (result == ETIMEDOUT) break;
        checked(result, "condition wait");
    }
    bool ok = e->set;
    if (ok && !e->manual) e->set = false;
    checked(pthread_mutex_unlock(&e->mutex), "wait unlock");
    return ok;
#endif
}
static void event_destroy(event *e) {
#ifndef ORDER_CPP_EVENT
    checked(pthread_cond_destroy(&e->condition), "condition destroy");
    checked(pthread_mutex_destroy(&e->mutex), "mutex destroy");
#else
    (void)e;
#endif
}
typedef struct log_line {
    struct log_line *next;
    char text[64];
} log_line;
typedef struct {
    pthread_t thread;
    event wake;
    atomic_int issued;
    int id, received;
    uint64_t sent_ns, timeouts, min_timeout_ns, generated, delivered, bytes, delivered_bytes;
    uint64_t digest, checksum, log_checksum, delivered_checksum;
    uint64_t *latencies;
    pthread_mutex_t log_lock;
    log_line *head, *tail;
} worker;
typedef struct callback { struct callback *next; worker *target; } callback;
static worker *workers;
static event gate, ack, main_wake;
static atomic_int ready, completed;
static pthread_mutex_t queue_lock = PTHREAD_MUTEX_INITIALIZER;
static callback *queue_head, *queue_tail;
static int count, rounds, period_ms, signals;
static bool do_work, selected_only;
static uint64_t text_checksum(const char *text) {
    uint64_t sum = 0;
    for (const unsigned char *p = (const unsigned char *)text; *p; ++p) sum = sum * 131 + *p;
    return sum;
}
static void queue_log(worker *w, int step) {
    log_line *line = (log_line *)malloc(sizeof(*line));
    callback *call = (callback *)malloc(sizeof(*call));
    require(line && call, "log allocation");
    int length = snprintf(line->text, sizeof(line->text), "order=%d step=%d", w->id, step);
    require(length > 0 && (size_t)length < sizeof(line->text), "log format");
    line->next = NULL;
    ++w->generated;
    w->bytes += length;
    w->log_checksum += text_checksum(line->text);
    checked(pthread_mutex_lock(&w->log_lock), "log lock");
    if (w->tail) w->tail->next = line; else w->head = line;
    w->tail = line;
    checked(pthread_mutex_unlock(&w->log_lock), "log unlock");
    call->next = NULL;
    call->target = w;
    checked(pthread_mutex_lock(&queue_lock), "queue lock");
    if (queue_tail) queue_tail->next = call; else queue_head = call;
    queue_tail = call;
    checked(pthread_mutex_unlock(&queue_lock), "queue unlock");
    event_set(&main_wake);
}
static void drain_queue(void) {
    checked(pthread_mutex_lock(&queue_lock), "drain lock");
    callback *calls = queue_head;
    queue_head = queue_tail = NULL;
    checked(pthread_mutex_unlock(&queue_lock), "drain unlock");
    while (calls) {
        worker *w = calls->target;
        checked(pthread_mutex_lock(&w->log_lock), "deliver lock");
        while (w->head) {
            log_line *line = w->head;
            w->head = line->next;
            ++w->delivered;
            w->delivered_bytes += strlen(line->text);
            w->delivered_checksum += text_checksum(line->text);
            free(line);
        }
        w->tail = NULL;
        checked(pthread_mutex_unlock(&w->log_lock), "deliver unlock");
        callback *next = calls->next;
        free(calls);
        calls = next;
    }
}
static uint64_t calendar_ms(void) {
    struct timespec t;
    struct tm local;
    require(clock_gettime(CLOCK_REALTIME, &t) == 0, "calendar clock");
    require(localtime_r(&t.tv_sec, &local) != NULL, "local calendar");
    // Force an observable local-calendar conversion, analogous to Now's work.
    return (uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000 + (uint64_t)local.tm_yday;
}
static void *consume(void *argument) {
    worker *w = (worker *)argument;
    atomic_fetch_add(&ready, 1);
    require(event_wait(&gate, -1), "gate");
    int n = selected_only ? signals : rounds;
    for (int step = 1; step <= n; ++step) {
        uint64_t began = wall_ns();
        bool ok = event_wait(&w->wake, selected_only || w->timeouts == (uint64_t)(rounds - signals) ? -1 : period_ms);
        uint64_t ended = wall_ns();
        if (ok) {
            require(atomic_load(&w->issued) == w->received + 1 && w->received < signals, "wrong recipient/duplicate");
            w->latencies[w->received++] = ended - w->sent_ns;
            event_set(&ack);
        } else {
            require(!selected_only && ended - began + 1000000 >= (uint64_t)period_ms * 1000000, "early timeout");
            ++w->timeouts;
            if (ended - began < w->min_timeout_ns) w->min_timeout_ns = ended - began;
        }
        w->checksum += (uint64_t)(w->id + 1) * 1000003 + step;
        if (do_work) {
            w->digest ^= wall_ns() / 1000000;
            w->digest ^= wall_ns() / 1000000;
            w->digest ^= calendar_ms();
            if (step % 8 == 0) queue_log(w, step);
        }
    }
    require(w->received == signals, "recipient lifetime");
    atomic_fetch_add(&completed, 1);
    event_set(&main_wake);
    return NULL;
}
static void *produce(void *unused) {
    (void)unused;
    require(event_wait(&gate, -1), "producer gate");
    for (int round = 1; round <= signals; ++round) for (int i = 0; i < count; ++i) {
        sleep_ms(period_ms);
        workers[i].sent_ns = wall_ns();
        atomic_store(&workers[i].issued, round);
        event_set(&workers[i].wake);
        require(event_wait(&ack, 5000), "recipient acknowledgement");
    }
    return NULL;
}
static uint64_t timeval_ns(struct timeval t) { return (uint64_t)t.tv_sec * 1000000000 + t.tv_usec * 1000; }
static int compare_u64(const void *a, const void *b) {
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return (x > y) - (x < y);
}
int main(int argc, char **argv) {
    require(argc == 6, "usage: orders|wait|selected WORKERS ROUNDS PERIOD_MS SIGNALS_PER_WORKER");
    do_work = strcmp(argv[1], "orders") == 0;
    selected_only = strcmp(argv[1], "selected") == 0;
    require(do_work || selected_only || strcmp(argv[1], "wait") == 0, "mode");
    count = atoi(argv[2]); rounds = atoi(argv[3]); period_ms = atoi(argv[4]); signals = atoi(argv[5]);
    require(count > 0 && count <= 256 && rounds > 0 && rounds <= 10000 && period_ms >= 2 && period_ms <= 1000 &&
            signals > 0 && signals <= 100, "size");
    require(selected_only || rounds > count * signals + 32, "insufficient timeout rounds");
#ifdef ORDER_CPP_EVENT
    workers = new worker[count]();
#else
    workers = (worker *)calloc((size_t)count, sizeof(*workers));
#endif
    require(workers != NULL, "worker allocation");
    event_init(&gate, true); event_init(&ack, false); event_init(&main_wake, false);
    for (int i = 0; i < count; ++i) {
        worker *w = &workers[i];
        w->id = i;
        atomic_init(&w->issued, 0);
        w->min_timeout_ns = UINT64_MAX;
        w->latencies = (uint64_t *)calloc((size_t)signals, sizeof(uint64_t));
        require(w->latencies != NULL, "latency allocation");
        event_init(&w->wake, false);
        checked(pthread_mutex_init(&w->log_lock, NULL), "log mutex");
        checked(pthread_create(&w->thread, NULL, consume, w), "worker create");
    }
    pthread_t producer;
    checked(pthread_create(&producer, NULL, produce, NULL), "producer create");
    uint64_t start = wall_ns();
    while (atomic_load(&ready) < count) { sleep_ms(1); require(wall_ns() - start < 10000000000ULL, "startup timeout"); }
    sleep_ms(20);
    struct rusage before, after;
    require(getrusage(RUSAGE_SELF, &before) == 0, "usage before");
    start = wall_ns();
    event_set(&gate);
    while (atomic_load(&completed) < count) {
        drain_queue();
        if (atomic_load(&completed) < count) event_wait(&main_wake, 100);
        require(wall_ns() - start < (uint64_t)rounds * period_ms * 4000000 + 10000000000ULL, "workload timeout");
    }
    drain_queue();
    uint64_t elapsed = wall_ns() - start;
    require(getrusage(RUSAGE_SELF, &after) == 0, "usage after");
    checked(pthread_join(producer, NULL), "producer join");
    uint64_t timeouts = 0, minimum = UINT64_MAX, logs = 0, bytes = 0, digest = 0, checksum = 0, log_sum = 0;
    size_t k = 0, total = (size_t)count * signals;
    uint64_t *latencies = (uint64_t *)malloc(total * sizeof(uint64_t));
    require(latencies != NULL, "all latencies");
    for (int i = 0; i < count; ++i) {
        worker *w = &workers[i];
        checked(pthread_join(w->thread, NULL), "worker join");
        int n = selected_only ? signals : rounds;
        require(w->received == signals && w->checksum == (uint64_t)n * (i + 1) * 1000003 + (uint64_t)n * (n + 1) / 2, "work checksum");
        require(w->generated == (do_work ? (uint64_t)rounds / 8 : 0) && w->generated == w->delivered &&
                w->bytes == w->delivered_bytes && w->log_checksum == w->delivered_checksum && !w->head, "log oracle");
        timeouts += w->timeouts;
        if (w->min_timeout_ns < minimum) minimum = w->min_timeout_ns;
        logs += w->delivered; bytes += w->delivered_bytes; digest ^= w->digest; checksum += w->checksum; log_sum += w->log_checksum;
        for (int j = 0; j < signals; ++j) latencies[k++] = w->latencies[j];
        free(w->latencies);
        event_destroy(&w->wake);
        checked(pthread_mutex_destroy(&w->log_lock), "log mutex destroy");
    }
    require(timeouts == (selected_only ? 0 : (uint64_t)count * (rounds - signals)) && !queue_head, "timeout/queue oracle");
    qsort(latencies, total, sizeof(uint64_t), compare_u64);
    event_destroy(&gate); event_destroy(&ack); event_destroy(&main_wake);
    checked(pthread_mutex_destroy(&queue_lock), "queue mutex destroy");
#ifdef ORDER_CPP_EVENT
    delete[] workers;
#else
    free(workers);
#endif
    printf("PULSE_ORDER mode=%s workers=%d rounds=%d period_ms=%d wall_ns=%" PRIu64
           " user_ns=%" PRIu64 " kernel_ns=%" PRIu64 " cycles=0 signals=%zu timeouts=%" PRIu64
           " min_timeout_ns=%" PRIu64 " timeout_slack_ns=1000000 logs=%" PRIu64 " digest=%" PRIu64
           " checksum=%" PRIu64 " log_bytes=%" PRIu64 " log_checksum=%" PRIu64
           " latency_p50_ns=%" PRIu64 " latency_p95_ns=%" PRIu64 " latency_p99_ns=%" PRIu64 " latency_max_ns=%" PRIu64 " verified=1\n",
           argv[1], count, rounds, period_ms, elapsed,
           timeval_ns(after.ru_utime) - timeval_ns(before.ru_utime), timeval_ns(after.ru_stime) - timeval_ns(before.ru_stime),
           total, timeouts, timeouts ? minimum : 0, logs, digest, checksum, bytes, log_sum,
           latencies[(total-1)*50/100], latencies[(total-1)*95/100], latencies[(total-1)*99/100], latencies[total-1]);
    free(latencies);
    return 0;
}
