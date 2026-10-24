#define _GNU_SOURCE
#include <dlfcn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <ucontext.h>
#include <unistd.h>

/* The installed x86-64 libunwind local ABI; identical storage widths are used
   by Moon.Diagnostics, but the traversal/oracle here is independent. */
typedef int (*init_fn)(void *, void *, int);
typedef int (*step_fn)(void *);
typedef int (*reg_fn)(void *, int, unsigned long *);
static init_fn init_cursor;
static step_fn step_cursor;
static reg_fn get_reg;
static unsigned char *armed;
static unsigned char saved_byte;
static uintptr_t anchor_start, anchor_end;
static volatile sig_atomic_t fired, found, error, depth, truncated;
static uintptr_t frames[128];

static void trap(int sig, siginfo_t *info, void *context) {
  (void)sig; (void)info;
  ucontext_t *ctx = context;
  unsigned long cursor[127] = {0};
  if (!armed || (uintptr_t)ctx->uc_mcontext.gregs[REG_RIP] != (uintptr_t)armed + 1)
    _exit(91);
  *armed = saved_byte;
  ctx->uc_mcontext.gregs[REG_RIP] = (greg_t)(uintptr_t)armed;
  fired++;
  int status = init_cursor(cursor, context, 1);
  if (status < 0) { error = status; return; }
  do {
    unsigned long ip;
    status = get_reg(cursor, 16, &ip);
    if (status < 0 || !ip) break;
    frames[depth++] = ip;
    if (ip >= anchor_start && ip < anchor_end) found = 1;
    if (truncated || depth == 128) break;
    status = step_cursor(cursor);
  } while (status > 0);
  if (status < 0) error = status;
}

int audit_setup(uintptr_t lo, uintptr_t hi, int negative) {
  void *lib = dlopen("libunwind.so.8", RTLD_NOW | RTLD_LOCAL);
  if (!lib) return 1;
  init_cursor = (init_fn)dlsym(lib, "_ULx86_64_init_local2");
  step_cursor = (step_fn)dlsym(lib, "_ULx86_64_step");
  get_reg = (reg_fn)dlsym(lib, "_ULx86_64_get_reg");
  if (!init_cursor || !step_cursor || !get_reg) return 2;
  struct sigaction sa = {0};
  sa.sa_sigaction = trap;
  sa.sa_flags = SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  if (sigaction(SIGTRAP, &sa, NULL)) return 3;
  anchor_start = lo; anchor_end = hi; truncated = negative;
  return 0;
}

int audit_arm(uintptr_t address) {
  long page = sysconf(_SC_PAGESIZE);
  uintptr_t base = address & ~(uintptr_t)(page - 1);
  if (mprotect((void *)base, (size_t)page, PROT_READ | PROT_WRITE | PROT_EXEC)) return 1;
  armed = (unsigned char *)address;
  saved_byte = *armed;
  if (saved_byte == 0xcc) return 2;
  *armed = 0xcc;
  return 0;
}

int audit_finish(void) {
  if (!fired) { *armed = saved_byte; puts("UNREACHED"); return 77; }
  printf("TRAP=%d ANCHOR=%d DEPTH=%d ERROR=%d", fired, found, depth, error);
  for (int i = 0; i < depth; i++) printf(" %lx", (unsigned long)frames[i]);
  puts("");
  return fired != 1 || !found ? 1 : 0;
}

/* Keep one Pascal scalar in its own stack slot across an opaque call. */
void audit_observe(void *value) {
  __asm__ volatile("" : : "r"(value) : "memory");
}
