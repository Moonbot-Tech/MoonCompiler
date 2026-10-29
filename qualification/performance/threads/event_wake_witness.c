#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
typedef volatile LONG atomic_int;
#define load(p) InterlockedCompareExchange((p),0,0)
#define store(p,v) InterlockedExchange((p),(v))
#define add(p,v) InterlockedExchangeAdd((p),(v))
typedef HANDLE thread;
typedef DWORD (WINAPI *thread_fn)(void *);
#define THREAD_RET DWORD WINAPI
#define THREAD_END return 0
#else
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#include <errno.h>
#include <unistd.h>
#include <sched.h>
#include <sys/syscall.h>
#include <linux/futex.h>
#define load(p) atomic_load_explicit((p),memory_order_acquire)
#define store(p,v) atomic_store_explicit((p),(v),memory_order_release)
#define add(p,v) atomic_fetch_add_explicit((p),(v),memory_order_acq_rel)
typedef pthread_t thread;
typedef void *(*thread_fn)(void *);
#define THREAD_RET void *
#define THREAD_END return NULL
#endif

static void check(int ok,const char *text) { if(!ok) { fprintf(stderr,"FAIL %s\n",text); exit(1); } }
static uint64_t ns(void) {
#ifdef _WIN32
    LARGE_INTEGER n,f; QueryPerformanceCounter(&n); QueryPerformanceFrequency(&f);
    return (uint64_t)(n.QuadPart/f.QuadPart)*1000000000+(uint64_t)(n.QuadPart%f.QuadPart)*1000000000/f.QuadPart;
#else
    struct timespec t; check(clock_gettime(CLOCK_MONOTONIC,&t)==0,"clock");
    return (uint64_t)t.tv_sec*1000000000+t.tv_nsec;
#endif
}
static void sleep_ms(int ms) {
#ifdef _WIN32
    Sleep(ms);
#else
    struct timespec t={ms/1000,(ms%1000)*1000000L},r;
    while(nanosleep(&t,&r)) { check(errno==EINTR,"sleep"); t=r; }
#endif
}
typedef struct {
#ifdef _WIN32
    HANDLE handle;
#else
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    atomic_int token;
    int set;
#endif
} event;
static int direct;
static void init(event *e) {
#ifdef _WIN32
    e->handle=CreateEventW(NULL,FALSE,FALSE,NULL); check(e->handle!=NULL,"create event");
#else
    atomic_init(&e->token,0); e->set=0;
    check(pthread_mutex_init(&e->mutex,NULL)==0,"mutex init");
    pthread_condattr_t a; check(pthread_condattr_init(&a)==0,"condattr");
    check(pthread_condattr_setclock(&a,CLOCK_MONOTONIC)==0,"monotonic cond");
    check(pthread_cond_init(&e->cond,&a)==0,"cond init");
    check(pthread_condattr_destroy(&a)==0,"condattr destroy");
#endif
}
static void set(event *e) {
#ifdef _WIN32
    check(SetEvent(e->handle)!=0,"set");
#else
    if(direct) {
        if(!atomic_exchange_explicit(&e->token,1,memory_order_release))
            check(syscall(SYS_futex,&e->token,FUTEX_WAKE_PRIVATE,1,NULL,NULL,0)>=0,"futex wake");
    } else {
        check(pthread_mutex_lock(&e->mutex)==0,"set lock"); e->set=1;
        check(pthread_mutex_unlock(&e->mutex)==0,"set unlock");
        check(pthread_cond_signal(&e->cond)==0,"signal");
    }
#endif
}
static int wait_event(event *e,int milliseconds) {
#ifdef _WIN32
    DWORD r=WaitForSingleObject(e->handle,milliseconds<0?INFINITE:(DWORD)milliseconds);
    check(r==WAIT_OBJECT_0||r==WAIT_TIMEOUT,"wait"); return r==WAIT_OBJECT_0;
#else
    struct timespec deadline,*p=NULL;
    if(milliseconds>=0) { uint64_t t=ns()+(uint64_t)milliseconds*1000000;
        deadline.tv_sec=t/1000000000; deadline.tv_nsec=t%1000000000; p=&deadline; }
    if(direct) {
        for(;;) {
            if(atomic_exchange_explicit(&e->token,0,memory_order_acquire)) return 1;
            int r=(int)syscall(SYS_futex,&e->token,FUTEX_WAIT_BITSET_PRIVATE,0,p,NULL,FUTEX_BITSET_MATCH_ANY);
            if(r<0 && errno==ETIMEDOUT) return atomic_exchange_explicit(&e->token,0,memory_order_acquire)!=0;
            check(r==0||errno==EAGAIN||errno==EINTR,"futex wait");
        }
    }
    check(pthread_mutex_lock(&e->mutex)==0,"wait lock");
    while(!e->set) {
        int r=p?pthread_cond_timedwait(&e->cond,&e->mutex,p):pthread_cond_wait(&e->cond,&e->mutex);
        if(r==ETIMEDOUT) break;
        check(r==0,"cond wait");
    }
    int ok=e->set; e->set=0; check(pthread_mutex_unlock(&e->mutex)==0,"wait unlock"); return ok;
#endif
}
static void destroy(event *e) {
#ifdef _WIN32
    check(CloseHandle(e->handle)!=0,"close");
#else
    check(pthread_cond_destroy(&e->cond)==0,"cond destroy");
    check(pthread_mutex_destroy(&e->mutex)==0,"mutex destroy");
#endif
}
enum { MAX_BACKGROUND=100, WARMUP=16 };
static event input,ack,timers[MAX_BACKGROUND];
static atomic_int ready,go,stop,issued;
static int samples,period_ms,timer_ms,work,background_count;
static uint64_t target_timeouts,target_digest;
static uint64_t sent,*latencies,timeouts[MAX_BACKGROUND],digests[MAX_BACKGROUND];
static THREAD_RET receiver(void *unused) {
    (void)unused; add(&ready,1);
    uint64_t sum=1;
    for(int i=0;i<samples+WARMUP;) {
        if(!wait_event(&input,background_count?timer_ms:-1)) {
            target_timeouts++;
            for(int j=0;j<work;j++) sum=(sum*6364136223846793005ULL+1)^(sum>>17);
            continue;
        }
        uint64_t end=ns();
        check(load(&issued)==i+1,"signal sequence");
        if(i>=WARMUP) latencies[i-WARMUP]=end-sent;
        i++;
        set(&ack);
    }
    target_digest=sum;
    THREAD_END;
}
static THREAD_RET background(void *arg) {
    intptr_t id=(intptr_t)arg; uint64_t sum=1,n=0; add(&ready,1);
    while(!load(&go)) sleep_ms(1);
    while(!load(&stop)) {
        if(!wait_event(&timers[id],timer_ms)) {
            n++;
            for(int i=0;i<work;i++) sum=(sum*6364136223846793005ULL+1)^(sum>>17);
        }
    }
    timeouts[id]=n; digests[id]=sum; THREAD_END;
}
static thread start(thread_fn fn,void *arg) {
    thread t;
#ifdef _WIN32
    t=CreateThread(NULL,0,fn,arg,0,NULL); check(t!=NULL,"thread create");
#else
    check(pthread_create(&t,NULL,fn,arg)==0,"thread create");
#endif
    return t;
}
static void join(thread t) {
#ifdef _WIN32
    check(WaitForSingleObject(t,10000)==WAIT_OBJECT_0,"join"); CloseHandle(t);
#else
    check(pthread_join(t,NULL)==0,"join");
#endif
}
static int compare(const void *a,const void *b) {
    uint64_t x=*(const uint64_t*)a,y=*(const uint64_t*)b; return (x>y)-(x<y);
}
int main(int argc,char **argv) {
    check(argc==8,"usage: cond|futex CPU BACKGROUND SAMPLES SENDER_MS TIMER_MS WORK");
    direct=strcmp(argv[1],"futex")==0;
    check(direct||strcmp(argv[1],"cond")==0,"mode");
    int cpu=atoi(argv[2]),count=atoi(argv[3]); samples=atoi(argv[4]);
    background_count=count;
    period_ms=atoi(argv[5]); timer_ms=atoi(argv[6]); work=atoi(argv[7]);
    check(cpu>=0&&cpu<64&&count>=0&&count<=MAX_BACKGROUND&&samples>=32&&samples<=100000&&period_ms>0&&timer_ms>0&&work>=0&&work<=100000,"arguments");
#ifdef _WIN32
    check(!direct,"Windows uses its native event");
    check(SetProcessAffinityMask(GetCurrentProcess(),(DWORD_PTR)1<<cpu)!=0,"affinity");
#else
    cpu_set_t cpus; CPU_ZERO(&cpus); CPU_SET(cpu,&cpus); check(sched_setaffinity(0,sizeof(cpus),&cpus)==0,"affinity");
#endif
    latencies=calloc((size_t)samples,sizeof(*latencies)); check(latencies!=NULL,"allocate");
    init(&input); init(&ack); thread workers[MAX_BACKGROUND];
    for(int i=0;i<count;i++) { init(&timers[i]); workers[i]=start(background,(void*)(intptr_t)i); }
    thread target=start(receiver,NULL);
    uint64_t began=ns();
    while(load(&ready)!=count+1) { check(ns()-began<10000000000ULL,"ready timeout"); sleep_ms(1); }
    store(&go,1); began=ns();
    for(int i=0;i<samples+WARMUP;i++) {
        sleep_ms(period_ms); sent=ns(); store(&issued,i+1); set(&input);
        check(wait_event(&ack,5000),"missing acknowledgement");
    }
    uint64_t elapsed=ns()-began; store(&stop,1);
    for(int i=0;i<count;i++) set(&timers[i]);
    join(target); uint64_t total=0,digest=0;
    for(int i=0;i<count;i++) { join(workers[i]); total+=timeouts[i]; digest^=digests[i]; destroy(&timers[i]); }
    destroy(&input); destroy(&ack); qsort(latencies,(size_t)samples,sizeof(*latencies),compare);
    printf("WITNESS backend=%s background=%d samples=%d sender_ms=%d timer_ms=%d work=%d wall_ns=%llu timeouts=%llu target_timeouts=%llu digest=%llu p50_ns=%llu p95_ns=%llu p99_ns=%llu max_ns=%llu verified=1\n",
#ifdef _WIN32
           "win32",
#else
           direct?"futex":"pthread",
#endif
           count,samples,period_ms,timer_ms,work,(unsigned long long)elapsed,(unsigned long long)total,(unsigned long long)target_timeouts,(unsigned long long)(digest^target_digest),
           (unsigned long long)latencies[(samples-1)*50/100],(unsigned long long)latencies[(samples-1)*95/100],
           (unsigned long long)latencies[(samples-1)*99/100],(unsigned long long)latencies[samples-1]);
    free(latencies); return 0;
}
