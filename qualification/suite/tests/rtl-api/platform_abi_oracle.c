/* Independent OS-header oracle for the structure assertions in the Pascal tests.
   Linux: cc platform_abi_oracle.c -o abi && ./abi
   Win64: x86_64-w64-mingw32-gcc platform_abi_oracle.c -o abi.exe */
#define _GNU_SOURCE
#include <stdio.h>
#include <stddef.h>
#define S(t) printf(#t "=%zu\n", sizeof(t))
#define O(t,f) printf(#t "." #f "=%zu\n", offsetof(t,f))
#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <wincred.h>
#include <accctrl.h>
#include <iphlpapi.h>
#include <ipexport.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <qos.h>
#include <cpl.h>
int main(void) {
    S(PROCESS_MEMORY_COUNTERS); S(THREADENTRY32); S(CREDENTIALW);
    S(SERVICE_STATUS); S(SERVICE_STATUS_PROCESS); S(TRUSTEE_W); S(EXPLICIT_ACCESS_W);
    S(IP_ADAPTER_INFO); S(IP_ADDR_STRING); S(MIB_IPADDRTABLE); S(MIB_IFROW);
    S(WTS_SESSION_INFOW); S(PROFILEINFOW); S(QOS); S(CPLINFO);
    S(IP_OPTION_INFORMATION); S(ICMP_ECHO_REPLY);
    O(CREDENTIALW, CredentialBlob); O(IP_ADAPTER_INFO, LeaseObtained);
    return 0;
}
#else
#include <time.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <signal.h>
#include <pthread.h>
#include <netdb.h>
int main(void) {
    S(time_t); S(off_t); S(socklen_t); S(struct timeval); S(struct timespec); S(struct tm);
    S(struct stat); S(sigset_t); S(struct sigaction); S(pthread_mutex_t);
    S(pthread_cond_t); S(pthread_attr_t); S(struct addrinfo);
    O(struct tm, tm_gmtoff); O(struct stat, st_size); O(struct sigaction, sa_flags);
    return 0;
}
#endif
