program rtl_api_posix_contracts;
{$mode delphiunicode}
uses SysUtils, ctypes, Posix.SysTypes, Posix.Time, Posix.SysTime, Posix.Errno,
  Posix.Unistd, Posix.Fcntl, Posix.SysStat, Posix.SysMman, Posix.Dlfcn,
  Posix.SysSocket, Posix.NetinetIn, Posix.ArpaInet, Posix.Netdb, Posix.Poll,
  Posix.Pthread, Posix.Signal;
procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;
function Worker(Context: Pointer): Pointer; cdecl;
begin
  Inc(PInteger(Context)^);
  Result := Context;
end;
var
  TV: timeval;
  TS: timespec;
  Calendar: tm;
  Epoch: time_t;
  Info: _stat;
  FD: Integer;
  FDs: array[0..1] of cint;
  Path: UTF8String;
  Text, ReadBack: array[0..3] of Byte;
  Page, Lib, Returned: Pointer;
  Address: in6_addr;
  IP: array[0..63] of AnsiChar;
  Hints: addrinfo;
  AI: Paddrinfo;
  PollFD: Posix.Poll.pollfd;
  Attr: pthread_mutexattr_t;
  Mutex: pthread_mutex_t;
  Thread: pthread_t;
  Value: Integer;
  SignalSet: sigset_t;
  Action: sigaction_t;
begin
  Check((SizeOf(time_t) = 8) and (SizeOf(off_t) = 8) and (SizeOf(socklen_t) = 4), 'POSIX scalar ABI');
  Check((SizeOf(timeval) = 16) and (SizeOf(timespec) = 16) and (SizeOf(tm) = 56), 'time ABI');
  Check((SizeOf(_stat) = 144) and (SizeOf(sigset_t) = 128) and (SizeOf(sigaction_t) = 152), 'libc structure ABI');
  Check((SizeOf(pthread_mutex_t) = 40) and (SizeOf(pthread_cond_t) = 48) and
    (SizeOf(pthread_attr_t) = 56) and (SizeOf(addrinfo) = 48), 'pthread and DNS ABI');
  Check((NativeUInt(@Calendar.tm_gmtoff) - NativeUInt(@Calendar) = 40) and
    (NativeUInt(@Info.st_size) - NativeUInt(@Info) = 48) and
    (NativeUInt(@Action.sa_flags) - NativeUInt(@Action) = 136), 'libc field offsets');
  Check(gettimeofday(@TV, nil) = 0, 'wall time');
  Check(clock_gettime(CLOCK_REALTIME, @TS) = 0, 'clock time');
  Check(Abs(TV.tv_sec - TS.tv_sec) <= 1, 'same wall clock');
  Epoch := time(nil);
  Check(gmtime_r(@Epoch, @Calendar) = @Calendar, 'UTC conversion');
  Check(timegm(@Calendar) = Epoch, 'UTC round trip');
  Check(clock_gettime(CLOCK_MONOTONIC, @TS) = 0, 'monotonic time');
  Path := UTF8Encode(IncludeTrailingPathDelimiter(GetTempDir) + 'moon-posix-' + IntToStr(getpid));
  FD := open(PAnsiChar(Path), O_RDWR or O_CREAT or O_EXCL, mode_t($180));
  Check(FD >= 0, 'create file');
  try
    Text[0] := 0; Text[1] := 127; Text[2] := 128; Text[3] := 255;
    Check(write(FD, @Text, SizeOf(Text)) = SizeOf(Text), 'write file');
    Check(fstat(FD, @Info) = 0, 'fstat');
    Check((Info.st_size = 4) and ((Info.st_mode and S_IFMT) = S_IFREG), 'stat layout values');
    Check(lseek(FD, 0, SEEK_SET) = 0, 'seek file');
    Check(read(FD, @ReadBack, SizeOf(ReadBack)) = 4, 'read file');
    Check(CompareMem(@Text, @ReadBack, 4), 'file round trip');
    Check(fcntl(FD, F_GETFD) >= 0, 'fcntl without optional argument');
    Check(fcntl(FD, F_SETFD, FD_CLOEXEC) = 0, 'fcntl with optional argument');
  finally
    close(FD);
    unlink(PAnsiChar(Path));
  end;
  Check(open(PAnsiChar(Path), O_RDONLY) = -1, 'missing file fails');
  Check(errno = ENOENT, 'libc thread-local errno');
  Page := mmap(nil, 4096, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  Check(Page <> MAP_FAILED, 'anonymous mapping');
  PByte(Page)^ := 37;
  Check(PByte(Page)^ = 37, 'mapped memory');
  Check(munmap(Page, 4096) = 0, 'unmap');
  Check(socketpair(AF_UNIX, SOCK_STREAM, 0, @FDs) = 0, 'local socket pair');
  try
    Check(send(FDs[0], @Text, 4, MSG_NOSIGNAL) = 4, 'send socket');
    PollFD.fd := FDs[1]; PollFD.events := POLLIN; PollFD.revents := 0;
    Check((poll(@PollFD, 1, 1000) = 1) and ((PollFD.revents and POLLIN) <> 0), 'socket readiness');
    Check(recv(FDs[1], @ReadBack, 4, 0) = 4, 'receive socket');
    Check(CompareMem(@Text, @ReadBack, 4), 'socket round trip');
  finally
    close(FDs[0]); close(FDs[1]);
  end;
  Check(inet_pton(AF_INET6, '::1', @Address) = 1, 'parse IPv6');
  Check(inet_ntop(AF_INET6, @Address, @IP, SizeOf(IP)) <> nil, 'format IPv6');
  Check(AnsiString(PAnsiChar(@IP)) = '::1', 'IPv6 round trip');
  Hints := Default(addrinfo);
  Hints.ai_family := AF_INET;
  Hints.ai_socktype := SOCK_STREAM;
  Hints.ai_flags := AI_NUMERICHOST or AI_NUMERICSERV;
  AI := nil;
  Check(getaddrinfo('127.0.0.1', '80', @Hints, @AI) = 0, 'numeric address resolver');
  try
    Check((AI <> nil) and (AI^.ai_family = AF_INET) and (AI^.ai_addrlen = 16), 'resolver ABI');
  finally
    freeaddrinfo(AI);
  end;
  Lib := dlopen('libc.so.6', RTLD_NOW or RTLD_LOCAL);
  Check(Lib <> nil, 'load system library');
  Check(dlsym(Lib, 'getpid') <> nil, 'resolve OS symbol');
  Check(dlclose(Lib) = 0, 'close library');
  Check(pthread_mutexattr_init(@Attr) = 0, 'mutex attributes');
  Check(pthread_mutexattr_settype(@Attr, PTHREAD_MUTEX_RECURSIVE) = 0, 'recursive attribute');
  Check(pthread_mutex_init(@Mutex, @Attr) = 0, 'mutex init');
  Check(pthread_mutexattr_destroy(@Attr) = 0, 'attribute destroy');
  Check(pthread_mutex_lock(@Mutex) = 0, 'mutex lock');
  Check(pthread_mutex_trylock(@Mutex) = 0, 'recursive lock');
  Check(pthread_mutex_unlock(@Mutex) = 0, 'recursive unlock');
  Check(pthread_mutex_unlock(@Mutex) = 0, 'mutex unlock');
  Check(pthread_mutex_destroy(@Mutex) = 0, 'mutex destroy');
  Value := 41;
  Check(pthread_create(@Thread, nil, Worker, @Value) = 0, 'native thread');
  Check(pthread_join(Thread, @Returned) = 0, 'join native thread');
  Check((Returned = @Value) and (Value = 42), 'native thread calling convention');
  Check(sigemptyset(@SignalSet) = 0, 'empty signal set');
  Check(sigaddset(@SignalSet, SIGUSR1) = 0, 'add signal');
  Check(sigismember(@SignalSet, SIGUSR1) = 1, 'signal member');
  Check(sigismember(@SignalSet, SIGTERM) = 0, 'signal non-member');
  Check(sigaction(SIGUSR1, nil, @Action) = 0, 'read signal action');
  Writeln('RTL_API_POSIX_CONTRACTS_OK');
end.
