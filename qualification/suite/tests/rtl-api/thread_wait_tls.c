#define _GNU_SOURCE
#include <pthread.h>
#include <stdatomic.h>
#include <unistd.h>
#include <stdlib.h>
#include <stddef.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/seccomp.h>
#include <linux/filter.h>
#include <errno.h>
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
int wait_deny_clock(void) {
    struct sock_filter code[] = {
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,SYS_clock_gettime,0,1),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW)
    };
    struct sock_fprog filter = {sizeof(code)/sizeof(code[0]),code};
    if (prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)) return -1;
    return prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&filter);
}
__attribute__((destructor)) static void cleanup(void) { if (key_created) pthread_key_delete(key); }
