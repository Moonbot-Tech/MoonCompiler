/// Fast Memory Manager for FPC x86_64
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.core.fpcx64mm;

{
  *****************************************************************************

    A Multi-thread Friendly Memory Manager for FPC written in x86_64 assembly
    - targetting Linux (and Windows) multi-threaded Services
    - only for FPC on the x86_64 target - use the RTL MM on Delphi or ARM
    - based on proven FastMM4 by Pierre le Riche - with tuning and enhancements
    - can report detailed statistics (with threads contention and memory leaks)
    - three app modes: default GUI app, FPCMM_SERVER or FPCMM_BOOSTER

    Usage: include this unit as the very first in your FPC project uses clause

    Why another Memory Manager on FPC?
    - The built-in heap.inc is well written and cross-platform and cross-CPU,
      but its threadvar arena for small blocks tends to consume a lot of memory
      on multi-threaded servers, and has suboptimal allocation performance
    - C memory managers (glibc, Intel TBB, jemalloc) have a very high RAM
      consumption (especially Intel TBB) and do panic/SIG_KILL on any GPF - but
      they were reported to scale better on heavy load with cpu core count > 16
      even if GetMem() is almost twice faster on single thread with fpcx64mm
    - Pascal alternatives (FastMM4,ScaleMM2,BrainMM) are Windows+Delphi specific
    - Our lockess round-robin of tiny blocks and FreeMem bin list are unique
      algorithms among Memory Managers, and match modern CPUs and workloads
    - It was so fun diving into SSE2 x86_64 assembly and Pierre's insight
    - Resulting code is still easy to understand and maintain

    DISCLAMER: seems stable on Linux and Win64 but feedback is welcome!

  *****************************************************************************
}

(*
  In practice, write in your main project (.dpr/.lpr) source:

  uses
    {$I mormot.uses.inc} // may include fpcx64mm or fpclibcmm
    sysutils,
    mormot.core.base,
    ...

  Then define either FPC_X64MM or FPC_LIBCMM conditional.
  If both are set, FPC_64MM will be used on x86_64, and FPC_LIBCMM otherwise.
*)


{ ---- Ready-To-Use Scenarios for Memory Manager Tuning }

{
  TL;DR:
    1. default settings target GUI/console almost-mono-threaded apps;
    2. define FPCMM_SERVER for a multi-threaded service/daemon;
    3. try FPCMM_BOOSTER on high-end hardware;
    4. try mormot.core.fpclibcmm as POSIX alternative.
}

// target a multi-threaded service on a modern CPU
// - define FPCMM_DEBUG, FPCMM_ASSUMEMULTITHREAD, FPCMM_ERMS
// - currently mormot2tests run with no contention when FPCMM_SERVER is set :)
{.$define FPCMM_SERVER}

// increase settings for more aggressive multi-threaded process
// - tiny blocks will up to 256 bytes (instead of 128 bytes);
// - will enable FPCMM_SMALLNOTWITHMEDIUM to reduce medium sleeps.
{.$define FPCMM_BOOST}

// target high-end CPU/process when FPCMM_SERVER/FPCMM_BOOST are not enough
// - will use 128 arenas for <= 256B blocks to scale on high number of cores;
// - enable FPCMM_MULTIPLESMALLNOTWITHMEDIUM to reduce small pools locks;
// - enable FPCMM_TINYPERTHREAD to assign threads to the 128 arenas.
{.$define FPCMM_BOOSTER}


{ ---- Fine Grained Memory Manager Tuning }

// includes more detailed information to WriteHeapStatus()
{.$define FPCMM_DEBUG}

// on thread contention, don't spin executing "pause" but directly call Sleep()
// - may help on specific workloads, together with the FPCMM_OSYIELD conditional
{.$define FPCMM_NOPAUSE}

{.$define FPCMM_OSYIELD}
// for yielding in contention, sched_yield is usually considered better as it's
// designed for that, while nanosleep suits actual sleeps; but for our use case
// after some "pause" spinning, we prefer to reduce syscalls and rely on a well
// defined delay of 1us by default, which aligns with typical scheduler quanta
// - define this conditional if you want to experiment with sched_yield syscall

// let FPCMM_DEBUG include SleepCycles information from rdtsc
// and FPCMM_PAUSE call rdtsc for its spinnning loop
// - since rdtsc is emulated so unrealiable on VM, and it may even trigger a
// GPF if CR4.TSD bit is set on hardened systems, it is disabled by default
{.$define FPCMM_SLEEPTSC}

// checks leaks and write them to the console after all unit finalizers
// - only basic information will be included: more debugging information (e.g.
// call stack) may be gathered using heaptrc or valgrind
{.$define FPCMM_REPORTMEMORYLEAKS}

// restore the previous MM and release all arenas during unit finalization
// - unsafe for production: later unit finalizers may still own our allocations
// - only for controlled allocator teardown diagnostics
{.$define FPCMM_UNINSTALL_AT_EXIT}

// won't check the IsMultiThread global, but assume it is true
// - multi-threaded apps (e.g. a Server Daemon instance) will be faster with it
// - mono-threaded (console/LCL) apps are faster without this conditional
{.$define FPCMM_ASSUMEMULTITHREAD}

// won't use mremap but a regular GetMem/move/FreeMem pattern for large blocks
// - depending on the actual system (e.g. on a VM), mremap may be slower
// - will disable Linux mremap() or Windows following block VirtualQuery/Alloc
{.$define FPCMM_NOMREMAP}

// customize mmap() allocation strategy
{.$define FPCMM_MEDIUM32BIT}   // enable MAP_32BIT for OsAllocMedium() on Linux
{.$define FPCMM_LARGEBIGALIGN} // THP alignment of large chunks to PMD_SIZE=2MB
{.$define FPCMM_LARGEPOPULATE} // use MAP_POPULATE flag for large blocks

// force the tiny/small blocks to be in their own arena, not with medium blocks
// - would use a little more memory, but medium pool is less likely to sleep
// - not defined for FPCMM_SERVER because no performance difference was found
// - defined for FPCMM_BOOST
{.$define FPCMM_SMALLNOTWITHMEDIUM}

// force several tiny/small blocks arenas, not with medium blocks
// - would use a little more memory, but more medium pools could help
// - defined for FPCMM_BOOSTER
{.$define FPCMM_MULTIPLESMALLNOTWITHMEDIUM}

// use the current thread id to identify the arena for a Tiny block GetMem()
// - defined for FPCMM_BOOSTER (requires enough tiny arenas)
// - warning: EXPERIMENTAL Linux and Win64 ONLY, due to very low-level asm trick
{.$define FPCMM_TINYPERTHREAD}

// MoonBot sharding layer A - separate switches allow staged bisection;
// FPCMM_MOONSHARD enables the complete supported combination
{$ifdef FPCMM_MOONSHARD}
  {$define FPCMM_MS_ARENAS}    // all classes arena-sharded (PO2 6/5)
  {$define FPCMM_MS_TABLE}     // 44 classes in a fixed 64-slot arena row
  {$define FPCMM_MS_PERTHREAD} // per-thread arena mapping
  {$define FPCMM_MS_MEDIUM}    // user medium arenas with immutable pool owner
  {$define FPCMM_ASSUMEMULTITHREAD} // MoonBot services are always multi-threaded
  {$ifdef LINUX}
    {$define FPCMM_MS_LINUX_FASTGET} // state-equivalent MoonBot GetMem fast path
  {$endif LINUX}
{$endif FPCMM_MOONSHARD}
{$ifdef FPCMM_MS_PERTHREAD}
  {$define FPCMM_TINYPERTHREAD}
{$endif FPCMM_MS_PERTHREAD}
{$ifdef FPCMM_MS_ARENAS}
  {$ifndef FPCMM_MS_TABLE}
    // the arena init walk advances one TSmallBlockType per class but strides
    // one TTinyBlockTypes per arena: with fewer classes than tiny types the
    // walk desynchronizes and silently mis-initializes every arena
    {$error FPCMM_MS_ARENAS requires FPCMM_MS_TABLE (NumSmallBlockTypes must be >= NumTinyBlockTypes)}
  {$endif}
{$endif FPCMM_MS_ARENAS}
// use "rep movsb/stosd" ERMS for blocks > 256 bytes instead of SSE2 "movaps"
// - ERMS is available since Ivy Bridge, and we use "movaps" for smallest blocks
// (to not slow down older CPUs), so it is safe to enable this on FPCMM_SERVER
{.$define FPCMM_ERMS}

// try "cmp" before "lock cmpxchg" for old processors with huge lock penalty
{.$define FPCMM_CMPBEFORELOCK}

// will export libc-like functions, and not replace the FPC MM
// - e.g. to use this unit as a stand-alone C memory allocator
{.$define FPCMM_STANDALONE}

// this whole unit will compile as void
// - may be defined e.g. when compiled as Design-Time Lazarus package
{.$define FPCMM_DISABLE}

// Product builds define this switch to reject an incomplete MoonBot profile.
{$ifdef MOONBOT_MM_PROFILE_REQUIRED}
  {$ifdef FPCMM_DISABLE}
    {$fatal MoonBot MM profile forbids FPCMM_DISABLE}
  {$endif FPCMM_DISABLE}
  {$ifdef FPCMM_STANDALONE}
    {$fatal MoonBot MM profile forbids FPCMM_STANDALONE}
  {$endif FPCMM_STANDALONE}
  {$ifndef FPCMM_BOOSTER}
    {$fatal MoonBot MM profile requires FPCMM_BOOSTER}
  {$endif FPCMM_BOOSTER}
  {$ifndef FPCMM_MOONSHARD}
    {$fatal MoonBot MM profile requires FPCMM_MOONSHARD}
  {$endif FPCMM_MOONSHARD}
{$endif MOONBOT_MM_PROFILE_REQUIRED}

interface

{$undef FPCX64MM_AVAILABLE}  // global conditional to enable this unit
{$ifdef FPC}
  {$ifdef CPUX64}            // this unit is for FPC + x86_64 only
    {$ifndef FPCMM_DISABLE}  // disabled on some targets/projects
      {$define FPCX64MM_AVAILABLE}
    {$endif FPCMM_DISABLE}
  {$endif CPUX64}
{$endif FPC}

{$ifdef FPCX64MM_AVAILABLE}
// this unit is available only for FPC + X86_64 CPU
// other targets would compile as a void unit

// cut-down version of mormot.defines.inc to make this unit standalone
{$mode Delphi}
{$inline on}
{$asmmode Intel}
{$R-} // disable Range checking
{$S-} // disable Stack checking
{$W-} // disable stack frame generation
{$Q-} // disable overflow checking
{$B-} // expect short circuit boolean

{$ifdef OLDLINUXKERNEL}
  {$define FPCMM_NOMREMAP}
{$endif OLDLINUXKERNEL}

{$ifdef FPCMM_BOOSTER}
  {$define FPCMM_BOOST}
  {$define FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
  {$define FPCMM_TINYPERTHREAD}
{$endif FPCMM_BOOSTER}
{$ifdef FPCMM_BOOST}
  {$define FPCMM_SERVER}
  {$define FPCMM_SMALLNOTWITHMEDIUM}
  {$define FPCMM_LARGEBIGALIGN} // bigger blocks implies less reallocation
{$endif FPCMM_BOOST}
{$ifdef FPCMM_SERVER}
  {$define FPCMM_DEBUG}
  {$define FPCMM_ASSUMEMULTITHREAD}
  {$define FPCMM_ERMS}
{$endif FPCMM_SERVER}
{$ifdef FPCMM_BOOSTER}
  {$undef FPCMM_DEBUG} // when performance matters more than stats
{$endif FPCMM_BOOSTER}

type
  /// Arena (middle/large) heap information as returned by CurrentHeapStatus
  TMMStatusArena = record
    /// how many bytes are currently reserved (mmap) to the Operating System
    CurrentBytes: PtrUInt;
    /// how many bytes have been reserved (mmap) to the Operating System
    CumulativeBytes: PtrUInt;
    {$ifdef FPCMM_DEBUG}
    /// maximum bytes count reserved (mmap) to the Operating System
    PeakBytes: PtrUInt;
    /// how many VirtualAlloc/mmap calls to the Operating System did occur
    CumulativeAlloc: PtrUInt;
    /// how many VirtualFree/munmap calls to the Operating System did occur
    CumulativeFree: PtrUInt;
    {$endif FPCMM_DEBUG}
    /// how many times this Arena did wait from been unlocked by another thread
    SleepCount: PtrUInt;
  end;

  /// heap information as returned by CurrentHeapStatus
  TMMStatus = record
    /// how many tiny/small memory blocks (<=2600 bytes) are currently allocated
    // - excludes blocks already accepted by FreeMem and awaiting deferred reuse
    SmallBlocks: PtrUInt;
    /// how many bytes of tiny/small memory blocks are currently allocated
    // - this size is included in Medium.CurrentBytes value, even if
    // FPCMM_SMALLNOTWITHMEDIUM has been defined
    SmallBlocksSize: PtrUInt;
    /// information about blocks up to 256KB (tiny, small and medium)
    // - includes also the memory needed for tiny/small blocks
    // - is shared by both small & medium pools even if FPCMM_SMALLNOTWITHMEDIUM
    Medium: TMMStatusArena;
    /// information about large blocks > 256KB
    // - those blocks are directly handled by the Operating System
    Large: TMMStatusArena;
    {$ifdef FPCMM_DEBUG}
    {$ifdef FPCMM_SLEEPTSC}
    /// how much rdtsc cycles were spent within SwitchToThread/nanosleep API
    // - we rdtsc since it is an indicative but very fast way of timing on
    // direct hardware
    // - warning: on virtual machines, the rdtsc opcode is usually emulated so
    // these SleepCycles number are non indicative anymore
    SleepCycles: PtrUInt;
    {$endif FPCMM_SLEEPTSC}
    {$endif FPCMM_DEBUG}
    /// how many times the Operating System Sleep/nanosleep API was called
    // - should be as small as possible - 0 is perfect
    SleepCount: PtrUInt;
    /// how many times GetMem() did block and wait for a tiny/small block
    // - see also GetSmallBlockContention() for more detailed information
    // - by design, our FreeMem() can't block thanks to its lock-less free list
    SmallGetmemSleepCount: PtrUInt;
  end;
  PMMStatus = ^TMMStatus;


/// allocate a new memory buffer
// - as FPC default heap, _Getmem(0) returns _Getmem(1)
function _GetMem(size: PtrUInt): pointer;

/// allocate a new zeroed memory buffer
function _AllocMem(Size: PtrUInt): pointer;

/// release a memory buffer
// - returns the allocated size of the supplied pointer (as FPC default heap)
function _FreeMem(P: pointer): PtrUInt;

/// change the size of a memory buffer
// - won't move any data if in-place reallocation is possible
// - as FPC default heap, _ReallocMem(P=nil,Size) maps P := _getmem(Size) and
// _ReallocMem(P,0) maps _Freemem(P)
function _ReallocMem(var P: pointer; Size: PtrUInt): pointer;

/// retrieve the allocated size of a memory buffer
// - equal or greater to the size supplied to _GetMem(), due to MM granularity
function _MemSize(P: pointer): PtrUInt; inline;

{$ifdef FPCX64MM_DIAGNOSTIC}
  {$ifndef FPCMM_STANDALONE}
    {$define FPCX64MM_DIAGNOSTIC_ACTIVE}
  {$endif FPCMM_STANDALONE}
{$endif FPCX64MM_DIAGNOSTIC}
{$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
/// set the diagnostic context captured with the first allocator invariant failure
procedure Fpcx64mmDebugSetContext(Context: PAnsiChar);
/// validate all records, deferred-free lists and large links at a quiescent point
procedure Fpcx64mmDebugVerifyHeap;
/// number of releases whose payload was filled with the diagnostic free pattern
function Fpcx64mmDebugFreedPoisonCount: QWord;
{$endif FPCX64MM_DIAGNOSTIC_ACTIVE}

{$ifdef FPCMM_SMALLLASTFREE_TEST}
procedure Fpcx64mmTestLockSmallBlockType(P: pointer; Locked: boolean);
/// lock the selected request class and its allocation fallbacks in all arenas
procedure Fpcx64mmTestLockSmallRequestClasses(Size: PtrUInt;
  ClassCount: cardinal; Locked: boolean);
/// total number of allocator sleeps across all small request sizes
function Fpcx64mmTestSmallGetmemSleepCount: cardinal;
function Fpcx64mmTestSmallLastFreeCount(P: pointer): cardinal;
procedure Fpcx64mmTestCorruptSmallLastFreeHead(P: pointer);
{$endif FPCMM_SMALLLASTFREE_TEST}

{$ifdef FPCMM_SMALLPOOL_REUSE_TEST}
function Fpcx64mmTestSmallBlockType(P: pointer): pointer;
function Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType: pointer): cardinal;
function Fpcx64mmTestSmallRetainedPool(BlockType: pointer): pointer;
{$endif FPCMM_SMALLPOOL_REUSE_TEST}

{$ifdef FPCMM_MEDIUMLASTFREE_TEST}
procedure Fpcx64mmTestLockMedium(P: pointer; Locked: boolean);
function Fpcx64mmTestMediumLastFree(P: pointer): pointer;
procedure Fpcx64mmTestCorruptMediumLastFree(P: pointer);
function Fpcx64mmTestSmallPool(P: pointer): pointer;
function Fpcx64mmTestSmallMediumInfo(P: pointer): pointer;
procedure Fpcx64mmTestLockMediumInfo(Info: pointer; Locked: boolean);
function Fpcx64mmTestMediumInfoLastFree(Info: pointer): pointer;
function Fpcx64mmTestBlockFlags(P: pointer): PtrUInt;
{$endif FPCMM_MEDIUMLASTFREE_TEST}

/// retrieve high-level statistics about the current memory manager state
// - see also GetSmallBlockContention for detailed small blocks information
// - standard GetHeapStatus and GetFPCHeapStatus gives less accurate information
// (only CurrHeapSize and MaxHeapSize are set), since we don't track "free" heap
// bytes: I can't figure how "free" memory is relevant nowadays - on 21th century
// Operating Systems, memory is virtual, and reserved/mapped by the OS but
// physically hosted in the HW RAM chips only when written the first time -
// GetHeapStatus information made sense on MSDOS with fixed 640KB of RAM
// - note that FPC GetHeapStatus and GetFPCHeapStatus is only about the
// current thread (irrelevant for sure) whereas CurrentHeapStatus is global
function CurrentHeapStatus: TMMStatus;


{$ifdef FPCMM_STANDALONE}

/// should be called before using any memory function
procedure InitializeMemoryManager;

/// should be called to finalize this memory manager process and release all RAM
procedure FreeAllMemory;

{$undef FPCMM_DEBUG} // excluded FPC-specific debugging

/// IsMultiThread global variable is not correct outside of the FPC RTL
{$define FPCMM_ASSUMEMULTITHREAD}
/// not supported to reduce dependencies and console writing
{$undef FPCMM_REPORTMEMORYLEAKS}

{$else}

type
  /// one GetSmallBlockContention info about unexpected multi-thread waiting
  TSmallBlockContention = packed record
    /// how many times a small block GetMem() has been waiting for unlock
    GetmemSleepCount: PtrUInt;
    /// the small block size on which GetMem() has been blocked
    GetmemBlockSize: PtrUInt;
    /// not used in GetSmallBlockContention() context - reserved for future use
    Reserved: PtrUInt;
  end;

  /// small blocks detailed information as returned GetSmallBlockContention
  TSmallBlockContentionDynArray = array of TSmallBlockContention;

  /// one GetSmallBlockStatus information
  TSmallBlockStatus = packed record
    /// how many times a memory block of this size has been allocated
    Total: PtrUInt;
    /// how many memory blocks of this size are currently allocated
    Current: PtrUInt;
    /// the standard size of the small memory block
    BlockSize: PtrUInt;
  end;

  /// small blocks detailed information as returned GetSmallBlockStatus
  TSmallBlockStatusDynArray = array of TSmallBlockStatus;

  /// sort order of detailed information as returned GetSmallBlockStatus
  TSmallBlockOrderBy = (
    obTotal,
    obCurrent,
    obBlockSize);

/// retrieve the use counts of allocated small blocks
// - returns maxcount biggest results, sorted by "orderby" field occurrence
function GetSmallBlockStatus(maxcount: integer = 10;
  orderby: TSmallBlockOrderBy = obTotal; count: PPtrUInt = nil; bytes: PPtrUInt = nil;
  small: PCardinal = nil; tiny: PCardinal = nil): TSmallBlockStatusDynArray;

/// retrieve all small blocks which suffered from blocking during multi-thread
// - returns maxcount biggest results, sorted by SleepCount Occurrence
function GetSmallBlockContention(
  maxcount: integer = 10): TSmallBlockContentionDynArray;


/// convenient debugging function into the console
// - if smallblockcontentioncount > 0, includes GetSmallBlockContention() info
// up to the smallblockcontentioncount biggest occurrences
// - see also RetrieveMemoryManagerInfo from mormot.core.log for runtime call
procedure WriteHeapStatus(const context: ShortString = '';
  smallblockstatuscount: integer = 8; smallblockcontentioncount: integer = 8;
  compilationflags: boolean = false);

/// convenient debugging function of the heap details into a text buffer
// - if smallblockcontentioncount > 0, includes GetSmallBlockContention() info
// up to the smallblockcontentioncount biggest occurrences
// - see also RetrieveMemoryManagerInfo from mormot.core.log for more details
// - warning: this function is not thread-safe, and return a global static buffer
function GetHeapStatus(const context: ShortString; smallblockstatuscount,
  smallblockcontentioncount: integer; compilationflags, onsameline: boolean): PAnsiChar;


const
  /// human readable information about how our MM was built
  // - similar to WriteHeapStatus(compilationflags=true) output
  FPCMM_FLAGS = ' '
    {$ifdef FPCMM_BOOSTER}           + 'BOOSTER '     {$else}
      {$ifdef FPCMM_BOOST}           + 'BOOST '       {$else}
        {$ifdef FPCMM_SERVER}        + 'SERVER '      {$endif}
      {$endif FPCMM_BOOST}
    {$endif FPCMM_BOOSTER}
    {$ifdef FPCMM_ASSUMEMULTITHREAD} + ' assumulthrd' {$endif}
    {$ifdef FPCMM_PAUSE}             + ' pause'       {$endif}
    {$ifdef FPCMM_SLEEPTSC}          + ' rdtsc'       {$endif}
    {$ifndef BSD}
      {$ifdef FPCMM_NOMREMAP}        + ' nomremap'    {$endif}
    {$endif BSD}
    {$ifdef FPCMM_SMALLNOTWITHMEDIUM}+ ' smallpool'
      {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM} + 's' {$endif} {$endif}
    {$ifdef FPCMM_TINYPERTHREAD}     + ' perthrd'  {$endif}
    {$ifdef FPCMM_MS_MEDIUM}         + ' medarena' {$endif}
    {$ifdef FPCMM_ERMS}              + ' erms'        {$endif}
    {$ifdef FPCMM_DEBUG}             + ' debug'       {$endif}
    {$ifdef FPCMM_REPORTMEMORYLEAKS} + ' repmemleak'  {$endif};

{$endif FPCMM_STANDALONE}

{$endif FPCX64MM_AVAILABLE}



implementation

{
   High-level Allocation Strategy Description
  --------------------------------------------

  The allocator handles the following families of memory blocks:
  - TINY <= 128 B (<= 256 B for FPCMM_BOOST)
    Round-robin distribution into several arenas, fed from one or several pool(s)
    (fair scaling from multi-threaded calls, with no threadvar nor GC involved)
  - SMALL <= 2600 B
    One arena per block size, fed from one or several pool(s)
  - MEDIUM <= 256 KB
    Separated pool of bitmap-marked chunks, fed from 1MB of OS mmap/virtualalloc
  - LARGE  > 256 KB
    Directly fed from OS mmap/virtualalloc with mremap when growing

  The original FastMM4 was enhanced as such, especially in FPCMM_SERVER mode:
  - FPC compatibility, even on POSIX/Linux, also for FPC specific API behavior;
  - Memory leaks and thread contention tracked without performance impact;
  - Detailed per-block statistics with little performance penalty;
  - x86_64 code was refactored and tuned in respect to 2020's hardware;
  - Inlined SSE2 movaps loop or ERMS are more efficient that subfunction(s);
  - New round-robin thread-friendly arenas of tiny blocks;
  - Those arenas can be configured by size, and assigned by thread ID;
  - Tiny and small blocks can fed from their own pool(s), not the medium pool;
  - Lock-less free lists to reduce tiny/small/medium FreeMem thread contention;
  - Large blocks logic has been rewritten, especially realloc;
  - OsAllocLarge() can use MAP_POPULATE to reduce page faults;
  - On Linux, mremap is used for efficient realloc of large blocks;
  - Largest blocks can grow by 2MB=PMD_SIZE chunks for even faster mremap.

  About locking:
  - Tiny and Small blocks have their own per-size lock;
  - Tiny and Small blocks have per-pool lock when feeding;
  - Lock-less free lists reduce tiny/small GetMem/FreeMem thread contention;
  - Lock-less free lists reduce medium FreeMem thread contention;
  - Medium and Large blocks have one giant lock over their own pool;
  - Medium blocks have an unlocked prefetched memory chunk to reduce contention;
  - Large blocks don't lock during mmap/virtualalloc system calls;
  - SwitchToThread/nanosleep OS call is done after initial spinning;
  - FPCMM_DEBUG / WriteHeapStatus helps identifying the lock contention(s).

}

{$ifdef FPCX64MM_AVAILABLE}
// this unit is available only for FPC + X86_64 CPU

{$ifndef FPCMM_NOPAUSE}
  // on contention problem, execute "pause" opcode and spin retrying the lock
  // - defined by default to follow Intel recommendatations from
  // https://software.intel.com/content/www/us/en/develop/articles/benefitting-power-and-performance-sleep-loops.html
  // - spinning loop is either using constants or rdtsc (if FPCMM_SLEEPTSC is set)
  // - on SkylakeX (Intel 7th gen), "pause" opcode went from 10-20 to 140 cycles
  // so our constants below will favor those latest CPUs with a longer pause
  {$define FPCMM_PAUSE}
{$endif FPCMM_NOPAUSE}

{$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
  {$define FPCMM_SMALLNOTWITHMEDIUM}
{$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}


{ ********* Operating System Specific API Calls }

{$ifdef MSWINDOWS}

// Win64: any assembler function with sub-calls should have a stack frame
// -> nostackframe is defined only on Linux or for functions with no nested call
{$undef NOSFRAME}

const
  kernel32 = 'kernel32.dll';

  {$ifdef FPCMM_MS_MEDIUM}
  MediumBlockAlignment     = 1 shl 21; // resolve pool header from any block
  MediumBlockAlignmentMask = MediumBlockAlignment - 1;
  {$endif FPCMM_MS_MEDIUM}

  MEM_COMMIT   = $1000;
  MEM_RESERVE  = $2000;
  MEM_RELEASE  = $8000;
  MEM_FREE     = $10000;
  MEM_TOP_DOWN = $100000;

  PAGE_READWRITE = 4;
  PAGE_GUARD = $0100;
  PAGE_VALID = $00e6; // PAGE_READONLY or PAGE_READWRITE or PAGE_EXECUTE or
      // PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY

type
  // VirtualQuery() API result structure
  TMemInfo = record
    BaseAddress, AllocationBase: PtrUInt;
    AllocationProtect: cardinal;
    PartitionId: word;
    RegionSize: PtrUInt;
    State, Protect, MemType: cardinal;
  end;

function VirtualAlloc(lpAddress: pointer;
   dwSize: PtrUInt; flAllocationType, flProtect: cardinal): pointer;
  stdcall; external kernel32 name 'VirtualAlloc';

function VirtualFree(lpAddress: pointer; dwSize: PtrUInt;
   dwFreeType: cardinal): LongBool;
  stdcall; external kernel32 name 'VirtualFree';

function VirtualQuery(lpAddress, lpMemInfo: pointer; dwLength: PtrUInt): PtrUInt;
  stdcall; external kernel32 name 'VirtualQuery';

procedure SwitchToThread;
  stdcall; external kernel32 name 'SwitchToThread';

function OsAllocMedium(Size: PtrInt): pointer; inline;
{$ifdef FPCMM_MS_MEDIUM}
var
  raw: pointer;
{$endif FPCMM_MS_MEDIUM}
begin
  {$ifdef FPCMM_MS_MEDIUM}
  // Keep the reservation alive around the aligned committed pool. This avoids
  // a release/re-reserve race and lets FreeMem recover its immutable owner by
  // masking any medium-block address to the pool header.
  raw := VirtualAlloc(nil, Size + MediumBlockAlignment,
    MEM_RESERVE, PAGE_READWRITE);
  if raw = nil then
  begin
    result := nil;
    exit;
  end;
  result := pointer((PtrUInt(raw) + MediumBlockAlignmentMask) and
    not MediumBlockAlignmentMask);
  if VirtualAlloc(result, Size, MEM_COMMIT, PAGE_READWRITE) = nil then
  begin
    VirtualFree(raw, 0, MEM_RELEASE);
    result := nil;
  end;
  {$else}
  // bottom-up allocation to reduce fragmentation
  result := VirtualAlloc(nil, Size, MEM_COMMIT, PAGE_READWRITE);
  {$endif FPCMM_MS_MEDIUM}
end;

function OsAllocLarge(Size: PtrInt): pointer; inline;
begin
  // FastMM4 uses top-down allocation (MEM_TOP_DOWN) of large blocks to "reduce
  // fragmentation", but on a 64-bit system I am not sure of this statement, and
  // VirtualAlloc() was reported to have a huge slowdown due to this option
  // https://randomascii.wordpress.com/2011/08/05/making-virtualalloc-arbitrarily-slower
  result := VirtualAlloc(nil, Size, MEM_COMMIT, PAGE_READWRITE);
end;

procedure OsFreeMedium(ptr: pointer; Size: PtrInt); inline;
{$ifdef FPCMM_MS_MEDIUM}
var
  nfo: TMemInfo;
{$endif FPCMM_MS_MEDIUM}
begin
  {$ifdef FPCMM_MS_MEDIUM}
  FillChar(nfo, SizeOf(nfo), 0);
  if VirtualQuery(ptr, @nfo, SizeOf(nfo)) = SizeOf(nfo) then
    VirtualFree(pointer(nfo.AllocationBase), 0, MEM_RELEASE);
  {$else}
  VirtualFree(ptr, 0, MEM_RELEASE);
  {$endif FPCMM_MS_MEDIUM}
end;

procedure OsFreeLarge(ptr: pointer; Size: PtrInt); forward;
// implemented below with knowledge of PLargeBlockHeader/LargeBlockIsSegmented

{$ifndef FPCMM_NOMREMAP}

function OsRemapLarge(addr: pointer; old_len: size_t; var new_len: size_t): pointer;
var
  nfo: TMemInfo;
  next: pointer;
  nextsize, tomove: size_t;
const
  LargeBlockIsSegmented = 8; // forward definition
begin
  // old_len and new_len have 64KB granularity, so match Windows page size
  nextsize := new_len - old_len;
  if PtrInt(nextsize) > 0 then
  begin
    // try to allocate the memory just after the existing one
    FillChar(nfo, SizeOf(nfo), 0);
    next := addr + old_len;
    if (VirtualQuery(next, @nfo, SizeOf(nfo)) = SizeOf(nfo)) and
       (nfo.State = MEM_FREE) and
       (nfo.BaseAddress <= PtrUInt(next)) and // enough space?
       (nfo.BaseAddress + nfo.RegionSize >= PtrUInt(next) + nextsize) and
       // set the address space in two reserve + commit steps for thread safety
       (VirtualAlloc(next, nextsize, MEM_RESERVE, PAGE_READWRITE) <> nil) and
       (VirtualAlloc(next, nextsize, MEM_COMMIT, PAGE_READWRITE) <> nil) then
      begin
        new_len := new_len or LargeBlockIsSegmented; // several VirtualFree()
        result := addr; // in-place realloc: no need to move memory :)
        exit;
      end;
  end;
  // we need to use the slower but safe Alloc/Move/Free pattern
  result := OsAllocLarge(new_len);
  tomove := new_len;
  if tomove > old_len then // handle size up or down
    tomove := old_len;
  Move(addr^, result^, tomove); // RTL non-volatile asm or our AVX MoveFast()
  OsFreeLarge(addr, old_len);
end;

{$endif FPCMM_NOMREMAP}

// aligning large chunks > 4MB to 2MB units seems always a good idea
{$define FPCMM_LARGEBIGALIGN}

// experimental VirtualQuery detection of object class - use at your own risk
{$define FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}

{$else}

uses
  {$ifndef DARWIN}
  syscall,
  {$endif DARWIN}
  BaseUnix;

// in practice, SYSV ABI seems to not require a stack frame, as Win64 does, for
// our use case of nested calls with no local stack storage and direct kernel
// syscalls - but since it is clearly undocumented, we set it on LINUX only
// -> appears to work with no problem from our tests: feedback is welcome!
// -> see FPCMM_NOSFRAME conditional to disable it on LINUX
{$ifdef LINUX}
  {$define NOSFRAME}
{$else}
  {$define OLDLINUXKERNEL}      // no Linuxism on BSD
  {$undef FPCMM_TINYPERTHREAD}  // no inlined pthread_self on BSD
{$endif LINUX}

// on Linux, mremap() on PMD_SIZE=2MB aligned data can make a huge speedup
// - Transparent Huge Pages (THP) exists since Kernel 2.6.38
// - HAVE_MOVE_PMD enabled on arm64 since 2020 - https://lwn.net/Articles/833208
// - FreeBSD has a similar behavior with its Superpages - feedback is needed
{$ifdef LINUX}
  {$define FPCMM_LARGEBIGALIGN} // align large chunks to 21-bit = 2MB = PMD_SIZE
{$endif LINUX}

// we directly call the OS Kernel, so this unit doesn't require any libc

const
  {$ifdef OLDLINUXKERNEL}
    {$undef FPCMM_MEDIUM32BIT}
    MAP_POPULATE = 0;
  {$else}
    /// put the mapping in first 2 GB of memory (31-bit addresses) - 2.4.20, 2.6
    MAP_32BIT = $40;
    /// populate (prefault) pagetables to avoid page faults later - 2.5.46
    MAP_POPULATE = $08000;
  {$endif OLDLINUXKERNEL}

  /// tiny/small/medium blocks mmap() flags
  // - MAP_POPULATE is not included because small and medium blocks are sparsely
  // accessed, and OsAllocMedium() is done within the global medium lock
  // - FPCMM_MEDIUM32BIT allocates only 31-bit pointers, but may be incompatible
  // e.g. with TOrmTable for data >256KB so would require the NOPOINTEROFFSET
  // conditional - therefore is not set by default
  MAP_MEDIUM = MAP_PRIVATE or MAP_ANONYMOUS
     {$ifdef FPCMM_MEDIUM32BIT} or MAP_32BIT {$endif};

  /// large blocks mmap() flags
  // - no MAP_32BIT since could use the whole 64-bit address space
  // - MAP_POPULATE is not included by default, even if mmap/mremap are called
  // outside the large blocks lock: in practice, it may lead to unnecessary
  // memory usage and increased initial mapping time - set FPCMM_LARGEPOPULATE
  MAP_LARGE = MAP_PRIVATE or MAP_ANONYMOUS
     {$ifdef FPCMM_LARGEPOPULATE} or MAP_POPULATE {$endif};

  {$ifdef FPCMM_MS_MEDIUM}
  MediumBlockAlignment     = 1 shl 21; // resolve pool header from any block
  MediumBlockAlignmentMask = MediumBlockAlignment - 1;
  {$endif FPCMM_MS_MEDIUM}

{$ifdef FPCMM_MEDIUM32BIT}
var
  AllocMediumflags: integer = MAP_MEDIUM;
{$else}
  AllocMediumflags = MAP_MEDIUM;
{$endif FPCMM_MEDIUM32BIT}

function OsAllocMediumRaw(Size: PtrInt): pointer;
begin
  result := fpmmap(nil, Size, PROT_READ or PROT_WRITE, AllocMediumflags, -1, 0);
  if result = MAP_FAILED then
    result := nil; // as VirtualAlloc()
  {$ifdef FPCMM_MEDIUM32BIT}
  if (result <> nil) or
     ((AllocMediumflags and MAP_32BIT) = 0) then
    exit;
  // try with no 2GB limit from now on
  AllocMediumflags := AllocMediumflags and not MAP_32BIT;
  result := OsAllocMediumRaw(Size);
  {$endif FPCMM_MEDIUM32BIT}
end;

function OsAllocMedium(Size: PtrInt): pointer;
{$ifdef FPCMM_MS_MEDIUM}
var
  raw: pointer;
  allocsize, prefix, suffix: PtrInt;
{$endif FPCMM_MS_MEDIUM}
begin
  {$ifdef FPCMM_MS_MEDIUM}
  // Keep the existing 1.25MB pool size, but map it at a 2MB boundary so its
  // immutable owner can be read from the pool header on FreeMem/ReallocMem.
  allocsize := Size + MediumBlockAlignment;
  raw := OsAllocMediumRaw(allocsize);
  if raw = nil then
  begin
    result := nil;
    exit;
  end;
  result := pointer((PtrUInt(raw) + MediumBlockAlignmentMask) and
    not MediumBlockAlignmentMask);
  prefix := PtrUInt(result) - PtrUInt(raw);
  if prefix <> 0 then
    fpmunmap(raw, prefix);
  suffix := allocsize - prefix - Size;
  if suffix <> 0 then
    fpmunmap(PByte(result) + Size, suffix);
  {$else}
  result := OsAllocMediumRaw(Size);
  {$endif FPCMM_MS_MEDIUM}
end;

function OsAllocLarge(Size: PtrInt): pointer; inline;
begin
  result := fpmmap(nil, Size, PROT_READ or PROT_WRITE, MAP_LARGE, -1, 0);
  if result = MAP_FAILED then
    result := nil; // as VirtualAlloc()
end;

procedure OsFreeMedium(ptr: pointer; Size: PtrInt); inline;
begin
  fpmunmap(ptr, Size);
end;

procedure OsFreeLarge(ptr: pointer; Size: PtrInt); inline;
begin
  fpmunmap(ptr, Size);
end;

{$ifdef LINUX}

{$ifndef FPCMM_NOMREMAP}

const
  syscall_nr_mremap = 25; // valid on x86_64 Linux and Android
  MREMAP_MAYMOVE = 1;

function OsRemapLarge(addr: pointer; old_len, new_len: size_t): pointer;
begin
  // let the Linux Kernel mremap() the memory using its TLB magic
  result := pointer(do_syscall(syscall_nr_mremap, TSysParam(addr),
    TSysParam(old_len), TSysParam(new_len), TSysParam(MREMAP_MAYMOVE)));
  if result <> MAP_FAILED then
    exit;
  // some OS (e.g. Alma Linux 9 with 5.x kernel) seems to fail sometimes :(
  // https://github.com/ClickHouse/ClickHouse/issues/52955#issuecomment-1664710083
  // -> it should not, because we use the MREMAP_MAYMOVE flag - but anyway...
  // -> fallback to safe, simple (and slower) Alloc/Move/Free pattern
  result := OsAllocLarge(new_len);
  if result = nil then
    exit; // out of memory
  if new_len > old_len then
    new_len := old_len; // resize down
  Move(addr^, result^, new_len); // RTL non-volatile asm or our AVX MoveFast()
  OsFreeLarge(addr, old_len);
end;

{$endif FPCMM_NOMREMAP}

{$ifdef FPCMM_TINYPERTHREAD}
function pthread_self: PtrUInt; external;
{$endif FPCMM_TINYPERTHREAD}

// experimental detection of object class - use at your own risk
{$define FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
// (untested on BSD/DARWIN)

{$else} // BSD branch

{$define FPCMM_NOMREMAP} // mremap is a Linux-specific syscall
{$undef FPCMM_OSYIELD}   // no yield syscall defined

{$endif LINUX}

{$ifdef FPCMM_OSYIELD}
procedure SwitchToThread;
begin
  // trigger more syscalls than nanosleep, with no actual benefit
  Do_SysCall(syscall_nr_sched_yield); // properly defined in syscall.pp
end;
{$else}
procedure SwitchToThread;
var
  t: TTimeSpec;
begin
  // note: nanosleep() may flood the kernel with timer/scheduling events under
  // repeated calls - but here we spin-and-pause between calls
  t.tv_sec := 0;
  t.tv_nsec := 1000; // 1us seems fair enough in respect to OS timers resolution
  fpnanosleep(@t, nil);
end;
{$endif FPCMM_OSYIELD}

{$endif MSWINDOWS}

// fallback to safe and simple Alloc/Move/Free pattern
{$ifdef FPCMM_NOMREMAP}

function OsRemapLarge(addr: pointer; old_len, new_len: size_t): pointer;
begin
  result := OsAllocLarge(new_len);
  if new_len > old_len then
    new_len := old_len; // resize down
  Move(addr^, result^, new_len); // RTL non-volatile asm or our AVX MoveFast()
  OsFreeLarge(addr, old_len);
end;

{$undef FPCMM_LARGEBIGALIGN}  // keep 64KB granularity if no mremap()

{$endif FPCMM_NOMREMAP}


{ ********* Some Assembly Helpers }

// low-level conditional to disable nostackframe code on Linux
{$ifdef FPCMM_NOSFRAME}
  {$undef NOSFRAME}
{$endif FPCMM_NOSFRAME}

var
  HeapStatus: TMMStatus;

procedure ReleaseCoreSafe;
var
  _c, _s, _d, _8, _9, _10, _11: pointer;
begin
asm
        mov     _c,  rcx  // always preserve volatile registers
        mov     _s,  rsi
        mov     _d,  rdi
        mov     _8,  r8
        mov     _9,  r9
        mov     _10, r10
        mov     _11, r11
        {$ifdef FPCMM_SLEEPTSC}
        rdtsc // returns the TSC in EDX:EAX
        shl     rdx, 32
        or      rax, rdx
        push    rax
        call    SwitchToThread
        pop     rcx
        rdtsc
        shl     rdx, 32
        or      rax, rdx
        lea     rdx, [rip + HeapStatus]
        sub     rax, rcx
   lock add     qword ptr [rdx + TMMStatus.SleepCycles], rax
        {$else}
        call    SwitchToThread
        lea     rdx, [rip + HeapStatus]
        {$endif FPCMM_SLEEPTSC}
   lock inc     qword ptr [rdx + TMMStatus.SleepCount]
        mov     rcx, _c
        mov     rsi, _s
        mov     rdi, _d
        mov     r8,  _8
        mov     r9,  _9
        mov     r10, _10
        mov     r11, _11
end;
end;

procedure NotifyArenaAlloc(var Arena: TMMStatusArena; Size: PtrUInt);
  nostackframe; assembler;
asm
        {$ifdef FPCMM_DEBUG}
   lock add     qword ptr [Arena].TMMStatusArena.CurrentBytes, Size
   lock add     qword ptr [Arena].TMMStatusArena.CumulativeBytes, Size
   lock inc     qword ptr [Arena].TMMStatusArena.CumulativeAlloc
        mov     rax, qword ptr [Arena].TMMStatusArena.CurrentBytes
        cmp     rax, qword ptr [Arena].TMMStatusArena.PeakBytes
        jbe     @s
        mov     qword ptr [Arena].TMMStatusArena.PeakBytes, rax
@s:     {$else}
        {$ifdef FPCMM_MS_MEDIUM} lock {$endif}
        add     qword ptr [Arena].TMMStatusArena.CurrentBytes, Size
        {$ifdef FPCMM_MS_MEDIUM} lock {$endif}
        add     qword ptr [Arena].TMMStatusArena.CumulativeBytes, Size
       {$endif FPCMM_DEBUG}
end;

procedure NotifyMediumLargeFree(var Arena: TMMStatusArena; Size: PtrUInt);
  nostackframe; assembler;
asm
        neg     Size
        {$ifdef FPCMM_DEBUG}
   lock add     qword ptr [Arena].TMMStatusArena.CurrentBytes, Size
   lock inc     qword ptr [Arena].TMMStatusArena.CumulativeFree
        {$else}
        {$ifdef FPCMM_MS_MEDIUM} lock {$endif}
        add     qword ptr [Arena].TMMStatusArena.CurrentBytes, Size
        {$endif FPCMM_DEBUG}
end;


{ ********* Constants and Data Structures Definitions }

// during spinning, there is clearly thread contention: in this case, plain
// "cmp" before "lock cmpxchg" is mandatory to leverage the CPU cores
{$define FPCMM_CMPBEFORELOCK_SPIN}

// prepare a Medium arena chunk in TMediumInfo.Prefetch outside of the lock
{$define FPCMM_MEDIUMPREFETCH}

const
  // define maximum size of tiny blocks, and the number of arenas
  {$ifdef FPCMM_MS_ARENAS}
  NumTinyBlockTypesPO2  = 6; // 44 classes in a 64-slot arena row
  NumTinyBlockArenasPO2 = 5; // 32 arenas
  {$else}
  {$ifdef FPCMM_BOOSTER}
  NumTinyBlockTypesPO2  = 4; // tiny are <= 256 bytes
  NumTinyBlockArenasPO2 = 7; // 128 arenas
  {$else}
    {$ifdef FPCMM_BOOST}
    NumTinyBlockTypesPO2  = 4; // tiny are <= 256 bytes
    NumTinyBlockArenasPO2 = 3; // 8 arenas
    {$else}
    // default (or FPCMM_SERVER) settings
    NumTinyBlockTypesPO2  = 3; // multiple arenas for tiny blocks <= 128 bytes
    NumTinyBlockArenasPO2 = 3; // 8 round-robin arenas (including Small[])
    {$endif FPCMM_BOOST}
  {$endif FPCMM_BOOSTER}
  {$endif FPCMM_MS_ARENAS}

  {$ifdef FPCMM_MS_TABLE}
  // Keep the proven FastMM/mORMot 44-class table up to 2608 bytes.  Each
  // sharded arena still occupies 64 cache-line slots, so selecting an arena
  // remains a shift-only 4096-byte stride on the GetMem hot path.  The 20
  // trailing slots are initialized but no GetmemLookup entry points to them.
  // In arena 0 the first two retain the allocator's cold same-size fallback
  // for the largest class.  No tail slot in any row is addressable by lookup;
  // all other tail records are pure physical padding.
  NumSmallBlockClasses     = 44;
  NumSmallBlockTypeSlots   = 64;
  NumSmallBlockTypes       = NumSmallBlockTypeSlots;
  MaximumSmallBlockSize    = 2608;
  {$else}
  NumSmallBlockTypes       = 46;
  NumSmallBlockTypeSlots   = NumSmallBlockTypes - 2; // last 2 are redundant
  NumSmallBlockClasses     = NumSmallBlockTypeSlots;
  MaximumSmallBlockSize    = 2608;
  {$endif FPCMM_MS_TABLE}
  NumTinyBlockTypes        =
     1 shl NumTinyBlockTypesPO2; // 8 (128B) or 16 (256B)
  NumTinyBlockArenas       =
     (1 shl NumTinyBlockArenasPO2) - 1; // -1 = main Small[]
  NumSmallInfoBlock        =
    NumSmallBlockTypes + NumTinyBlockArenas * NumTinyBlockTypes;
  SmallBlockSizes: array[0..NumSmallBlockTypes - 1] of word = (
    16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240, 256,
    272, 288, 304, 320, 352, 384, 416, 448, 480, 528, 576, 624, 672, 736, 800,
     880, 960, 1056, 1152, 1264, 1376, 1504, 1648, 1808, 1984, 2176, 2384,
     MaximumSmallBlockSize
     {$ifdef FPCMM_MS_TABLE}
     // No size lookup can select these 20 physical tail entries.  In arena 0
     // the first two are cold same-size fallback managers after contention.
     , MaximumSmallBlockSize, MaximumSmallBlockSize, MaximumSmallBlockSize,
     MaximumSmallBlockSize, MaximumSmallBlockSize, MaximumSmallBlockSize,
     MaximumSmallBlockSize, MaximumSmallBlockSize, MaximumSmallBlockSize,
     MaximumSmallBlockSize, MaximumSmallBlockSize, MaximumSmallBlockSize,
     MaximumSmallBlockSize, MaximumSmallBlockSize, MaximumSmallBlockSize,
     MaximumSmallBlockSize, MaximumSmallBlockSize, MaximumSmallBlockSize,
     MaximumSmallBlockSize, MaximumSmallBlockSize
     {$else}
     // Two redundant entries let a contended allocation try larger slots.
     , MaximumSmallBlockSize, MaximumSmallBlockSize
     {$endif FPCMM_MS_TABLE}
     );

  SmallBlockGranularity        = 16;
  NumSmallBlockGranularitySlots =
    (MaximumSmallBlockSize + SmallBlockGranularity - 1) div
      SmallBlockGranularity;
  TargetSmallBlocksPerPool     = 48;
  MinimumSmallBlocksPerPool    = 12;
  SmallBlockDownsizeCheckAdder = 64;
  SmallBlockUpsizeAdder        = 32;
  SmallBlockTypePO2            = 6;  // SizeOf(TSmallBlockType)=64
  SmallBlockHotPoolThreshold   = 8;

  MediumBlockPoolSizeMem       = 20 * 64 * 1024;
  MediumBlockPoolSize          = MediumBlockPoolSizeMem - 16;
  {$ifdef FPCMM_MS_MEDIUM}
  {$if MediumBlockPoolSizeMem > MediumBlockAlignment}
    {$error MediumBlockAlignment must cover a complete medium pool}
  {$ifend}
  NumMediumBlockArenasPO2      = 2; // 4 arenas
  NumMediumBlockArenas         = 1 shl NumMediumBlockArenasPO2;
  {$endif FPCMM_MS_MEDIUM}
  MediumBlockSizeOffset        = 48;
  MinimumMediumBlockSize       = 11 * 256 + MediumBlockSizeOffset;
  MediumBlockBinsPerGroup      = 32;
  MediumBlockBinGroupCount     = 32;
  MediumBlockBinCount = MediumBlockBinGroupCount * MediumBlockBinsPerGroup;
  MediumBlockGranularity       = 256;
  MaximumMediumBlockSize       =
    MinimumMediumBlockSize + (MediumBlockBinCount - 1) * MediumBlockGranularity;
  OptimalSmallBlockPoolSizeLowerLimit =
    29 * 1024 - MediumBlockGranularity + MediumBlockSizeOffset;
  OptimalSmallBlockPoolSizeUpperLimit =
    // HARD CEILING 64KB: TSmallBlockType.OptimalBlockPoolSize and
    // MinimumBlockPoolSize are Word fields, read with "movzx edi, [rbx]..."
    // when splitting a medium block into a small pool. Raising this limit
    // above 65535 truncates the split size and corrupts the medium free
    // list (crash in RemoveMediumFreeBlock) - verified by fuzzing.
    64 * 1024 - MediumBlockGranularity + MediumBlockSizeOffset;
  MaximumSmallBlockPoolSize   =
    OptimalSmallBlockPoolSizeUpperLimit + MinimumMediumBlockSize;
  MediumInPlaceDownsizeLimit  = MinimumMediumBlockSize div 4;

  {$ifdef FPCMM_SLEEPTSC}
  // pause using rdtsc (30 cycles latency on hardware but emulated on VM)
  SpinMediumLockTSC          = 10000;
  SpinLargeLockTSC           = 10000;
  {$ifdef FPCMM_PAUSE}
  SpinSmallGetmemLockTSC     = 1000;
  {$endif FPCMM_PAUSE}
  {$else}
  // pause with constant spinning counts (empirical values)
  SpinMediumLockCount        = pred(6 shl 5); // with exponential pause backoff
  SpinLargeLockCount         = 1000;          // linear backoff is enough here
  {$ifdef FPCMM_PAUSE}
  SpinSmallGetmemLockCount   = 500;
  {$endif FPCMM_PAUSE}
  SpinMediumFreememLockCount = 500;
  {$endif FPCMM_SLEEPTSC}

  {$ifdef FPCMM_ERMS}
  // pre-ERMS expects at least 256 bytes, IvyBridge+ with ERMS is good from 64
  // (copy_user_enhanced_fast_string() in recent Linux kernel uses 64)
  // see https://stackoverflow.com/a/43837564/458259 for explanations and timing
  // -> "movaps" loop is used up to 256 bytes of data: good on all CPUs
  // -> "movnt" Move/MoveFast is used for large blocks: always faster than ERMS
  ErmsMinSize = 256;
  {$endif FPCMM_ERMS}

  // some binary-level constants for internal flags
  IsFreeBlockFlag                = 1;
  IsMediumBlockFlag              = 2;
  IsSmallBlockPoolInUseFlag      = 4;
  IsLargeBlockFlag               = 4;
  PreviousMediumBlockIsFreeFlag  = 8;
  LargeBlockIsSegmented          = 8; // see also OsRemapLarge() above
  DropSmallFlagsMask             = -8;
  ExtractSmallFlagsMask          = 7;
  DropMediumAndLargeFlagsMask    = -16;
  ExtractMediumAndLargeFlagsMask = 15;

type
  PSmallBlockPoolHeader = ^TSmallBlockPoolHeader;

  // information for each small block size - 64 bytes long = CPU cache line
  TSmallBlockType = packed record
    Locked: boolean;
    AllowedGroupsForBlockPoolBitmap: byte;
    BlockSize: Word;
    MinimumBlockPoolSize: Word;
    OptimalBlockPoolSize: Word;
    NextPartiallyFreePool: PSmallBlockPoolHeader;
    PreviousPartiallyFreePool: PSmallBlockPoolHeader;
    NextSequentialFeedBlockAddress: pointer;
    MaxSequentialFeedBlockAddress: pointer;
    CurrentSequentialFeedPool: PSmallBlockPoolHeader;
    GetmemCount: cardinal;
    FreememCount: cardinal;
    LastFreeLocked: boolean;
    EmptyPoolReuseScore: byte;
    Padding: array[1 .. 2] of byte;
    LastFreeCount: cardinal;
  end;
  PSmallBlockType = ^TSmallBlockType;

  TSmallBlockTypes = array[0..NumSmallBlockTypes - 1] of TSmallBlockType;
  TTinyBlockTypes  = array[0..NumTinyBlockTypes - 1]  of TSmallBlockType;
  TSmallBlockInfo = record
    Small: TSmallBlockTypes;
    Tiny: array[0..NumTinyBlockArenas - 1] of TTinyBlockTypes;
    GetmemLookup: array[0..NumSmallBlockGranularitySlots - 1] of byte;
    // safe access to IsMultiThread global variable - accessed via GOT sub-call
    IsMultiThreadPtr: PBoolean;
    {$ifndef FPCMM_TINYPERTHREAD}
    TinyCurrentArena: integer;
    {$endif FPCMM_TINYPERTHREAD}
    { Assembly indexes this counter by requested-size granularity, not by
      logical class ordinal. }
    GetmemSleepCount: array[0..NumSmallBlockGranularitySlots - 1] of cardinal;
    // some fiedls here because there was no room in TSmallBlockType
    {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM} // PMediumBlockInfo lookup
    SmallMediumBlockInfo: array[0..NumSmallInfoBlock - 1] of pointer;
    {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
    SmallLastFree: array[0 .. NumSmallInfoBlock - 1] of pointer;
  end;

  TSmallBlockPoolHeader = record
    BlockType: PSmallBlockType;
    NextPartiallyFreePool: PSmallBlockPoolHeader;
    PreviousPartiallyFreePool: PSmallBlockPoolHeader;
    FirstFreeBlock: pointer;
    BlocksInUse: cardinal;
    SmallBlockPoolSignature: cardinal;
    FirstBlockPoolPointerAndFlags: PtrUInt;
  end;

  PMediumBlockPoolHeader = ^TMediumBlockPoolHeader;
  TMediumBlockPoolHeader = record
    PreviousMediumBlockPoolHeader: PMediumBlockPoolHeader;
    NextMediumBlockPoolHeader: PMediumBlockPoolHeader;
    Reserved1: PtrUInt;
    FirstMediumBlockSizeAndFlags: PtrUInt;
  end;

  PMediumFreeBlock = ^TMediumFreeBlock;
  TMediumFreeBlock = record
    PreviousFreeBlock: PMediumFreeBlock;
    NextFreeBlock: PMediumFreeBlock;
  end;

  PMediumBlockInfo = ^TMediumBlockInfo;
  TMediumBlockInfo = record
    Locked: boolean;
    {$ifdef FPCMM_MEDIUMPREFETCH}
    PrefetchLocked: boolean;
    {$endif FPCMM_MEDIUMPREFETCH}
    LastFreeLocked: boolean;
    PoolsCircularList: TMediumBlockPoolHeader;
    LastSequentiallyFed: pointer;
    SequentialFeedBytesLeft: cardinal;
    BinGroupBitmap: cardinal;
    {$ifdef FPCMM_MEDIUMPREFETCH}
    Prefetch: pointer;
    {$endif FPCMM_MEDIUMPREFETCH}
    {$ifndef FPCMM_ASSUMEMULTITHREAD}
    IsMultiThreadPtr: PBoolean; // safe access to IsMultiThread global variable
    {$endif FPCMM_ASSUMEMULTITHREAD}
    LastFree: pointer;
    BinBitmaps: array[0..MediumBlockBinGroupCount - 1] of cardinal;
    Bins: array[0..MediumBlockBinCount - 1] of TMediumFreeBlock;
  end;

  PLargeBlockHeader = ^TLargeBlockHeader;
  TLargeBlockHeader = record
    PreviousLargeBlockHeader: PLargeBlockHeader;
    NextLargeBlockHeader: PLargeBlockHeader;
    Reserved: PtrUInt;
    BlockSizeAndFlags: PtrUInt;
  end;

const
  BlockHeaderSize            = SizeOf(pointer);
  SmallBlockPoolHeaderSize   = SizeOf(TSmallBlockPoolHeader);
  SmallBlockTypeSize         = SizeOf(TSmallBlockType);
  MediumBlockPoolHeaderSize  = SizeOf(TMediumBlockPoolHeader);
  LargeBlockHeaderSize       = SizeOf(TLargeBlockHeader);
  LargeBlockGranularityAnd   = (1 shl 16) - 1; // 64KB minimum for large blocks
  {$ifdef FPCMM_LARGEBIGALIGN}
  LargeBlockGranularity2And  = (1 shl 21) - 1; // PMD_SIZE=2MB granularity
  LargeBlockGranularity2Size = 2 shl 21;  // for size >= 4MB
  // on Linux, mremap() on PMD_SIZE=2MB aligned data can make a huge speedup
  {$endif FPCMM_LARGEBIGALIGN}

// all T*BlockInfo variables are local to this unit, so are FPC_PIC compatible
{$CODEALIGN VARMIN=64} // align all those var to 64 bytes = CPU cache line size
var
  SmallBlockInfo: TSmallBlockInfo;
  MediumBlockInfo: TMediumBlockInfo;
  {$ifdef FPCMM_MS_MEDIUM}
  MediumBlockInfoExtra: array[1..NumMediumBlockArenas - 1] of TMediumBlockInfo;
  MediumBlockInfoLookup: array[0..NumMediumBlockArenas - 1] of PMediumBlockInfo;
  {$endif FPCMM_MS_MEDIUM}
  {$ifdef FPCMM_SMALLNOTWITHMEDIUM}
  {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
  SmallMediumBlockInfo: array[0.. (NumTinyBlockTypes * 2) - 2] of TMediumBlockInfo;
  // -2 to ensure same small block size won't share the same medium block
  // note: including NumTinyBlockArenasPO2 to the calculation has no benefit
  {$else}
  SmallMediumBlockInfo: array[0..0] of TMediumBlockInfo;
  {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
  {$else}
  SmallMediumBlockInfo: TMediumBlockInfo absolute MediumBlockInfo;
  {$endif FPCMM_SMALLNOTWITHMEDIUM}
  LargeBlocksLocked: boolean;
  LargeBlocksCircularList: TLargeBlockHeader;

{$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
procedure LockLargeBlocks; forward;
function _FreeMemSize(P: pointer; Size: PtrUInt): PtrInt; forward;

const
  // Kept out of release builds: the registry must never allocate through the MM
  // it checks, and a fixed capacity makes exhaustion a reported invariant.
  // The registry is split into independently locked segments so this layer
  // does not re-serialize the arena-sharded allocator it observes; a probe
  // never leaves its segment, which also bounds the worst-case miss scan.
  {$ifdef FPCX64MM_DIAGNOSTIC_LARGE}
  // 4M-record registry (~328MiB); a full VerifyHeap scan makes all pages
  // resident. It is intended only for short, allocation-heavy diagnostics
  // workloads holding millions of live blocks at once (memory_chaos peaks
  // above 1M: 32 workers x 512 slots x up to hundreds of nested RTL strings
  // per slot) - the default 128K records latch 'registry-full' there
  DiagRegistryBits = 22;
  {$else}
  DiagRegistryBits = 17;
  {$endif FPCX64MM_DIAGNOSTIC_LARGE}
  DiagRegistrySize = 1 shl DiagRegistryBits;
  DiagRegistryMask = DiagRegistrySize - 1;
  DiagSegmentBits = 6;
  DiagSegmentCount = 1 shl DiagSegmentBits;
  DiagSlotBits = DiagRegistryBits - DiagSegmentBits;
  DiagSlotMask = (1 shl DiagSlotBits) - 1;
  DiagBusySpinLimit = 10000000;
  DiagContextLength = 31;
  DiagNewFill = $A5;
  DiagFreeFill = $DE;
  DiagLive = 1;
  DiagFreed = 2;
  DiagBusy = 3;
  DiagSmall = 1;
  DiagMedium = 2;
  DiagLarge = 3;

type
  TDiagContext = array[0..DiagContextLength] of AnsiChar;
  TDiagRecord = packed record
    P: pointer;
    Requested: PtrUInt;
    Actual: PtrUInt;
    Header: PtrUInt;
    Owner: PtrUInt;
    Sequence: QWord;
    Context: TDiagContext;
    State: byte;
    Kind: byte;
  end;
  TDiagSegmentLock = record
    Locked: longint;
    Pad: array[0..59] of byte; // one cache line per lock
  end;

var
  DiagRegistry: array[0..DiagRegistrySize - 1] of TDiagRecord;
  DiagSegLocks: array[0..DiagSegmentCount - 1] of TDiagSegmentLock;
  DiagFailLock: longint;
  DiagSequence: int64;
  DiagFreedPoisoned: int64;
  DiagFailed: boolean;
  DiagFailureReported: boolean;
  DiagFailureOperation: TDiagContext;
  DiagFailureContext: TDiagContext;
  DiagFailureAllocationContext: TDiagContext;
  DiagFailurePointer: pointer;
  DiagFailureSequence: QWord;
  DiagFailureState: byte;

threadvar
  DiagThreadContext: TDiagContext;

procedure DiagRaiseIfFailed; forward;

{$ifdef MSWINDOWS}
procedure DiagOsExit(Code: cardinal);
  stdcall; external kernel32 name 'ExitProcess';
{$else}
procedure DiagOsExit(Code: longint);
begin
  {$ifdef LINUX}
  // FpExit is the exit(2) syscall which on NPTL terminates only the calling
  // thread - the process would then finish with the status of whichever
  // thread exits last; exit_group(2) ends the whole process with our status
  Do_SysCall(syscall_nr_exit_group, TSysParam(Code));
  {$else}
  FpExit(Code);
  {$endif LINUX}
end;
{$endif MSWINDOWS}

procedure DiagPause; nostackframe; assembler;
asm
        pause
end;

procedure DiagLockAcquire(var Lock: longint);
begin
  while InterlockedExchange(Lock, 1) <> 0 do
    DiagPause;
end;

procedure DiagLockRelease(var Lock: longint); inline;
begin
  Lock := 0; // a plain store is a release on x86-64
end;

// checked on the way out of every Debug* entry point: a violation latched by
// any thread stops the process on the very next allocator call instead of
// running corrupted until the next explicit VerifyHeap
procedure DiagCheckFailed; inline;
begin
  if DiagFailed then
    DiagRaiseIfFailed;
end;

procedure DiagCopyContext(var Dest: TDiagContext; Source: PAnsiChar);
var
  i: integer;
begin
  i := 0;
  if Source <> nil then
    while (i < high(Dest)) and (Source[i] <> #0) do
    begin
      Dest[i] := Source[i];
      inc(i);
    end;
  Dest[i] := #0;
  inc(i);
  while i <= high(Dest) do
  begin
    Dest[i] := #0;
    inc(i);
  end;
end;

procedure Fpcx64mmDebugSetContext(Context: PAnsiChar);
begin
  DiagCopyContext(DiagThreadContext, Context);
end;

function DiagHash(P: pointer): PtrUInt; inline;
var
  n: PtrUInt;
begin
  n := PtrUInt(P) shr 4;
  n := n xor (n shr 17);
  result := n and DiagRegistryMask;
end;

function DiagSegmentOf(P: pointer): PtrUInt; inline;
begin
  result := DiagHash(P) shr DiagSlotBits;
end;

function DiagFind(P: pointer; out Slot: PtrUInt): boolean;
// the caller must hold the segment lock of P; probing never leaves the segment
var
  base, start, i, firstfreed: PtrUInt;
begin
  i := DiagHash(P);
  base := i and not PtrUInt(DiagSlotMask);
  start := i and DiagSlotMask;
  i := start;
  firstfreed := PtrUInt(-1);
  repeat
    Slot := base + i;
    if DiagRegistry[Slot].P = P then
      exit(true);
    if DiagRegistry[Slot].P = nil then
    begin
      if firstfreed <> PtrUInt(-1) then
        Slot := firstfreed;
      exit(false);
    end;
    if (DiagRegistry[Slot].State = DiagFreed) and (firstfreed = PtrUInt(-1)) then
      firstfreed := Slot;
    i := (i + 1) and DiagSlotMask;
  until i = start;
  Slot := firstfreed;
  result := false;
end;

procedure DiagLatchLocked(Operation: PAnsiChar; P: pointer;
  const RecordInfo: TDiagRecord; HasRecord: boolean);
begin
  if DiagFailed then
    exit;
  DiagFailed := true;
  DiagCopyContext(DiagFailureOperation, Operation);
  DiagFailureContext := DiagThreadContext;
  DiagFailurePointer := P;
  if HasRecord then
  begin
    DiagFailureSequence := RecordInfo.Sequence;
    DiagFailureState := RecordInfo.State;
    DiagFailureAllocationContext := RecordInfo.Context;
  end
  else
  begin
    DiagFailureSequence := 0;
    DiagFailureState := 0;
    FillChar(DiagFailureAllocationContext, SizeOf(DiagFailureAllocationContext), 0);
  end;
end;

function DiagKnownMediumInfo(Info: PMediumBlockInfo): boolean;
var
  i: integer;
begin
  result := Info = @MediumBlockInfo;
  {$ifdef FPCMM_MS_MEDIUM}
  if not result then
    for i := 1 to high(MediumBlockInfoExtra) do
      if Info = @MediumBlockInfoExtra[i] then
        exit(true);
  {$endif FPCMM_MS_MEDIUM}
end;

function DiagKnownSmallType(BlockType: PSmallBlockType): boolean;
var
  index, classindex, offset: PtrUInt;
begin
  offset := PtrUInt(BlockType) - PtrUInt(@SmallBlockInfo.Small[0]);
  if (offset >= NumSmallInfoBlock * SmallBlockTypeSize) or
     (offset and (SmallBlockTypeSize - 1) <> 0) then
    exit(false);
  index := offset shr SmallBlockTypePO2;
  if index < NumSmallBlockTypes then
    classindex := index
  else
    classindex := (index - NumSmallBlockTypes) and (NumTinyBlockTypes - 1);
  result := BlockType^.BlockSize = SmallBlockSizes[classindex];
end;

function DiagInspect(P: pointer; out Kind: byte; out Actual, Header,
  Owner: PtrUInt): boolean;
var
  small: PSmallBlockPoolHeader;
  blocktype: PSmallBlockType;
  medium: PMediumBlockPoolHeader;
  large: PLargeBlockHeader;
begin
  result := false;
  Kind := 0;
  Actual := 0;
  Header := 0;
  Owner := 0;
  if P = nil then
    exit;
  try
    Header := PPtrUInt(PByte(P) - BlockHeaderSize)^;
    if Header and IsMediumBlockFlag <> 0 then
    begin
      if Header and IsFreeBlockFlag <> 0 then
        exit;
      Kind := DiagMedium;
      Actual := Header and DropMediumAndLargeFlagsMask;
      if Actual <= BlockHeaderSize then
        exit;
      dec(Actual, BlockHeaderSize);
      Header := Header and DropMediumAndLargeFlagsMask;
      {$ifdef FPCMM_MS_MEDIUM}
      medium := pointer(PtrUInt(P) and not MediumBlockAlignmentMask);
      Owner := PtrUInt(medium^.Reserved1);
      if not DiagKnownMediumInfo(pointer(Owner)) then
        exit;
      {$else}
      Owner := PtrUInt(@MediumBlockInfo);
      {$endif FPCMM_MS_MEDIUM}
    end
    else if Header and IsLargeBlockFlag <> 0 then
    begin
      if Header and IsFreeBlockFlag <> 0 then
        exit;
      Kind := DiagLarge;
      large := pointer(PByte(P) - LargeBlockHeaderSize);
      if (large^.PreviousLargeBlockHeader = nil) or
         (large^.NextLargeBlockHeader = nil) then
        exit;
      Actual := Header and DropMediumAndLargeFlagsMask;
      if Actual <= LargeBlockHeaderSize + BlockHeaderSize then
        exit;
      dec(Actual, LargeBlockHeaderSize + BlockHeaderSize);
      Header := Header and DropMediumAndLargeFlagsMask;
      Owner := PtrUInt(large);
    end
    else
    begin
      if Header and IsFreeBlockFlag <> 0 then
        exit;
      Header := Header and DropSmallFlagsMask;
      small := pointer(Header);
      blocktype := small^.BlockType;
      if not DiagKnownSmallType(blocktype) then
        exit;
      Kind := DiagSmall;
      Actual := blocktype^.BlockSize - BlockHeaderSize;
      Owner := PtrUInt(blocktype);
    end;
    result := Actual <> 0;
  except
    result := false;
  end;
end;

procedure DiagLatch(Operation: PAnsiChar; P: pointer;
  const RecordInfo: TDiagRecord; HasRecord: boolean);
begin
  DiagLockAcquire(DiagFailLock);
  DiagLatchLocked(Operation, P, RecordInfo, HasRecord);
  DiagLockRelease(DiagFailLock);
end;

procedure DiagLatchLarge(Operation: PAnsiChar; Failed: pointer;
  Header: PLargeBlockHeader);
var
  slot, seg: PtrUInt;
  recordinfo: TDiagRecord;
  found: boolean;
begin
  FillChar(recordinfo, SizeOf(recordinfo), 0);
  found := false;
  if Header <> @LargeBlocksCircularList then
  begin
    seg := DiagSegmentOf(PByte(Header) + LargeBlockHeaderSize);
    DiagLockAcquire(DiagSegLocks[seg].Locked);
    found := DiagFind(PByte(Header) + LargeBlockHeaderSize, slot);
    if found then
      recordinfo := DiagRegistry[slot];
    DiagLockRelease(DiagSegLocks[seg].Locked);
  end;
  DiagLatch(Operation, Failed, recordinfo, found);
end;

procedure DiagLatchPointer(Operation: PAnsiChar; Failed: pointer);
var
  slot, seg: PtrUInt;
  recordinfo: TDiagRecord;
  found: boolean;
begin
  FillChar(recordinfo, SizeOf(recordinfo), 0);
  found := false;
  if Failed <> nil then
  begin
    seg := DiagSegmentOf(Failed);
    DiagLockAcquire(DiagSegLocks[seg].Locked);
    found := DiagFind(Failed, slot);
    if found then
      recordinfo := DiagRegistry[slot];
    DiagLockRelease(DiagSegLocks[seg].Locked);
  end;
  DiagLatch(Operation, Failed, recordinfo, found);
end;

function DiagLargeNodeLinkedLocked(Header: PLargeBlockHeader): boolean;
var
  prev, next, peer: PLargeBlockHeader;
begin
  result := false;
  try
    prev := Header^.PreviousLargeBlockHeader;
    next := Header^.NextLargeBlockHeader;
    if (Header <> @LargeBlocksCircularList) and
       (Header^.BlockSizeAndFlags and IsLargeBlockFlag = 0) then
    begin
      DiagLatchLarge('large-list-header', Header, Header);
      exit;
    end;
  except
    DiagLatchLarge('large-list-header-access', Header, Header);
    exit;
  end;
  if (prev = nil) or (next = nil) then
  begin
    DiagLatchLarge('large-list-null-link', Header, Header);
    exit;
  end;
  try
    peer := prev^.NextLargeBlockHeader;
  except
    DiagLatchLarge('large-list-prev-access', prev, Header);
    exit;
  end;
  if peer <> Header then
  begin
    DiagLatchLarge('large-list-prev-link', prev, Header);
    exit;
  end;
  try
    peer := next^.PreviousLargeBlockHeader;
  except
    DiagLatchLarge('large-list-next-access', next, Header);
    exit;
  end;
  if peer <> Header then
  begin
    DiagLatchLarge('large-list-next-link', next, Header);
    exit;
  end;
  result := true;
end;

procedure DiagCountPoison; inline;
begin
  InterLockedIncrement64(DiagFreedPoisoned);
end;

function DiagMatches(P: pointer; const RecordInfo: TDiagRecord): boolean;
var
  kind: byte;
  actual, header, owner: PtrUInt;
begin
  result := DiagInspect(P, kind, actual, header, owner) and
    (kind = RecordInfo.Kind) and (actual = RecordInfo.Actual) and
    (header = RecordInfo.Header) and (owner = RecordInfo.Owner) and
    (actual >= RecordInfo.Requested);
end;

procedure DiagReportMismatch(P: pointer; const RecordInfo: TDiagRecord);
var
  kind: byte;
  actual, header, owner: PtrUInt;
begin
  if DiagInspect(P, kind, actual, header, owner) then
    writeln('FPCX64MM_DIAGNOSTIC header expected-actual=', RecordInfo.Actual,
      '-', actual, ' expected-header=', RecordInfo.Header,
      ' actual-header=', header, ' expected-owner=', RecordInfo.Owner,
      ' actual-owner=', owner, ' expected-kind=', RecordInfo.Kind,
      ' actual-kind=', kind)
  else
    writeln('FPCX64MM_DIAGNOSTIC header unreadable pointer=', PtrUInt(P));
end;

procedure DiagRestoreLive(Slot: PtrUInt);
var
  seg: PtrUInt;
begin
  seg := Slot shr DiagSlotBits;
  DiagLockAcquire(DiagSegLocks[seg].Locked);
  if DiagRegistry[Slot].State = DiagBusy then
    DiagRegistry[Slot].State := DiagLive;
  DiagLockRelease(DiagSegLocks[seg].Locked);
end;

procedure DiagRestoreFreedToLive(Slot: PtrUInt);
var
  seg: PtrUInt;
begin
  seg := Slot shr DiagSlotBits;
  DiagLockAcquire(DiagSegLocks[seg].Locked);
  if DiagRegistry[Slot].State = DiagFreed then
    DiagRegistry[Slot].State := DiagLive;
  DiagLockRelease(DiagSegLocks[seg].Locked);
end;

procedure DiagRelease(Slot: PtrUInt);
var
  seg: PtrUInt;
begin
  seg := Slot shr DiagSlotBits;
  DiagLockAcquire(DiagSegLocks[seg].Locked);
  if DiagRegistry[Slot].State = DiagBusy then
    DiagRegistry[Slot].State := DiagFreed;
  DiagLockRelease(DiagSegLocks[seg].Locked);
end;

function DiagPrepare(P: pointer; Operation: PAnsiChar; out Slot: PtrUInt;
  out RecordInfo: TDiagRecord): boolean;
var
  found: boolean;
  seg: PtrUInt;
begin
  FillChar(RecordInfo, SizeOf(RecordInfo), 0);
  seg := DiagSegmentOf(P);
  DiagLockAcquire(DiagSegLocks[seg].Locked);
  found := DiagFind(P, Slot);
  if found then
    RecordInfo := DiagRegistry[Slot];
  if found and (RecordInfo.State = DiagLive) then
    DiagRegistry[Slot].State := DiagBusy;
  DiagLockRelease(DiagSegLocks[seg].Locked);
  if (not found) or (RecordInfo.State <> DiagLive) then
  begin
    DiagLatch(Operation, P, RecordInfo, found);
    exit(false);
  end;
  if DiagMatches(P, RecordInfo) then
    exit(true);
  DiagRestoreLive(Slot);
  DiagLatch(Operation, P, RecordInfo, true);
  DiagReportMismatch(P, RecordInfo);
  result := false;
end;

function DiagPrepareRelease(P: pointer; Operation: PAnsiChar;
  out Slot: PtrUInt; out RecordInfo: TDiagRecord): boolean;
var
  found: boolean;
  seg: PtrUInt;
begin
  FillChar(RecordInfo, SizeOf(RecordInfo), 0);
  seg := DiagSegmentOf(P);
  DiagLockAcquire(DiagSegLocks[seg].Locked);
  found := DiagFind(P, Slot);
  if found then
    RecordInfo := DiagRegistry[Slot];
  if found and (RecordInfo.State = DiagLive) then
    DiagRegistry[Slot].State := DiagFreed;
  DiagLockRelease(DiagSegLocks[seg].Locked);
  if (not found) or (RecordInfo.State <> DiagLive) then
  begin
    DiagLatch(Operation, P, RecordInfo, found);
    exit(false);
  end;
  if DiagMatches(P, RecordInfo) then
    exit(true);
  DiagRestoreFreedToLive(Slot);
  DiagLatch(Operation, P, RecordInfo, true);
  DiagReportMismatch(P, RecordInfo);
  result := false;
end;

procedure DiagRegister(P: pointer; Requested: PtrUInt; FillNew: boolean);
var
  slot, seg: PtrUInt;
  kind: byte;
  actual, header, owner: PtrUInt;
  recordinfo, busyrecord: TDiagRecord;
  found: boolean;
  spins: cardinal;
begin
  if P = nil then
    exit;
  if (not DiagInspect(P, kind, actual, header, owner)) or (actual < Requested) then
  begin
    FillChar(recordinfo, SizeOf(recordinfo), 0);
    DiagLatch('allocation-header', P, recordinfo, false);
    exit;
  end;
  seg := DiagSegmentOf(P);
  spins := 0;
  repeat
    DiagLockAcquire(DiagSegLocks[seg].Locked);
    found := DiagFind(P, slot);
    if found and (DiagRegistry[slot].State = DiagBusy) then
    begin
      busyrecord := DiagRegistry[slot];
      DiagLockRelease(DiagSegLocks[seg].Locked);
      inc(spins);
      if spins > DiagBusySpinLimit then
      begin
        DiagLatch('allocation-registry-busy', P, busyrecord, true);
        exit;
      end;
      if spins and 1023 = 0 then
        ReleaseCoreSafe
      else
        DiagPause;
      continue;
    end;
    if found and (DiagRegistry[slot].State = DiagLive) then
    begin
      busyrecord := DiagRegistry[slot];
      DiagLockRelease(DiagSegLocks[seg].Locked);
      DiagLatch('allocation-live', P, busyrecord, true);
      exit;
    end;
    if (not found) and (slot = PtrUInt(-1)) then
    begin
      DiagLockRelease(DiagSegLocks[seg].Locked);
      FillChar(recordinfo, SizeOf(recordinfo), 0);
      DiagLatch('registry-full', P, recordinfo, false);
      exit;
    end;
    recordinfo.P := P;
    recordinfo.Requested := Requested;
    recordinfo.Actual := actual;
    recordinfo.Header := header;
    recordinfo.Owner := owner;
    recordinfo.Sequence := QWord(InterLockedIncrement64(DiagSequence));
    recordinfo.Context := DiagThreadContext;
    recordinfo.State := DiagLive;
    recordinfo.Kind := kind;
    DiagRegistry[slot] := recordinfo;
    DiagLockRelease(DiagSegLocks[seg].Locked);
    break;
  until false;
  if FillNew then
    FillChar(P^, actual, DiagNewFill);
end;

function DebugGetMem(Size: PtrUInt): pointer;
begin
  result := _GetMem(Size);
  DiagRegister(result, Size, true);
  DiagCheckFailed;
end;

function DebugAllocMem(Size: PtrUInt): pointer;
begin
  result := _AllocMem(Size);
  // AllocMem retains its public zero-fill contract.
  DiagRegister(result, Size, false);
  DiagCheckFailed;
end;

function DebugFreeMem(P: pointer): PtrUInt;
var
  slot: PtrUInt;
  recordinfo: TDiagRecord;
begin
  if P = nil then
    exit(_FreeMem(nil));
  if not DiagPrepareRelease(P, 'free-owner', slot, recordinfo) then
  begin
    DiagCheckFailed;
    exit(0);
  end;
  FillChar(P^, recordinfo.Actual, DiagFreeFill);
  DiagCountPoison;
  result := _FreeMem(P);
  DiagCheckFailed;
end;

function DebugFreeMemSize(P: pointer; Size: PtrUInt): PtrInt;
var
  slot: PtrUInt;
  recordinfo: TDiagRecord;
begin
  if P = nil then
    exit(_FreeMemSize(nil, Size));
  if not DiagPrepareRelease(P, 'freememsize-owner', slot, recordinfo) then
  begin
    DiagCheckFailed;
    exit(0);
  end;
  if Size > recordinfo.Actual then
  begin
    // freeing with a size above the block capacity means the caller lost
    // track of what it allocated, even though the block itself is intact
    DiagRestoreFreedToLive(slot);
    DiagLatch('freememsize-size', P, recordinfo, true);
    DiagCheckFailed;
    exit(0);
  end;
  FillChar(P^, recordinfo.Actual, DiagFreeFill);
  DiagCountPoison;
  result := _FreeMemSize(P, Size);
  DiagCheckFailed;
end;

function DebugMemSize(P: pointer): PtrUInt;
var
  slot: PtrUInt;
  recordinfo: TDiagRecord;
begin
  if P = nil then
    exit(0);
  if not DiagPrepare(P, 'memsize-owner', slot, recordinfo) then
  begin
    DiagCheckFailed;
    exit(0);
  end;
  result := _MemSize(P);
  DiagRestoreLive(slot);
  DiagCheckFailed;
end;

function DebugReallocMem(var P: pointer; Size: PtrUInt): pointer;
var
  old: pointer;
  slot, seg: PtrUInt;
  recordinfo: TDiagRecord;
  kind: byte;
  actual, header, owner: PtrUInt;
begin
  old := P;
  if old = nil then
  begin
    result := _ReallocMem(P, Size);
    if Size <> 0 then
      DiagRegister(P, Size, true);
    DiagCheckFailed;
    exit;
  end;
  if not DiagPrepare(old, 'realloc-owner', slot, recordinfo) then
  begin
    DiagCheckFailed;
    exit(P);
  end;
  if Size = 0 then
  begin
    DiagRestoreLive(slot);
    if not DiagPrepareRelease(old, 'realloc-free-owner', slot, recordinfo) then
    begin
      DiagCheckFailed;
      exit(P);
    end;
    FillChar(old^, recordinfo.Actual, DiagFreeFill);
    DiagCountPoison;
    result := _ReallocMem(P, Size);
    DiagCheckFailed;
    exit;
  end;
  result := _ReallocMem(P, Size);
  if result = nil then
  begin
    DiagRestoreLive(slot);
    DiagCheckFailed;
    exit;
  end;
  if not DiagInspect(P, kind, actual, header, owner) or (actual < Size) then
  begin
    DiagLatch('realloc-result-header', P, recordinfo, true);
    DiagRelease(slot);
    DiagCheckFailed;
    exit;
  end;
  if P = old then
  begin
    if actual > recordinfo.Actual then
      FillChar(PByte(P)[recordinfo.Actual], actual - recordinfo.Actual, DiagNewFill);
    seg := slot shr DiagSlotBits;
    DiagLockAcquire(DiagSegLocks[seg].Locked);
    DiagRegistry[slot].Requested := Size;
    DiagRegistry[slot].Actual := actual;
    DiagRegistry[slot].Header := header;
    DiagRegistry[slot].Owner := owner;
    DiagRegistry[slot].Kind := kind;
    DiagRegistry[slot].State := DiagLive;
    DiagLockRelease(DiagSegLocks[seg].Locked);
  end
  else
  begin
    // The source must remain intact until _ReallocMem copies it, so a moved
    // realloc cannot be poisoned without violating the realloc contract.
    if actual > recordinfo.Actual then
      FillChar(PByte(P)[recordinfo.Actual], actual - recordinfo.Actual,
        DiagNewFill);
    DiagRelease(slot);
    DiagRegister(P, Size, false);
  end;
  DiagCheckFailed;
end;

procedure DiagVerifyLargeList(out Count: PtrUInt);
var
  current, previous: PLargeBlockHeader;
  slot, seg: PtrUInt;
  payload: pointer;
  ok: boolean;
  recordinfo: TDiagRecord;
begin
  Count := 0;
  LockLargeBlocks;
  try
    try
      previous := @LargeBlocksCircularList;
      current := LargeBlocksCircularList.NextLargeBlockHeader;
      while current <> @LargeBlocksCircularList do
      begin
        if (current = nil) or
           (current^.PreviousLargeBlockHeader <> previous) or
           (current^.NextLargeBlockHeader = nil) or
           (current^.BlockSizeAndFlags and IsLargeBlockFlag = 0) then
        begin
          FillChar(recordinfo, SizeOf(recordinfo), 0);
          DiagLatch('large-list-link', current, recordinfo, false);
          exit;
        end;
        payload := PByte(current) + LargeBlockHeaderSize;
        seg := DiagSegmentOf(payload);
        DiagLockAcquire(DiagSegLocks[seg].Locked);
        ok := DiagFind(payload, slot) and
              (DiagRegistry[slot].State = DiagLive) and
              (DiagRegistry[slot].Kind = DiagLarge);
        DiagLockRelease(DiagSegLocks[seg].Locked);
        if not ok then
        begin
          FillChar(recordinfo, SizeOf(recordinfo), 0);
          DiagLatch('large-list-owner', current, recordinfo, false);
          exit;
        end;
        inc(Count);
        if Count > DiagRegistrySize then
        begin
          FillChar(recordinfo, SizeOf(recordinfo), 0);
          DiagLatch('large-list-cycle', current, recordinfo, false);
          exit;
        end;
        previous := current;
        current := current^.NextLargeBlockHeader;
      end;
      if LargeBlocksCircularList.PreviousLargeBlockHeader <> previous then
      begin
        FillChar(recordinfo, SizeOf(recordinfo), 0);
        DiagLatch('large-list-tail', previous, recordinfo, false);
      end;
    except
      FillChar(recordinfo, SizeOf(recordinfo), 0);
      DiagLatch('large-list-access', current, recordinfo, false);
    end;
  finally
    LargeBlocksLocked := false;
  end;
end;

procedure DiagRaiseIfFailed;
var
  operation, context, allocationcontext: TDiagContext;
  p: pointer;
  sequence: QWord;
  state: byte;
  failed, report: boolean;
begin
  p := nil;
  sequence := 0;
  state := 0;
  DiagLockAcquire(DiagFailLock);
  failed := DiagFailed;
  report := failed and not DiagFailureReported;
  if report then
    DiagFailureReported := true;
  if failed then
  begin
    operation := DiagFailureOperation;
    context := DiagFailureContext;
    allocationcontext := DiagFailureAllocationContext;
    p := DiagFailurePointer;
    sequence := DiagFailureSequence;
    state := DiagFailureState;
  end;
  DiagLockRelease(DiagFailLock);
  if report then
  begin
    writeln('FPCX64MM_DIAGNOSTIC first-violation operation=',
      PAnsiChar(@operation[0]), ' pointer=', PtrUInt(p),
      ' allocation=', sequence, ' state=', state,
      ' context=', PAnsiChar(@context[0]),
      ' allocated-context=', PAnsiChar(@allocationcontext[0]));
  end;
  if failed then
  begin
    // Only the elected reporter may terminate the process. Otherwise another
    // worker could call exit_group after DiagFailureReported was claimed but
    // before the first-violation line above was written and flushed.
    if not report then
      repeat
        DiagPause;
      until false;
    // exit straight through the OS: the heap is compromised, so neither the
    // remaining finalizations may run on it, nor may Halt() be trusted - a
    // Halt() from a worker thread loses the exit status on Linux
    Flush(Output);
    DiagOsExit(218);
  end;
end;

procedure DiagVerifySmallLastFree(out Count: PtrUInt);
var
  blocktype: PSmallBlockType;
  pool: PSmallBlockPoolHeader;
  node, next, head: PPointer;
  i, expected, traversed, blocksize, poolsize, first, finish: PtrUInt;
begin
  Count := 0;
  blocktype := @SmallBlockInfo;
  for i := 0 to high(SmallBlockInfo.SmallLastFree) do
  begin
    expected := blocktype^.LastFreeCount;
    head := SmallBlockInfo.SmallLastFree[i];
    if blocktype^.LastFreeLocked then
    begin
      DiagLatchPointer('small-last-free-lock', head);
      DiagRaiseIfFailed;
    end;
    node := head;
    traversed := 0;
    while node <> nil do
    begin
      if traversed >= expected then
      begin
        DiagLatchPointer('small-last-free-count', node);
        DiagRaiseIfFailed;
      end;
      try
        next := node^;
        if PPtrUInt(PByte(node) - BlockHeaderSize)^ and
             ExtractSmallFlagsMask <> 0 then
        begin
          DiagLatchPointer('small-last-free-marker', node);
          DiagRaiseIfFailed;
        end;
        pool := PSmallBlockPoolHeader(
          PPtrUInt(PByte(node) - BlockHeaderSize)^);
        if pool^.BlockType <> blocktype then
        begin
          DiagLatchPointer('small-last-free-owner', node);
          DiagRaiseIfFailed;
        end;
        blocksize := blocktype^.BlockSize;
        poolsize := PPtrUInt(PByte(pool) - BlockHeaderSize)^ and
          DropMediumAndLargeFlagsMask;
        first := PtrUInt(pool) + SmallBlockPoolHeaderSize;
        finish := PtrUInt(pool) + poolsize;
        if (blocksize = 0) or
           (PtrUInt(node) < first) or
           (PtrUInt(node) > finish) or
           (finish < first) or
           (blocksize > finish - PtrUInt(node)) or
           ((PtrUInt(node) - first) mod blocksize <> 0) then
        begin
          DiagLatchPointer('small-last-free-geometry', node);
          DiagRaiseIfFailed;
        end;
      except
        DiagLatchPointer('small-last-free-access', node);
        DiagRaiseIfFailed;
      end;
      inc(traversed);
      inc(Count);
      node := next;
    end;
    if traversed <> expected then
    begin
      DiagLatchPointer('small-last-free-count', head);
      DiagRaiseIfFailed;
    end;
    inc(blocktype);
  end;
end;

procedure DiagVerifyOneMediumLastFree(Info: PMediumBlockInfo;
  var Count: PtrUInt);
var
  node, next: PPointer;
  traversed, slot, seg, actual, header, owner: PtrUInt;
  recordinfo: TDiagRecord;
  found: boolean;
  kind: byte;
begin
  node := Info^.LastFree;
  if Info^.LastFreeLocked then
  begin
    DiagLatchPointer('medium-last-free-lock', node);
    DiagRaiseIfFailed;
  end;
  traversed := 0;
  while node <> nil do
  begin
    if traversed >= DiagRegistrySize then
    begin
      DiagLatchPointer('medium-last-free-cycle', node);
      DiagRaiseIfFailed;
    end;
    try
      next := node^;
    except
      DiagLatchPointer('medium-last-free-access', node);
      DiagRaiseIfFailed;
    end;
    if not DiagInspect(node, kind, actual, header, owner) or
       (kind <> DiagMedium)
       {$ifdef FPCMM_MS_MEDIUM} or
       (owner <> PtrUInt(Info))
       {$endif FPCMM_MS_MEDIUM} then
    begin
      DiagLatchPointer('medium-last-free-owner', node);
      DiagRaiseIfFailed;
    end;
    FillChar(recordinfo, SizeOf(recordinfo), 0);
    seg := DiagSegmentOf(node);
    DiagLockAcquire(DiagSegLocks[seg].Locked);
    found := DiagFind(node, slot);
    if found then
      recordinfo := DiagRegistry[slot];
    DiagLockRelease(DiagSegLocks[seg].Locked);
    if not found or (recordinfo.State <> DiagFreed) or
       (recordinfo.Kind <> DiagMedium)
       {$ifdef FPCMM_MS_MEDIUM} or
       (recordinfo.Owner <> PtrUInt(Info))
       {$endif FPCMM_MS_MEDIUM} then
    begin
      DiagLatch('medium-last-free-registry', node, recordinfo, found);
      DiagRaiseIfFailed;
    end;
    inc(traversed);
    inc(Count);
    node := next;
  end;
end;

procedure DiagVerifyMediumLastFree(out Count: PtrUInt);
var
  i: PtrUInt;
begin
  Count := 0;
  DiagVerifyOneMediumLastFree(@MediumBlockInfo, Count);
  {$ifdef FPCMM_MS_MEDIUM}
  for i := 1 to high(MediumBlockInfoExtra) do
    DiagVerifyOneMediumLastFree(@MediumBlockInfoExtra[i], Count);
  {$endif FPCMM_MS_MEDIUM}
  {$ifdef FPCMM_SMALLNOTWITHMEDIUM}
  for i := 0 to high(SmallMediumBlockInfo) do
    DiagVerifyOneMediumLastFree(@SmallMediumBlockInfo[i], Count);
  {$endif FPCMM_SMALLNOTWITHMEDIUM}
end;

procedure Fpcx64mmDebugVerifyHeap;
var
  i, seg, live, larges, listlarges, smallpending, mediumpending: PtrUInt;
  recordinfo: TDiagRecord;
begin
  DiagRaiseIfFailed;
  live := 0;
  larges := 0;
  for i := 0 to DiagRegistrySize - 1 do
  begin
    // snapshot each record under its segment lock, validate the copy outside:
    // DiagInspect may fault on corrupted headers and the handler must never
    // run while a registry lock is held
    seg := i shr DiagSlotBits;
    DiagLockAcquire(DiagSegLocks[seg].Locked);
    recordinfo := DiagRegistry[i];
    DiagLockRelease(DiagSegLocks[seg].Locked);
    if recordinfo.State = DiagLive then
    begin
      inc(live);
      if recordinfo.Kind = DiagLarge then
        inc(larges);
      if not DiagMatches(recordinfo.P, recordinfo) then
        DiagLatch('verify-header', recordinfo.P, recordinfo, true);
    end;
  end;
  DiagVerifySmallLastFree(smallpending);
  DiagVerifyMediumLastFree(mediumpending);
  DiagVerifyLargeList(listlarges);
  if listlarges <> larges then
  begin
    FillChar(recordinfo, SizeOf(recordinfo), 0);
    DiagLatch('large-list-membership', nil, recordinfo, false);
  end;
  DiagRaiseIfFailed;
  writeln('FPCX64MM_DIAGNOSTIC verify live=', live,
    ' large=', listlarges, ' small-pending=', smallpending,
    ' medium-pending=', mediumpending,
    ' poisoned-free=', DiagFreedPoisoned,
    ' context=', PAnsiChar(@DiagThreadContext[0]));
end;

function Fpcx64mmDebugFreedPoisonCount: QWord;
begin
  result := QWord(DiagFreedPoisoned); // aligned 8-byte read is atomic on x86-64
end;

procedure DiagReportLeaks;
var
  i, seg, count, tagged, taggedshown, untaggedshown: PtrUInt;
  recordinfo: TDiagRecord;
  taggedrecords, untaggedrecords: array[0..7] of TDiagRecord;
begin
  count := 0;
  tagged := 0;
  taggedshown := 0;
  untaggedshown := 0;
  for i := 0 to DiagRegistrySize - 1 do
  begin
    seg := i shr DiagSlotBits;
    DiagLockAcquire(DiagSegLocks[seg].Locked);
    recordinfo := DiagRegistry[i];
    DiagLockRelease(DiagSegLocks[seg].Locked);
    if recordinfo.State = DiagLive then
    begin
      inc(count);
      // Keep tagged and untagged samples separate: a missing context must not
      // hide a real leak, while startup/runtime allocations remain identifiable.
      if recordinfo.Context[0] <> #0 then
      begin
        inc(tagged);
        if taggedshown <= high(taggedrecords) then
        begin
          taggedrecords[taggedshown] := recordinfo;
          inc(taggedshown);
        end;
      end
      else if untaggedshown <= high(untaggedrecords) then
      begin
        untaggedrecords[untaggedshown] := recordinfo;
        inc(untaggedshown);
      end;
    end;
  end;
  if taggedshown <> 0 then
    for i := 0 to taggedshown - 1 do
      writeln('FPCX64MM_DIAGNOSTIC tagged-live pointer=',
        PtrUInt(taggedrecords[i].P), ' requested=', taggedrecords[i].Requested,
        ' kind=', taggedrecords[i].Kind, ' allocation=',
        taggedrecords[i].Sequence, ' context=',
        PAnsiChar(@taggedrecords[i].Context[0]));
  if untaggedshown <> 0 then
    for i := 0 to untaggedshown - 1 do
      writeln('FPCX64MM_DIAGNOSTIC untagged-live pointer=',
        PtrUInt(untaggedrecords[i].P), ' requested=',
        untaggedrecords[i].Requested, ' kind=', untaggedrecords[i].Kind,
        ' allocation=', untaggedrecords[i].Sequence);
  writeln('FPCX64MM_DIAGNOSTIC live-blocks=', count, ' tagged=', tagged,
    ' untagged=', count - tagged, ' reported-tagged=', taggedshown,
    ' reported-untagged=', untaggedshown);
end;
{$endif FPCX64MM_DIAGNOSTIC_ACTIVE}


{ ********* Shared Routines }

// small/tiny blocks maintain a separated locked list of last freed items

procedure GetSmallLastFreeBlockRsi; nostackframe; assembler;
asm
        // input: rsi = TSmallBlockType
        mov     rax, rsi
        lea     r10, [rip + SmallBlockInfo]
        sub     rax, r10
        shr     eax, SmallBlockTypePO2 - 3 // 1 shl 3 = SizeOf(SmallLastFree[])
        lea     r10, [r10 + rax].TSmallBlockInfo.SmallLastFree
        // r10 = @SmallLastFree[] of this rsi = TSmallBlockType
        mov     eax, $100
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.LastFreeLocked, ah
        je      @ok
        xor     rax, rax // just try once to acquire the lock
        ret
@ok:    mov     rax, [r10]
        test    rax, rax
        jz      @done
        mov     r11, [rax] // very simple (and quick) linked list pattern
        mov     [r10], r11
        dec     dword ptr [rsi].TSmallBlockType.LastFreeCount
        test    rax, rax   // dec above did change the z flag
@done:  mov     byte ptr [rsi].TSmallBlockType.LastFreeLocked, false
        // nz = rax=to be freed or z = nothing found - modifies r10+r11
end;

{$ifdef MSWINDOWS}
procedure GetSmallLastFreeBlockRbx; nostackframe; assembler;
asm
        // Win64 _FreeMem keeps TSmallBlockType in rbx: unlike rsi, restoring
        // rbx cannot create a dependency on a caller's loop counter in esi.
        mov     rax, rbx
        lea     r10, [rip + SmallBlockInfo]
        sub     rax, r10
        shr     eax, SmallBlockTypePO2 - 3 // 1 shl 3 = SizeOf(SmallLastFree[])
        lea     r10, [r10 + rax].TSmallBlockInfo.SmallLastFree
        mov     eax, $100
  lock  cmpxchg byte ptr [rbx].TSmallBlockType.LastFreeLocked, ah
        je      @ok
        xor     rax, rax // just try once to acquire the lock
        ret
@ok:    mov     rax, [r10]
        test    rax, rax
        jz      @done
        mov     r11, [rax] // very simple (and quick) linked list pattern
        mov     [r10], r11
        dec     dword ptr [rbx].TSmallBlockType.LastFreeCount
        test    rax, rax   // dec above did change the z flag
@done:  mov     byte ptr [rbx].TSmallBlockType.LastFreeLocked, false
        // nz = rax=to be freed or z = nothing found - modifies r10+r11
end;
{$endif MSWINDOWS}

procedure LockMediumBlocks(dummy: cardinal);
  {$ifdef NOSFRAME} nostackframe; {$endif} assembler;
// on input/output: r10=TMediumBlockInfo
asm
        {$ifdef FPCMM_MEDIUMPREFETCH}
        // since we are waiting for the lock, prefetch one medium memory chunk
        mov     rcx, r10
        xor     edx, edx
        cmp     qword ptr [rcx].TMediumBlockInfo.Prefetch, rdx
        jnz     @s // there is already a prefetched memory chunk available
        {$ifdef FPCMM_CMPBEFORELOCK_SPIN}
        cmp     byte ptr [rcx].TMediumBlockInfo.PrefetchLocked, dl
        jnz     @s
        {$endif FPCMM_CMPBEFORELOCK_SPIN}
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.PrefetchLocked, ah
        jne     @s
        cmp     qword ptr [rcx].TMediumBlockInfo.Prefetch, rdx
        jnz     @s2
        push    rsi
        push    rdi
        push    r10
        push    r11
        mov     dummy, MediumBlockPoolSizeMem
        call    OsAllocMedium // mmap() is usually very fast
        pop     r11
        pop     r10
        pop     rdi
        pop     rsi
        mov     qword ptr [r10].TMediumBlockInfo.Prefetch, rax
@s2:    mov     byte ptr [r10].TMediumBlockInfo.PrefetchLocked, false
        {$endif FPCMM_MEDIUMPREFETCH}
        // spin and acquire the medium arena lock
        {$ifdef FPCMM_SLEEPTSC}
@s:     rdtsc   // tsc in edx:eax
        shl     rdx, 32
        lea     r9, [rax + rdx + SpinMediumLockTSC] // r9 = endtsc
@sp:    pause
        rdtsc
        shl     rdx, 32
        or      rax, rdx
        cmp     rax, r9
        ja      @rc // timeout
        {$else}
        // same algorithm than function DoSpin() in mormot.core.os.pas
@s:     mov     edx, SpinMediumLockCount // = pred(6 shl 5)
@sp:    mov     ecx, SpinMediumLockCount
        sub     ecx, edx
        dec     edx
        jz      @rc     // timeout
        shr     ecx, 5  // 0..6 range, each 32 times
        jz      @try
        dec     ecx
        mov     eax, 1
        shl     eax, cl // exponential backoff: 1,2,4,8,16 x pause
@p:     pause           // "rep nop" called 992 times until yield to the OS
        dec     eax
        jnz     @p
        {$endif FPCMM_SLEEPTSC}
@try:   mov     rcx, r10
        mov     eax, $100
        {$ifdef FPCMM_CMPBEFORELOCK_SPIN}
        cmp     byte ptr [r10].TMediumBlockInfo.Locked, true
        je      @sp
        {$endif FPCMM_CMPBEFORELOCK_SPIN}
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.Locked, ah
        je      @ok
        jmp     @sp
@rc:    call    ReleaseCoreSafe // Windows SwitchToThread or POSIX nanosleep(1us)
        lea     rax, [rip + HeapStatus]
        {$ifdef FPCMM_DEBUG} lock {$endif}
        inc     qword ptr [rax].TMMStatus.Medium.SleepCount
        jmp     @s
@ok:
end;

procedure InsertMediumBlockIntoBin; nostackframe; assembler;
// rcx=P edx=blocksize r10=TMediumBlockInfo - even on POSIX
asm
        mov     rax, rcx
        // Get the bin number for this block size
        sub     edx, MinimumMediumBlockSize
        shr     edx, 8
        // Validate the bin number
        sub     edx, MediumBlockBinCount - 1
        sbb     ecx, ecx
        and     edx, ecx
        add     edx, MediumBlockBinCount - 1
        mov     r9, rdx
        // Get the bin address in rcx
        shl     edx, 4
        lea     rcx, [r10 + rdx + TMediumBlockInfo.Bins]
        // Bins are LIFO, se we insert this block as the first free block in the bin
        mov     rdx, TMediumFreeBlock[rcx].NextFreeBlock
        mov     TMediumFreeBlock[rax].PreviousFreeBlock, rcx
        mov     TMediumFreeBlock[rax].NextFreeBlock, rdx
        mov     TMediumFreeBlock[rdx].PreviousFreeBlock, rax
        mov     TMediumFreeBlock[rcx].NextFreeBlock, rax
        // Was this bin empty?
        cmp     rdx, rcx
        jne     @Done
        // Get ecx=bin number, edx=group number
        mov     rcx, r9
        mov     rdx, r9
        shr     edx, 5
        // Flag this bin as not empty
        mov     eax, 1
        shl     eax, cl
        or      dword ptr [r10 + TMediumBlockInfo.BinBitmaps + rdx * 4], eax
        // Flag the group as not empty
        mov     eax, 1
        mov     ecx, edx
        shl     eax, cl
        or      [r10 + TMediumBlockInfo.BinGroupBitmap], eax
@Done:
end;

procedure RemoveMediumFreeBlock; nostackframe; assembler;
asm
        // rcx=MediumFreeBlock r10=TMediumBlockInfo - even on POSIX
        // Get the current previous and next blocks
        mov     rdx, TMediumFreeBlock[rcx].PreviousFreeBlock
        mov     rcx, TMediumFreeBlock[rcx].NextFreeBlock
        // Remove this block from the linked list
        mov     TMediumFreeBlock[rcx].PreviousFreeBlock, rdx
        mov     TMediumFreeBlock[rdx].NextFreeBlock, rcx
        // Is this bin now empty? If the previous and next free block pointers are
        // equal, they must point to the bin
        cmp     rcx, rdx
        jne     @Done
        // Get ecx=bin number, edx=group number
        lea     r8, [r10 + TMediumBlockInfo.Bins]
        sub     rcx, r8
        mov     edx, ecx
        shr     ecx, 4
        shr     edx, 9
        // Flag this bin as empty
        mov     eax, -2
        rol     eax, cl
        and     dword ptr [r10 + TMediumBlockInfo.BinBitmaps + rdx * 4], eax
        jnz     @Done
        // Flag this group as empty
        mov     eax, -2
        mov     ecx, edx
        rol     eax, cl
        and     [r10 + TMediumBlockInfo.BinGroupBitmap], eax
@Done:
end;

procedure BinMediumSequentialFeedRemainder(
  var Info: TMediumBlockInfo); nostackframe; assembler;
asm
        mov     r10, Info
        mov     eax, [Info + TMediumBlockInfo.SequentialFeedBytesLeft]
        test    eax, eax
        jz      @Done
        // Is the last fed sequentially block free?
        mov     rax, [Info + TMediumBlockInfo.LastSequentiallyFed]
        test    byte ptr [rax - BlockHeaderSize], IsFreeBlockFlag
        jnz     @LastBlockFedIsFree
        // Set the "previous block is free" flag in the last block fed
        or      qword ptr [rax - BlockHeaderSize], PreviousMediumBlockIsFreeFlag
        // Get edx=remainder size, rax=remainder start
        mov     edx, [r10 + TMediumBlockInfo.SequentialFeedBytesLeft]
        sub     rax, rdx
@BinTheRemainder:
        // Store the size of the block as well as the flags
        lea     rcx, [rdx + IsMediumBlockFlag + IsFreeBlockFlag]
        mov     [rax - BlockHeaderSize], rcx
        // Store the trailing size marker
        mov     [rax + rdx - 16], rdx
        // Bin this medium block
        cmp     edx, MinimumMediumBlockSize
        jb      @Done
        mov     rcx, rax
        jmp     InsertMediumBlockIntoBin // rcx=P edx=blocksize r10=Info
@Done:  ret
@LastBlockFedIsFree:
        // Drop the flags
        mov     rdx, DropMediumAndLargeFlagsMask
        and     rdx, [rax - BlockHeaderSize]
        // Free the last block fed
        cmp     edx, MinimumMediumBlockSize
        jb      @DontRemoveLastFed
        // Last fed block is free - remove it from its size bin
        mov     rcx, rax
        call    RemoveMediumFreeBlock // rcx = APMediumFreeBlock
        // Re-read rax and rdx
        mov     rax, [r10 + TMediumBlockInfo.LastSequentiallyFed]
        mov     rdx, DropMediumAndLargeFlagsMask
        and     rdx, [rax - BlockHeaderSize]
@DontRemoveLastFed:
        // Get the number of bytes left in ecx
        mov     ecx, [r10 + TMediumBlockInfo.SequentialFeedBytesLeft]
        // rax = remainder start, rdx = remainder size
        sub    rax, rcx
        add    edx, ecx
        jmp    @BinTheRemainder
end;

procedure LockLargeBlocks;
  {$ifdef NOSFRAME} nostackframe; {$endif} assembler;
asm
@s:     mov     eax, $100
        lea     rcx, [rip + LargeBlocksLocked]
  lock  cmpxchg byte ptr [rcx], ah
        je      @ok
        {$ifdef FPCMM_SLEEPTSC}
        rdtsc
        shl     rdx, 32
        lea     r9, [rax + rdx + SpinLargeLockTSC] // r9 = endtsc
@sp:    pause
        rdtsc
        shl     rdx, 32
        or      rax, rdx
        cmp     rax, r9
        ja      @rc // timeout
        {$else}
        mov     edx, SpinLargeLockCount
@sp:    pause
        dec     edx
        jz      @rc // timeout
        {$endif FPCMM_SLEEPTSC}
        mov     eax, $100
        {$ifdef FPCMM_CMPBEFORELOCK_SPIN}
        cmp     byte ptr [rcx], true
        je      @sp
        {$endif FPCMM_CMPBEFORELOCK_SPIN}
  lock  cmpxchg byte ptr [rcx], ah
        je      @ok
        jmp     @sp
@rc:    call    ReleaseCoreSafe
        lea     rax, [rip + HeapStatus]
        {$ifdef FPCMM_DEBUG} lock {$endif}
        inc     qword ptr [rax].TMMStatus.Large.SleepCount
        jmp     @s
@ok:    // reset the stack frame before ret
end;

{$ifdef FPCMM_MEDIUMPREFETCH}

// munmap() takes more time than mmap() so it makes sense to cache one chunk
function TrySaveMediumPrefetch(var Info: TMediumBlockInfo;
  MediumBlock: PMediumBlockPoolHeader): pointer; nostackframe; assembler;
asm
        {$ifndef MSWINDOWS}
        mov     rcx, Info
        mov     rdx, MediumBlock
        {$endif MSWINDOWS}
        xor     eax, eax
        cmp     qword ptr [rcx].TMediumBlockInfo.Prefetch, rax
        jnz     @ko // there is already a prefetched memory chunk available
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.PrefetchLocked, ah
        jne     @ko
        cmp     qword ptr [rcx].TMediumBlockInfo.Prefetch, 0
        jnz     @ko2
        // store this Medium block for the next TryAllocMediumPrefetch()
        mov     [rcx].TMediumBlockInfo.Prefetch, rdx
        xor     edx, edx // return nil if was saved
@ko2:   mov     byte ptr [rcx].TMediumBlockInfo.PrefetchLocked, false
@ko:    mov     rax, rdx
end;

function TryAllocMediumPrefetch(var Info: TMediumBlockInfo): pointer;
  nostackframe; assembler;
asm
        {$ifndef MSWINDOWS}
        mov     rcx, Info
        {$endif MSWINDOWS}
        xor     eax, eax
        cmp     qword ptr [rcx].TMediumBlockInfo.Prefetch, rax
        jz      @ok        // is there a prefetched memory chunk available?
        xor     edx, edx
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.PrefetchLocked, ah
        jne     @busy
        // just get the memory chunk - no need to call mmap/VirtualAlloc
        mov     rax, [rcx].TMediumBlockInfo.Prefetch
        mov     [rcx].TMediumBlockInfo.Prefetch, rdx
        mov     [rcx].TMediumBlockInfo.PrefetchLocked, dl
        ret
@busy:  xor     eax, eax
@ok:
end;

{$endif FPCMM_MEDIUMPREFETCH}

procedure FreeMedium(ptr: PMediumBlockPoolHeader; var info: TMediumBlockInfo);
begin
  {$ifdef FPCMM_MEDIUMPREFETCH}
  ptr := TrySaveMediumPrefetch(info, ptr);
  if ptr <> nil then
  {$endif FPCMM_MEDIUMPREFETCH}
    OsFreeMedium(ptr, MediumBlockPoolSizeMem);
  NotifyMediumLargeFree(HeapStatus.Medium, MediumBlockPoolSizeMem);
end;

function AllocNewSequentialFeedMediumPool(BlockSize: cardinal;
  var Info: TMediumBlockInfo): pointer;
var
  old: PMediumBlockPoolHeader;
  new: pointer;
begin
  BinMediumSequentialFeedRemainder(Info);
  {$ifdef FPCMM_MEDIUMPREFETCH}
  new := TryAllocMediumPrefetch(Info);
  if new = nil then
  {$endif FPCMM_MEDIUMPREFETCH}
    new := OsAllocMedium(MediumBlockPoolSizeMem);
  if new <> nil then
  begin
    {$ifdef FPCMM_MS_MEDIUM}
    // Written once before the pool becomes reachable from any shared list.
    PMediumBlockPoolHeader(new).Reserved1 := PtrUInt(@Info);
    {$endif FPCMM_MS_MEDIUM}
    old := Info.PoolsCircularList.NextMediumBlockPoolHeader;
    PMediumBlockPoolHeader(new).PreviousMediumBlockPoolHeader := @Info.PoolsCircularList;
    Info.PoolsCircularList.NextMediumBlockPoolHeader := new;
    PMediumBlockPoolHeader(new).NextMediumBlockPoolHeader := old;
    old.PreviousMediumBlockPoolHeader := new;
    PPtrUInt(PByte(new) + MediumBlockPoolSize - BlockHeaderSize)^ := IsMediumBlockFlag;
    Info.SequentialFeedBytesLeft :=
      (MediumBlockPoolSize - MediumBlockPoolHeaderSize) - BlockSize;
    result := pointer(PByte(new) + MediumBlockPoolSize - BlockSize);
    Info.LastSequentiallyFed := result;
    PPtrUInt(PByte(result) - BlockHeaderSize)^ := BlockSize or IsMediumBlockFlag;
    NotifyArenaAlloc(HeapStatus.Medium, MediumBlockPoolSizeMem);
  end
  else
  begin
    Info.SequentialFeedBytesLeft := 0; // system is unstable for sure
    result := nil;
  end;
end;

{$ifdef MSWINDOWS} // implemented here with knowledge of PLargeBlockHeader
procedure OsFreeLarge(ptr: pointer; Size: PtrInt);
var
  nfo: TMemInfo;
begin
  if (PLargeBlockHeader(ptr)^.BlockSizeAndFlags and LargeBlockIsSegmented) = 0 then
    // there was a regular single VirtualAlloc() call
    VirtualFree(ptr, 0, MEM_RELEASE)
  else
    // OsRemapLarge() requires several VirtualFree() calls
    repeat
      FillChar(nfo, SizeOf(nfo), 0);
      if (VirtualQuery(ptr, @nfo, SizeOf(nfo)) <> SizeOf(nfo)) or
         not VirtualFree(ptr, 0, MEM_RELEASE) then
        exit;
      inc(PByte(ptr), nfo.RegionSize);
      dec(Size, PtrInt(nfo.RegionSize));
    until Size <= 0;
end;
{$endif MSWINDOWS}

function ComputeLargeBlockSize(size: PtrUInt): PtrUInt; inline;
begin
  inc(size, LargeBlockHeaderSize + BlockHeaderSize);
  // aligned_size := ((size + align - 1) AND (NOT (align - 1)))
  {$ifdef FPCMM_LARGEBIGALIGN}
  // on Linux, mremap() on PMD_SIZE=2MB aligned data make a huge speedup
  if size >= LargeBlockGranularity2Size then // trigger if size>=4MB
    result := (size + LargeBlockGranularity2And) and not LargeBlockGranularity2And
  else
  {$endif FPCMM_LARGEBIGALIGN}
    // use default 64KB granularity for large blocks up to 4MB
    result := (size + LargeBlockGranularityAnd) and not LargeBlockGranularityAnd;
end;

function AllocateLargeBlockFrom(existing: pointer;
  oldblocksize, newblocksize: PtrUInt): pointer;
var
  new, old: PLargeBlockHeader;
begin
  if existing = nil then
    new := OsAllocLarge(newblocksize)
  else
    new := OsRemapLarge(existing, oldblocksize, newblocksize);
    // note: on Windows, newblocksize may now include LargeBlockIsSegmented flag
  if new <> nil then
  begin
    NotifyArenaAlloc(HeapStatus.Large, DropMediumAndLargeFlagsMask and newblocksize);
    if existing <> nil then
      NotifyMediumLargeFree(HeapStatus.Large, oldblocksize);
    new.BlockSizeAndFlags := newblocksize or IsLargeBlockFlag;
    LockLargeBlocks;
    {$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
    if not DiagLargeNodeLinkedLocked(@LargeBlocksCircularList) then
    begin
      LargeBlocksLocked := false;
      DiagRaiseIfFailed;
      result := nil;
      exit;
    end;
    {$endif FPCX64MM_DIAGNOSTIC_ACTIVE}
    old := LargeBlocksCircularList.NextLargeBlockHeader;
    new.PreviousLargeBlockHeader := @LargeBlocksCircularList;
    LargeBlocksCircularList.NextLargeBlockHeader := new;
    new.NextLargeBlockHeader := old;
    old.PreviousLargeBlockHeader := new;
    {$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
    if not DiagLargeNodeLinkedLocked(new) then
    begin
      LargeBlocksLocked := false;
      DiagRaiseIfFailed;
      result := nil;
      exit;
    end;
    {$endif FPCX64MM_DIAGNOSTIC_ACTIVE}
    LargeBlocksLocked := false;
    inc(new);
  end;
  result := new;
end;

function AllocateLargeBlock(size: PtrUInt): pointer;
begin
  result := AllocateLargeBlockFrom(nil, 0, ComputeLargeBlockSize(size));
end;

procedure FreeLarge(ptr: PLargeBlockHeader; size: PtrUInt);
begin
  NotifyMediumLargeFree(HeapStatus.Large, size);
  OsFreeLarge(ptr, size);
end;

function FreeLargeBlock(p: pointer): PtrInt;
var
  header, prev, next: PLargeBlockHeader;
begin
  header := pointer(PByte(p) - LargeBlockHeaderSize);
  if header.BlockSizeAndFlags and IsFreeBlockFlag <> 0 then
  begin
    // try to release the same pointer twice
    result := 0;
    exit;
  end;
  LockLargeBlocks;
  {$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
  if not DiagLargeNodeLinkedLocked(header) then
  begin
    LargeBlocksLocked := false;
    DiagRaiseIfFailed;
    result := 0;
    exit;
  end;
  {$endif FPCX64MM_DIAGNOSTIC_ACTIVE}
  prev := header.PreviousLargeBlockHeader;
  next := header.NextLargeBlockHeader;
  next.PreviousLargeBlockHeader := prev;
  prev.NextLargeBlockHeader := next;
  LargeBlocksLocked := false;
  result := DropMediumAndLargeFlagsMask and header.BlockSizeAndFlags;
  FreeLarge(header, result);
end; // returns the size for _FreeMem()

function ReallocateLargeBlock(p: pointer; size: PtrUInt): pointer;
var
  oldavail, minup, new, old: PtrUInt;
  prev, next, header: PLargeBlockHeader;
begin
  header := pointer(PByte(p) - LargeBlockHeaderSize);
  oldavail := (DropMediumAndLargeFlagsMask and header^.BlockSizeAndFlags) -
              (LargeBlockHeaderSize + BlockHeaderSize);
  new := size;
  if size > oldavail then
  begin
    // size-up with 1/8 or 1/4 overhead for any future growing realloc
    if oldavail > 128 shl 20 then
      minup := oldavail + oldavail shr 3
    else
      minup := oldavail + oldavail shr 2;
    if size < minup then
      new := minup;
  end
  else
  begin
    result := p;
    oldavail := oldavail shr 1;
    if size >= oldavail then
      // small size-up within current buffer -> no reallocate
      exit
    else
      // size-down and move just the trailing data
      oldavail := size;
  end;
  if new < MaximumMediumBlockSize then
  begin
    // size was reduced to a small/medium block: use GetMem/Move/FreeMem
    result := _GetMem(new);
    if result <> nil then
      Move(p^, result^, oldavail); // RTL non-volatile asm or our AVX MoveFast()
    _FreeMem(p);
  end
  else
  begin
    old := DropMediumAndLargeFlagsMask and header^.BlockSizeAndFlags;
    size := ComputeLargeBlockSize(new);
    if size = old then
      // no need to realloc anything (paranoid check: should be handled above)
      result := p
    else
    begin
      // remove previous large block from current chain list
      LockLargeBlocks;
      {$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
      if not DiagLargeNodeLinkedLocked(header) then
      begin
        LargeBlocksLocked := false;
        DiagRaiseIfFailed;
        result := nil;
        exit;
      end;
      {$endif FPCX64MM_DIAGNOSTIC_ACTIVE}
      prev := header^.PreviousLargeBlockHeader;
      next := header^.NextLargeBlockHeader;
      next.PreviousLargeBlockHeader := prev;
      prev.NextLargeBlockHeader := next;
      LargeBlocksLocked := false;
      // on Linux, call Kernel mremap() and its TLB magic
      // on Windows, try to reserve the memory block just after the existing
      // otherwise, use Alloc/Move/Free pattern, with asm/AVX move
      result := AllocateLargeBlockFrom(header, old, size);
    end;
  end;
end;


{ ********* Main Memory Manager Functions }

function _GetMem(size: PtrUInt): pointer;
  {$ifdef NOSFRAME} nostackframe; {$endif} assembler;
asm     // size = rcx on Windows, = rdi on SystemV; use rsi = TSmallBlockType
        {$ifdef MSWINDOWS}
        push    rsi
        push    rdi
        {$endif MSWINDOWS}
        // Since most allocations are for small blocks, determine small block type
        lea     rsi, [rip + SmallBlockInfo]
        {$ifndef FPCMM_MS_LINUX_FASTGET}
@VoidSizeToSomething:
        {$endif FPCMM_MS_LINUX_FASTGET}
        lea     rdx, [size + BlockHeaderSize - 1]
        shr     rdx, 4 // div SmallBlockGranularity
        // Is it a tiny/small block?
        cmp     size, (MaximumSmallBlockSize - BlockHeaderSize)
        ja      @NotTinySmallBlock
        {$ifndef FPCMM_MS_LINUX_FASTGET}
        test    size, size
        jz      @VoidSize
        {$endif FPCMM_MS_LINUX_FASTGET}
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, qword ptr [rsi].TSmallBlockInfo.IsMultiThreadPtr
        {$endif FPCMM_ASSUMEMULTITHREAD}
        // Get the tiny/small TSmallBlockType[] offset in rcx
        movzx   ecx, byte ptr [rsi + rdx].TSmallBlockInfo.GetmemLookup
        mov     r8, rsi
        shl     ecx, SmallBlockTypePO2
        // ---------- Acquire block type lock ----------
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        cmp     byte ptr [rax], false
        je      @GotLockOnSmallBlock // no lock if IsMultiThread=false
        {$endif FPCMM_ASSUMEMULTITHREAD}
        // Can use one of the several arenas reserved for tiny blocks?
        {$ifndef FPCMM_MS_LINUX_FASTGET}
        cmp     ecx, SizeOf(TTinyBlockTypes)
        jae     @NotTinyBlockType
        {$endif FPCMM_MS_LINUX_FASTGET}
        // ---------- TINY (size<=128/256) block lock ----------
@LockTinyBlockTypeLoop:
        {$ifdef FPCMM_TINYPERTHREAD}
        lea     rsi, [r8 + rcx]
        {$ifdef LINUX}
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, qword ptr [r8].TSmallBlockInfo.IsMultiThreadPtr
        cmp     byte ptr [rax], false
        je      @GotLockOnSmallBlockType // no pthread yet
        {$endif FPCMM_ASSUMEMULTITHREAD}
        // mov rax,fs:[$00000010] = inlined pthread_self on Linux X86_64
        db $64, $48, $8B, $04, $25, $10, $00, $00, $00
        {$else}
        {$ifdef WINDOWS}
        // TEB.ClientId.UniqueThread (Windows 7-11)
        db $65, $8B, $04, $25, $48, $00, $00, $00 // mov eax, gs:[$0048]
        {$else}
        unsupported
        {$endif WINDOWS}
        {$endif LINUX}
        {$ifdef LINUX}
        // Same low 32-bit Knuth hash as unsigned mul, without its unused high half
        imul    eax, eax, $9E3779B1
        {$else}
        mov     edx, $9E3779B1   // KNUTH_HASH32_MUL magic number
        mul     edx     // very fast on modern CPUs
        {$endif LINUX}
        shr     eax, 32 - NumTinyBlockArenasPO2 // high bits hash truncate
        {$ifdef FPCMM_MS_LINUX_FASTGET}
        jz      @TinySmall // Arena 0 = TSmallBlockInfo.Small[]
        shl     eax, NumTinyBlockTypesPO2 + SmallBlockTypePO2 // TTinyBlockTypes
	lea	rsi, [rax + rsi + TSmallBlockInfo.Tiny - SizeOf(TTinyBlockTypes)]
        {$else}
        jz      @Aren0  // Arena 0 = TSmallBlockInfo.Small[]
        shl     eax, NumTinyBlockTypesPO2 + SmallBlockTypePO2 // TTinyBlockTypes
	lea	rsi, [rax + rsi + TSmallBlockInfo.Tiny - SizeOf(TTinyBlockTypes)]
@Aren0: mov     edx, NumTinyBlockArenas + 1 // 8/128 Small + Tiny[] arenas
        jmp     @TinySmall
        {$ifdef WINDOWS}
        // Unreachable padding keeps downstream hot/cold branch layout stable
        db $0F, $1F, $40, $00
        {$endif WINDOWS}
        {$endif FPCMM_MS_LINUX_FASTGET}
        {$else}
        mov     edx, NumTinyBlockArenas + 1 // 8/128 Small + Tiny[] arenas
        {$endif FPCMM_TINYPERTHREAD}
        {$ifndef FPCMM_MS_LINUX_FASTGET}
        // Round-Robin attempt to lock next SmallBlockInfo.Tiny[]
@TinyBlockArenaLoop:
        mov     eax, SizeOf(TTinyBlockTypes)
        {$ifdef FPCMM_TINYPERTHREAD}
        // try next arenas following the per-thread one
        sub     rsi, r8
        sub     rsi, rcx
        jz      @Sml    // from Small[rcx] to Tiny[0][rcx]
        {$ifdef LINUX}
        lea     rax, [rax * 2 + rsi - TSmallBlockInfo.Tiny] // Tiny[+1][rcx]
        {$else}
        lea     rax, [rax + rsi - TSmallBlockInfo.Tiny] // Tiny[+1][rcx]
        {$endif LINUX}
@Sml:   {$else}
        // fair distribution among calls to reduce thread contention
        {$ifdef FPCMM_BOOST}
        // "lock xadd" decreases loop iterations but is slower on normal load
        lock
        {$endif FPCMM_BOOST}
        xadd    dword ptr [r8 + TSmallBlockInfo.TinyCurrentArena], eax
        {$endif FPCMM_TINYPERTHREAD}
        lea     rsi, [r8 + rcx]
        and     eax, ((NumTinyBlockArenas + 1) * SizeOf(TTinyBlockTypes)) - 1
        jz      @TinySmall // Arena 0 = TSmallBlockInfo.Small[]
	lea	rsi, [rax + rsi + TSmallBlockInfo.Tiny - SizeOf(TTinyBlockTypes)]
        {$endif FPCMM_MS_LINUX_FASTGET}
@TinySmall:
        // Can we get a Tiny block from its LastFree list?
        cmp     dword ptr [rsi].TSmallBlockType.LastFreeCount, 0
        je      @NoLastFree
        cmp     byte ptr [rsi].TSmallBlockType.LastFreeLocked, false
        jne     @NoLastFree
        call    GetSmallLastFreeBlockRsi
        {$ifdef NOSFRAME}
        jz      @NoLastFree
        ret
        {$else}
        jnz     @Quit // on Win64, a stack frame is required
        {$endif NOSFRAME}
@NoLastFree:
        // Try to lock this Tiny block
        mov     eax, $100
        {$ifdef FPCMM_CMPBEFORELOCK}
        cmp     byte ptr [rsi].TSmallBlockType.Locked, false // no lock in loop
        jnz     @NextTinyBlockArena1
        {$endif FPCMM_CMPBEFORELOCK}
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.Locked, ah
        je      @GotLockOnSmallBlockType
@NextTinyBlockArena1:
        {$ifdef FPCMM_MS_LINUX_FASTGET}
        // rdx still holds the non-negative lookup index on the first failure;
        // use a negative counter only on this cold retry path (31 more arenas)
        test    edx, edx
        jns     @FirstTinyBlockArenaFailure
        inc     edx
        jz      @TinyBlockArenasExhausted
        jmp     @NextTinyBlockArena
@FirstTinyBlockArenaFailure:
        mov     edx, -NumTinyBlockArenas
@NextTinyBlockArena:
        mov     eax, SizeOf(TTinyBlockTypes)
        sub     rsi, r8
        sub     rsi, rcx
        jz      @NextTinyBlockArenaFromSmall
        lea     rax, [rax * 2 + rsi - TSmallBlockInfo.Tiny]
@NextTinyBlockArenaFromSmall:
        lea     rsi, [r8 + rcx]
        and     eax, ((NumTinyBlockArenas + 1) * SizeOf(TTinyBlockTypes)) - 1
        jz      @TinySmall
	lea	rsi, [rax + rsi + TSmallBlockInfo.Tiny - SizeOf(TTinyBlockTypes)]
        jmp     @TinySmall
@TinyBlockArenasExhausted:
        {$else}
        dec     edx
        jnz     @TinyBlockArenaLoop
        {$endif FPCMM_MS_LINUX_FASTGET}
        // Fallback to SmallBlockInfo.Small[] next 2 small sizes - never occurs
        lea     rsi, [r8 + rcx + TSmallBlockInfo.Small + SizeOf(TSmallBlockType)]
        mov     eax, $100
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.Locked, ah
        je      @GotLockOnSmallBlockType
        add     rsi, SizeOf(TSmallBlockType) // next two small sizes
        mov     eax, $100
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.Locked, ah
        je      @GotLockOnSmallBlockType
        // Thread Contention (_Freemem is more likely)
        movzx   rax, [rsi].TSmallBlockType.BlockSize
        shr     rax, 2 // div by SmallBlockGranularity then * SizeOf(cardinal)
   lock inc     dword ptr [r8 + rax - 4].TSmallBlockInfo.GetmemSleepCount
        call    ReleaseCoreSafe
        jmp     @LockTinyBlockTypeLoop
        // ---------- SMALL (size<2600) block lock ----------
@NotTinyBlockType:
        // Try to get a Small block from its SmallLastFree[] list or the next two
        lea     rsi, [r8 + rcx].TSmallBlockInfo.Small
        cmp     dword ptr [rsi].TSmallBlockType.LastFreeCount, 0
        je      @SLL0
        cmp     byte ptr [rsi].TSmallBlockType.LastFreeLocked, false
        je      @SmallLockLess0
@SLL0:  cmp     dword ptr [rsi + SmallBlockTypeSize].TSmallBlockType.LastFreeCount, 0
        je      @SLL1
        cmp     byte ptr [rsi + SmallBlockTypeSize].TSmallBlockType.LastFreeLocked, false
        je      @SmallLockLess1
@SLL1:  cmp     dword ptr [rsi + SmallBlockTypeSize * 2].TSmallBlockType.LastFreeCount, 0
        je      @LockBlockTypeLoopRetry
        cmp     byte ptr [rsi + SmallBlockTypeSize * 2].TSmallBlockType.LastFreeLocked, false
        je      @LockBlockTypeLoopRetry
        add     rsi, SizeOf(TSmallBlockType) * 2
        call    GetSmallLastFreeBlockRsi
        jnz     {$ifdef NOSFRAME} @SLL {$else} @Quit {$endif}
        sub     rsi, SizeOf(TSmallBlockType) * 2
        jmp     @LockBlockTypeLoopRetry
@SmallLockLess0:
        call    GetSmallLastFreeBlockRsi
        jz      @SLL0
@SLL:   {$ifdef NOSFRAME}
        ret
        {$else}
        jmp     @Quit // on Win64, a stack frame is required
        {$endif NOSFRAME}
@SmallLockLess1:
        add     rsi, SizeOf(TSmallBlockType)
        call    GetSmallLastFreeBlockRsi
        jnz     {$ifdef NOSFRAME} @SLL {$else} @Quit {$endif}
        sub     rsi, SizeOf(TSmallBlockType)
        jmp     @SLL1
        // Try to lock this Small block or the next two
@LockBlockTypeLoopRetry:
        {$ifdef FPCMM_PAUSE}
        {$ifdef FPCMM_SLEEPTSC}
        rdtsc
        shl     rdx, 32
        lea     r9, [rax + rdx + SpinSmallGetmemLockTSC] // r9 = endtsc
        {$else}
        mov    edx, SpinSmallGetmemLockCount
        {$endif FPCMM_SLEEPTSC}
        {$endif FPCMM_PAUSE}
@LockBlockTypeLoop:
        // Grab the default block type
        mov     eax, $100
        {$ifdef FPCMM_CMPBEFORELOCK}
        cmp     byte ptr [rsi].TSmallBlockType.Locked, false
        jnz     @NextLockBlockType1
        {$endif FPCMM_CMPBEFORELOCK}
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.Locked, ah
        je      @GotLockOnSmallBlockType
        // Try up to two next sizes
        mov     eax, $100
@NextLockBlockType1:
        add     rsi, SizeOf(TSmallBlockType)
        {$ifdef FPCMM_CMPBEFORELOCK}
        cmp     byte ptr [rsi].TSmallBlockType.Locked, al
        jnz     @NextLockBlockType2
        {$endif FPCMM_CMPBEFORELOCK}
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.Locked, ah
        je      @GotLockOnSmallBlockType
        mov     eax, $100
@NextLockBlockType2:
        add     rsi, SizeOf(TSmallBlockType)
        pause
        {$ifdef FPCMM_CMPBEFORELOCK}
        cmp     byte ptr [rsi].TSmallBlockType.Locked, al
        jnz     @NextLockBlockType3
        {$endif FPCMM_CMPBEFORELOCK}
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.Locked, ah
        je      @GotLockOnSmallBlockType
@NextLockBlockType3:
        sub     rsi, 2 * SizeOf(TSmallBlockType)
        {$ifdef FPCMM_PAUSE}
        pause
        {$ifdef FPCMM_SLEEPTSC}
        rdtsc
        shl     rdx, 32
        or      rax, rdx
        cmp     rax, r9
        jb      @LockBlockTypeLoop // continue spinning until timeout
        {$else}
        dec     edx
        jnz     @LockBlockTypeLoop // continue until spin count reached
        {$endif FPCMM_SLEEPTSC}
        {$endif FPCMM_PAUSE}
        // Block type and two sizes larger are all locked - give up and sleep
        lea     rcx, [rip + SmallBlockInfo]
        movzx   rax, [rsi].TSmallBlockType.BlockSize
        shr     rax, 2 // div by SmallBlockGranularity then * SizeOf(cardinal)
   lock inc     dword ptr [rcx + rax - 4].TSmallBlockInfo.GetmemSleepCount
        call    ReleaseCoreSafe
        jmp     @LockBlockTypeLoopRetry
        // ---------- TINY/SMALL block registration ----------
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
@GotLockOnSmallBlock:
        add     rsi, rcx
        {$endif FPCMM_ASSUMEMULTITHREAD}
@GotLockOnSmallBlockType:
        // set rdx=NextPartiallyFreePool rax=FirstFreeBlock rcx=DropSmallFlagsMask
        mov     rdx, [rsi].TSmallBlockType.NextPartiallyFreePool
        add     [rsi].TSmallBlockType.GetmemCount, 1
        mov     rax, [rdx].TSmallBlockPoolHeader.FirstFreeBlock
        mov     rcx, DropSmallFlagsMask
        // Is there a pool with free blocks?
        cmp     rdx, rsi
        je      @TrySmallSequentialFeed
        add     [rdx].TSmallBlockPoolHeader.BlocksInUse, 1
        // Set the new first free block and the block header
        and     rcx, [rax - BlockHeaderSize]
        mov     [rdx].TSmallBlockPoolHeader.FirstFreeBlock, rcx
        mov     [rax - BlockHeaderSize], rdx
        // Is the chunk now full?
        jz      @RemoveSmallPool
        // Unlock the block type and leave
        mov     byte ptr [rsi].TSmallBlockType.Locked, false
        {$ifdef NOSFRAME}
        ret
        {$else}
        jmp     @Quit // on Win64, a stack frame is required
        {$endif NOSFRAME}
        {$ifndef FPCMM_MS_LINUX_FASTGET}
@VoidSize:
        inc     size // "we always need to allocate something" (see RTL heap.inc)
        jmp     @VoidSizeToSomething
        {$endif FPCMM_MS_LINUX_FASTGET}
@TrySmallSequentialFeed:
        // Feed a small block sequentially
        movzx   ecx, [rsi].TSmallBlockType.BlockSize
        mov     rdx, [rsi].TSmallBlockType.CurrentSequentialFeedPool
        add     rcx, rax
        // Can another block fit?
        cmp     rax, [rsi].TSmallBlockType.MaxSequentialFeedBlockAddress
        ja      @AllocateSmallBlockPool
        // Adjust number of used blocks and sequential feed pool
        mov     [rsi].TSmallBlockType.NextSequentialFeedBlockAddress, rcx
        add     [rdx].TSmallBlockPoolHeader.BlocksInUse, 1
        // Unlock the block type, set the block header and leave
        mov     byte ptr [rsi].TSmallBlockType.Locked, false
        mov     [rax - BlockHeaderSize], rdx
        {$ifdef NOSFRAME}
        ret
        {$else}
        jmp     @Quit // on Win64, a stack frame is required
        {$endif NOSFRAME}
@RemoveSmallPool:
        // Pool is full - remove it from the partially free list
        mov     rcx, [rdx].TSmallBlockPoolHeader.NextPartiallyFreePool
        mov     [rcx].TSmallBlockPoolHeader.PreviousPartiallyFreePool, rsi
        mov     [rsi].TSmallBlockType.NextPartiallyFreePool, rcx
        // Unlock the block type and leave
        mov     byte ptr [rsi].TSmallBlockType.Locked, false
        {$ifdef NOSFRAME}
        ret
        {$else}
        jmp     @Quit // on Win64, a stack frame is required
        {$endif NOSFRAME}
@AllocateSmallBlockPool:
        // Access shared information about Medium blocks storage
        {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
        mov     rax, rsi
        lea     rdx, [rip + SmallBlockInfo]
        sub     rax, rdx
        shr     eax, SmallBlockTypePO2 - 3 // 1 shl 3 = SizeOf(pointer)
        mov     rcx, [rdx + rax].TSmallBlockInfo.SmallMediumBlockInfo
        {$else}
        lea     rcx, [rip + SmallMediumBlockInfo]
        {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
        mov     r10, rcx
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, [rcx + TMediumBlockinfo.IsMultiThreadPtr]
        cmp     byte ptr [rax], false
        je      @MediumLocked1 // no lock if IsMultiThread=false
        {$endif FPCMM_ASSUMEMULTITHREAD}
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.Locked, ah
        je      @MediumLocked1
        call    LockMediumBlocks
@MediumLocked1:
        // From now own rbx=TSmallBlockType, so we need to preserve it
        push    rbx
        mov     rbx, rsi
        // Are there any available blocks of a suitable size?
        movsx   esi, [rbx].TSmallBlockType.AllowedGroupsForBlockPoolBitmap
        and     esi, [r10 + TMediumBlockInfo.BinGroupBitmap]
        jz      @NoSuitableMediumBlocks
        // Compute rax = bin group number with free blocks, rcx = bin number
        bsf     eax, esi
        lea     r9, [rax * 4]
        mov     ecx, [r10 + TMediumBlockInfo.BinBitmaps + r9]
        bsf     ecx, ecx
        lea     rcx, [rcx + r9 * 8]
        // Set rdi = @bin, rsi = free block
        lea     rsi, [rcx * 8] // SizeOf(TMediumBlockInfo.Bins[]) = 16
        lea     rdi, [r10 + TMediumBlockInfo.Bins + rsi * 2]
        mov     rsi, TMediumFreeBlock[rdi].NextFreeBlock
        // Remove the first block from the linked list (LIFO)
        mov     rdx, TMediumFreeBlock[rsi].NextFreeBlock
        mov     TMediumFreeBlock[rdi].NextFreeBlock, rdx
        mov     TMediumFreeBlock[rdx].PreviousFreeBlock, rdi
        // Is this bin now empty?
        cmp     rdi, rdx
        jne     @MediumBinNotEmpty
        // rbx = block type, rax = bin group number,
        // r9 = bin group number * 4, rcx = bin number, rdi = @bin, rsi = free block
        // Flag this bin (and the group if needed) as empty
        mov     edx,  - 2
        rol     edx, cl
        and     [r10 + TMediumBlockInfo.BinBitmaps + r9], edx
        jnz     @MediumBinNotEmpty
        btr     [r10 + TMediumBlockInfo.BinGroupBitmap], eax
@MediumBinNotEmpty:
        // rsi = free block, rbx = block type
        // Get the size of the available medium block in edi
        mov     rdi, DropMediumAndLargeFlagsMask
        and     rdi, [rsi - BlockHeaderSize]
        cmp     edi, MaximumSmallBlockPoolSize
        jb      @UseWholeBlock
        // Split the block: new block size is the optimal size
        mov     edx, edi
        movzx   edi, [rbx].TSmallBlockType.OptimalBlockPoolSize
        sub     edx, edi
        lea     rcx, [rsi + rdi]
        lea     rax, [rdx + IsMediumBlockFlag + IsFreeBlockFlag]
        mov     [rcx - BlockHeaderSize], rax
        // Store the size of the second split as the second last pointer
        mov     [rcx + rdx - 16], rdx
        // Put the remainder in a bin (it will be big enough)
        call    InsertMediumBlockIntoBin // rcx=P edx=blocksize r10=Info
        jmp     @GotMediumBlock
@NoSuitableMediumBlocks:
        // Check the sequential feed medium block pool for space
        movzx   ecx, [rbx].TSmallBlockType.MinimumBlockPoolSize
        mov     edi, [r10 + TMediumBlockInfo.SequentialFeedBytesLeft]
        cmp     edi, ecx
        jb      @AllocateNewSequentialFeed
        // Get the address of the last block that was fed
        mov     rsi, [r10 + TMediumBlockInfo.LastSequentiallyFed]
        // Enough sequential feed space: Will the remainder be usable?
        movzx   ecx, [rbx].TSmallBlockType.OptimalBlockPoolSize
        lea     rdx, [rcx + MinimumMediumBlockSize]
        cmp     edi, edx
        cmovae  edi, ecx
        sub     rsi, rdi
        // Update the sequential feed parameters
        sub     [r10 + TMediumBlockInfo.SequentialFeedBytesLeft], edi
        mov     [r10 + TMediumBlockInfo.LastSequentiallyFed], rsi
        jmp     @GotMediumBlock
@AllocateNewSequentialFeed:
        // Use the optimal size for allocating this small block pool
        {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
        mov     rax, rbx
        lea     rdx, [rip + SmallBlockInfo]
        sub     rax, rdx
        shr     eax, SmallBlockTypePO2 - 3 // 1 shl 3 = SizeOf(pointer)
        mov     rsi, [rdx + rax].TSmallBlockInfo.SmallMediumBlockInfo
        {$else}
        lea     rsi, [rip + SmallMediumBlockInfo]
        {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
        {$ifdef MSWINDOWS}
        movzx   ecx, word ptr [rbx].TSmallBlockType.OptimalBlockPoolSize
        mov     rdx, rsi
        push    rcx
        push    rdx
        {$else}
        movzx   edi, word ptr [rbx].TSmallBlockType.OptimalBlockPoolSize
        push    rdi
        push    rsi
        {$endif MSWINDOWS}
        // on input: ecx/edi=BlockSize, rdx/rsi=Info
        call    AllocNewSequentialFeedMediumPool
        pop     r10
        pop     rdi  // restore edi=blocksize and r10=TMediumBlockInfo
        mov     rsi, rax
        test    rax, rax
        jnz     @GotMediumBlock // rsi=freeblock rbx=blocktype edi=blocksize
        mov     [r10 + TMediumBlockInfo.Locked], al
        mov     [rbx].TSmallBlockType.Locked, al
        {$ifdef NOSFRAME}
        pop     rbx
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
        {$endif NOSFRAME}
@UseWholeBlock:
        // rsi = free block, rbx = block type, edi = block size
        // Mark this block as used in the block following it
        and     byte ptr [rsi + rdi - BlockHeaderSize],  NOT PreviousMediumBlockIsFreeFlag
@GotMediumBlock:
        // rsi = free block, rbx = small block type, edi = block size
        // Set the size and flags for this block
        lea     rcx, [rdi + IsMediumBlockFlag + IsSmallBlockPoolInUseFlag]
        mov     [rsi - BlockHeaderSize], rcx
        // Unlock medium blocks and setup the block pool
        xor     eax, eax
        mov     [r10 + TMediumBlockInfo.Locked], al
        mov     TSmallBlockPoolHeader[rsi].BlockType, rbx
        mov     TSmallBlockPoolHeader[rsi].FirstFreeBlock, rax
        mov     TSmallBlockPoolHeader[rsi].BlocksInUse, 1
        mov     [rbx].TSmallBlockType.CurrentSequentialFeedPool, rsi
        // Return the pointer to the first block, compute next/last block addresses
        lea     rax, [rsi + SmallBlockPoolHeaderSize]
        movzx   ecx, [rbx].TSmallBlockType.BlockSize
        lea     rdx, [rax + rcx]
        mov     [rbx].TSmallBlockType.NextSequentialFeedBlockAddress, rdx
        add     rdi, rsi
        sub     rdi, rcx
        mov     [rbx].TSmallBlockType.MaxSequentialFeedBlockAddress, rdi
        // Unlock the small block type, set header and leave
        mov     byte ptr [rbx].TSmallBlockType.Locked, false
        mov     [rax - BlockHeaderSize], rsi
        {$ifdef NOSFRAME}
        pop     rbx
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
        {$endif NOSFRAME}
        // ---------- MEDIUM block allocation ----------
@NotTinySmallBlock:
        // from now on, we may use the rbx register
        push    rbx
        // Do we need a Large block?
        lea     r10, [rip + MediumBlockInfo]
        {$ifdef FPCMM_MS_MEDIUM}
        xor     r9d, r9d
        mov     rax, qword ptr [rsi].TSmallBlockInfo.IsMultiThreadPtr
        cmp     byte ptr [rax], false
        je      @MediumArenaSelected
        mov     edx, $9E3779B1 // same per-thread hash as tiny/small arenas
        {$ifdef LINUX}
        // mov rax,fs:[$00000010] = inlined pthread_self on Linux X86_64
        db $64, $48, $8B, $04, $25, $10, $00, $00, $00
        {$else}
        {$ifdef WINDOWS}
        // inlined GetThreadID from the Win64 TEB (tested on Windows 7-11)
        db $65, $48, $8B, $04, $25, $30, $00, $00, $00
        mov     eax, [rax + $48]
        {$else}
        unsupported
        {$endif WINDOWS}
        {$endif LINUX}
        mul     edx
        shr     eax, 32 - NumMediumBlockArenasPO2
        mov     r9d, eax
        lea     r10, [rip + MediumBlockInfoLookup]
        mov     r10, [r10 + rax * 8]
@MediumArenaSelected:
        {$endif FPCMM_MS_MEDIUM}
        cmp     size, MaximumMediumBlockSize - BlockHeaderSize
        ja      @IsALargeBlockRequest
        // Get the bin size for this block size (rounded up to the next bin size)
        lea     rbx, [size + MediumBlockGranularity - 1 + BlockHeaderSize - MediumBlockSizeOffset]
        mov     rcx, r10
        and     ebx,  - MediumBlockGranularity
        add     ebx, MediumBlockSizeOffset
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, [r10 + TMediumBlockinfo.IsMultiThreadPtr]
        cmp     byte ptr [rax], false
        je      @MediumLocked2 // no lock if IsMultiThread=false
        {$endif FPCMM_ASSUMEMULTITHREAD}
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.Locked, ah
        je      @MediumLocked2
        {$ifdef FPCMM_MS_MEDIUM}
        // A thread hash may collide. Try every other arena before waiting on
        // the contended one; any arena is valid and each pool records owner.
        mov     r8d, NumMediumBlockArenas - 1
@TryNextMediumArena:
        inc     r9d
        and     r9d, NumMediumBlockArenas - 1
        lea     r10, [rip + MediumBlockInfoLookup]
        mov     r10, [r10 + r9 * 8]
        mov     rcx, r10
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.Locked, ah
        je      @MediumLocked2
        dec     r8d
        jnz     @TryNextMediumArena
        {$endif FPCMM_MS_MEDIUM}
        call    LockMediumBlocks
@MediumLocked2:
        // Compute ecx = bin number in ecx and edx = group number
        lea     rdx, [rbx - MinimumMediumBlockSize]
        mov     ecx, edx
        shr     edx, 8 + 5
        shr     ecx, 8
        mov     eax, -1
        shl     eax, cl
        and     eax, [r10 + TMediumBlockInfo.BinBitmaps + rdx * 4]
        jz      @GroupIsEmpty
        and     ecx,  - 32
        bsf     eax, eax
        or      ecx, eax
        jmp     @GotBinAndGroup
@GroupIsEmpty:
        // Try all groups greater than this group
        mov     eax,  - 2
        mov     ecx, edx
        shl     eax, cl
        and     eax, [r10 + TMediumBlockInfo.BinGroupBitmap]
        jz      @TrySequentialFeedMedium
        // There is a suitable group with enough space
        bsf     edx, eax
        mov     eax, [r10 + TMediumBlockInfo.BinBitmaps + rdx * 4]
        bsf     ecx, eax
        mov     eax, edx
        shl     eax, 5
        or      ecx, eax
        jmp     @GotBinAndGroup
@TrySequentialFeedMedium:
        mov     ecx, [r10 + TMediumBlockInfo.SequentialFeedBytesLeft]
        // Can block be fed sequentially?
        sub     ecx, ebx
        jc      @AllocateNewSequentialFeedForMedium
        // Get the block address, store remaining bytes, set the flags and unlock
        mov     rax, [r10 + TMediumBlockInfo.LastSequentiallyFed]
        sub     rax, rbx
        mov     [r10 + TMediumBlockInfo.LastSequentiallyFed], rax
        mov     [r10 + TMediumBlockInfo.SequentialFeedBytesLeft], ecx
        or      rbx, IsMediumBlockFlag
        mov     [rax - BlockHeaderSize], rbx
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
        {$ifdef NOSFRAME}
        pop     rbx
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
        {$endif NOSFRAME}
@AllocateNewSequentialFeedForMedium:
        {$ifdef MSWINDOWS}
        mov     ecx, ebx
        {$ifdef FPCMM_MS_MEDIUM}
        mov     rbx, r10 // preserve selected arena across the Pascal call
        mov     rdx, rbx
        {$else}
        lea     rdx, [rip + MediumBlockInfo]
        {$endif FPCMM_MS_MEDIUM}
        {$else}
        mov     edi, ebx
        {$ifdef FPCMM_MS_MEDIUM}
        mov     rbx, r10 // preserve selected arena across the Pascal call
        mov     rsi, rbx
        {$else}
        lea     rsi, [rip + MediumBlockInfo]
        {$endif FPCMM_MS_MEDIUM}
        {$endif MSWINDOWS}
        // on input: ecx/edi=BlockSize, rdx/rsi=Info
        call    AllocNewSequentialFeedMediumPool
        {$ifdef FPCMM_MS_MEDIUM}
        mov     byte ptr [rbx + TMediumBlockInfo.Locked], false
        {$else}
        mov     byte ptr [rip + MediumBlockInfo.Locked], false
        {$endif FPCMM_MS_MEDIUM}
        {$ifdef NOSFRAME}
        pop     rbx
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
        {$endif NOSFRAME}
@GotBinAndGroup:
        // ebx = block size, ecx = bin number, edx = group number
        // Compute rdi = @bin, rsi = free block
        lea     rax, [rcx + rcx]
        lea     rdi, [r10 + TMediumBlockInfo.Bins + rax * 8]
        mov     rsi, TMediumFreeBlock[rdi].NextFreeBlock
        // Remove the first block from the linked list (LIFO)
        mov     rax, TMediumFreeBlock[rsi].NextFreeBlock
        mov     TMediumFreeBlock[rdi].NextFreeBlock, rax
        mov     TMediumFreeBlock[rax].PreviousFreeBlock, rdi
        // Is this bin now empty?
        cmp     rdi, rax
        jne     @MediumBinNotEmptyForMedium
        // edx=bingroupnumber, ecx=binnumber, rdi=@bin, rsi=freeblock, ebx=blocksize
        // Flag this bin (and the group if needed) as empty
        mov     eax,  - 2
        rol     eax, cl
        and     [r10 + TMediumBlockInfo.BinBitmaps + rdx * 4], eax
        jnz     @MediumBinNotEmptyForMedium
        btr     [r10 + TMediumBlockInfo.BinGroupBitmap], edx
@MediumBinNotEmptyForMedium:
        // rsi = free block, ebx = block size
        // Get rdi = size of the available medium block, rdx = second split size
        mov     rdi, DropMediumAndLargeFlagsMask
        and     rdi, [rsi - BlockHeaderSize]
        mov     edx, edi
        sub     edx, ebx
        jz      @UseWholeBlockForMedium
        // Split the block in two
        lea     rcx, [rsi + rbx]
        lea     rax, [rdx + IsMediumBlockFlag + IsFreeBlockFlag]
        mov     [rcx - BlockHeaderSize], rax
        // Store the size of the second split as the second last pointer
        mov     [rcx + rdx - 16], rdx
        // Put the remainder in a bin
        cmp     edx, MinimumMediumBlockSize
        jb      @GotMediumBlockForMedium
        call    InsertMediumBlockIntoBin // rcx=P edx=blocksize r10=Info
        jmp     @GotMediumBlockForMedium
@UseWholeBlockForMedium:
        // Mark this block as used in the block following it
        and     byte ptr [rsi + rdi - BlockHeaderSize],  NOT PreviousMediumBlockIsFreeFlag
@GotMediumBlockForMedium:
        // Set the size and flags for this block
        lea     rcx, [rbx + IsMediumBlockFlag]
        mov     [rsi - BlockHeaderSize], rcx
        // Unlock medium blocks and leave
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
        mov     rax, rsi
        {$ifdef NOSFRAME}
        pop     rbx
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
        {$endif NOSFRAME}
        // ---------- LARGE block allocation ----------
@IsALargeBlockRequest:
        xor     rax, rax
        test    size, size
        js      @Done
        // Note: size is still in the rcx/rdi first param register
        call    AllocateLargeBlock
@Done:  // restore registers and the stack frame before ret
        pop     rbx
@Quit:  {$ifdef MSWINDOWS}
        pop     rdi
        pop     rsi
        {$endif MSWINDOWS}
end;

function FreeMediumBlock(arg1, arg2: pointer): PtrUInt;
  {$ifdef NOSFRAME} nostackframe; {$endif} assembler;
// rcx=P rdx=[P-BlockHeaderSize] r10=TMediumBlockInfo
// (arg1/arg2 are used only for proper call of pascal functions below on all ABI)
asm
        // Drop the flags, and set r11=P rbx=blocksize
        and     rdx, DropMediumAndLargeFlagsMask
        push    rbx
        push    rdx // save blocksize
        mov     rbx, rdx
        mov     r11, rcx
        // Lock the Medium blocks
        mov     rcx, r10
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, [r10 + TMediumBlockinfo.IsMultiThreadPtr]
        cmp     byte ptr [rax], false
        je      @MediumBlocksLocked // no lock if IsMultiThread=false
        {$endif FPCMM_ASSUMEMULTITHREAD}
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.Locked, ah
        je      @MediumBlocksLocked
        // Locked: add r11=P in TMediumBlockInfo.LastFree and Quit
@Atom0: mov     eax, $100
        pause
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.LastFreeLocked, ah
        jne     @Atom0
        mov     rax, [rcx].TMediumBlockInfo.LastFree
        mov     [r11], rax // use freed buffer as next linked list slot
        mov     [rcx].TMediumBlockInfo.LastFree, r11 // in list
        mov     byte ptr [rcx + TMediumBlockInfo.LastFreeLocked], false
        jmp     @Quit
@MediumBlocksLocked:
        // We acquired the lock: get rcx = next block size and flags
        mov     rcx, [r11 + rbx - BlockHeaderSize]
        // Can we combine this block with the next free block?
        test    qword ptr [r11 + rbx - BlockHeaderSize], IsFreeBlockFlag
        jnz     @NextBlockIsFree
        // Set the "PreviousIsFree" flag in the next block
        or      rcx, PreviousMediumBlockIsFreeFlag
        mov     [r11 + rbx - BlockHeaderSize], rcx
@NextBlockChecked:
        // Re-read the flags and try to combine with previous free block
        test    byte ptr [r11 - BlockHeaderSize], PreviousMediumBlockIsFreeFlag
        jnz     @PreviousBlockIsFree
@PreviousBlockChecked:
        // Check if entire medium block pool is free
        cmp     ebx, (MediumBlockPoolSize - MediumBlockPoolHeaderSize)
        je      @EntireMediumPoolFree
@Bin:   // Store size of the block, flags and trailing size marker and insert into bin
        lea     rax, [rbx + IsMediumBlockFlag + IsFreeBlockFlag]
        mov     [r11 - BlockHeaderSize], rax
        mov     [r11 + rbx - 16], rbx
        mov     rcx, r11
        mov     rdx, rbx
        call    InsertMediumBlockIntoBin // rcx=P edx=blocksize r10=Info
        // Check if some LastFree is pending
        cmp     qword ptr [r10].TMediumBlockInfo.LastFree, 0
        jnz     @LastFree
@Done:  // Unlock medium blocks and leave
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
        jmp     @Quit
@LastFree:
        // Release the next LastFree list block while we own the lock
@Atom1: mov     rcx, r10
        mov     eax, $100
        pause
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.LastFreeLocked, ah
        jne     @Atom1
        mov     r11, [rcx].TMediumBlockInfo.LastFree
        test    r11, r11
        jz      @Done
        mov     rax, [r11]
        mov     [rcx].TMediumBlockInfo.LastFree, rax
        mov     byte ptr [r10 + TMediumBlockInfo.LastFreeLocked], false
@OneBin:// Compute rbx=blocksize of r11 pointer retrieved from LastFree list
        mov     rbx, qword ptr [r11 - BlockHeaderSize]
        and     rbx, DropMediumAndLargeFlagsMask
        jmp     @MediumBlocksLocked
@NextBlockIsFree:
        // Get rax = next block address, rbx = end of the block
        lea     rax, [r11 + rbx]
        and     rcx, DropMediumAndLargeFlagsMask
        add     rbx, rcx
        // Was the block binned?
        cmp     rcx, MinimumMediumBlockSize
        jb      @NextBlockChecked
        mov     rcx, rax
        call    RemoveMediumFreeBlock // rcx = APMediumFreeBlock
        jmp     @NextBlockChecked
@PreviousBlockIsFree:
        // Get rcx =  size/point of the previous free block, rbx = new block end
        mov     rcx, [r11 - 16]
        sub     r11, rcx
        add     rbx, rcx
        // Remove the previous block from the linked list
        cmp     ecx, MinimumMediumBlockSize
        jb      @PreviousBlockChecked
        mov     rcx, r11
        call    RemoveMediumFreeBlock // rcx = APMediumFreeBlock
        jmp     @PreviousBlockChecked
@EntireMediumPoolFree:
        // Ensure current sequential feed pool is free
        cmp     dword ptr [r10 + TMediumBlockInfo.SequentialFeedBytesLeft], MediumBlockPoolSize - MediumBlockPoolHeaderSize
        jne     @MakeEmptyMediumPoolSequentialFeed
        // Remove this medium block pool from the linked list stored in its header
        sub     r11, MediumBlockPoolHeaderSize
        mov     rax, TMediumBlockPoolHeader[r11].PreviousMediumBlockPoolHeader
        mov     rdx, TMediumBlockPoolHeader[r11].NextMediumBlockPoolHeader
        mov     TMediumBlockPoolHeader[rax].NextMediumBlockPoolHeader, rdx
        mov     TMediumBlockPoolHeader[rdx].PreviousMediumBlockPoolHeader, rax
        // Unlock medium blocks and free the block pool
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
        mov     arg1, r11
        mov     arg2, r10
        call    FreeMedium // munmap() may take time - or cache in Info.Prefetch
        jmp     @Quit
@MakeEmptyMediumPoolSequentialFeed:
        // Get rbx = end-marker block, and recycle the current sequential feed pool
        lea     rbx, [r11 + MediumBlockPoolSize - MediumBlockPoolHeaderSize]
        mov     arg1, r10
        call    BinMediumSequentialFeedRemainder
        // Set this medium pool up as the new sequential feed pool, unlock and leave
        mov     qword ptr [rbx - BlockHeaderSize], IsMediumBlockFlag
        mov     dword ptr [r10 + TMediumBlockInfo.SequentialFeedBytesLeft], MediumBlockPoolSize - MediumBlockPoolHeaderSize
        mov     [r10 + TMediumBlockInfo.LastSequentiallyFed], rbx
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
@Quit:  // restore registers and the stack frame
        pop     rax // medium block size
        pop     rbx
end;

{$ifdef FPCMM_REPORTMEMORYLEAKS}
const
  /// mark freed blocks with 00000000 BLODLESS marker to track incorrect usage
  REPORTMEMORYLEAK_FREEDHEXSPEAK = $B10D1E55;
{$endif FPCMM_REPORTMEMORYLEAKS}

function _FreeMem(P: pointer): PtrUInt;
  {$ifdef NOSFRAME} nostackframe; {$endif} assembler;
asm     // P = rcx on Windows, P = rdi on SystemV
        {$ifndef MSWINDOWS}
        mov     rcx, P
        {$endif MSWINDOWS}
        {$ifdef FPCMM_REPORTMEMORYLEAKS}
        mov     eax, REPORTMEMORYLEAK_FREEDHEXSPEAK // 00000000 BLODLESS marker
        {$endif FPCMM_REPORTMEMORYLEAKS}
        test    rcx, rcx
        jz      @Void
        {$ifdef FPCMM_REPORTMEMORYLEAKS}
        mov     [rcx], rax // overwrite TObject VMT or string/dynarray header
        {$endif FPCMM_REPORTMEMORYLEAKS}
        mov     rdx, [rcx - BlockHeaderSize]
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, qword ptr [rip + SmallBlockInfo].TSmallBlockInfo.IsMultiThreadPtr
        {$endif FPCMM_ASSUMEMULTITHREAD}
        // Is it a small block in use?
        test    dl, IsFreeBlockFlag + IsMediumBlockFlag + IsLargeBlockFlag
        jnz     @NotSmallBlockInUse
        // Keep TSmallBlockType in the register best suited to each ABI:
        // rbx on Win64 and caller-saved rsi on SystemV.
        {$ifdef MSWINDOWS}
        push    rbx
        mov     rbx, [rdx].TSmallBlockPoolHeader.BlockType
        {$else}
        mov     rsi, [rdx].TSmallBlockPoolHeader.BlockType
        {$endif MSWINDOWS}
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        cmp     byte ptr [rax], false
        je      @FreeAndUnLock
        {$endif FPCMM_ASSUMEMULTITHREAD}
        mov     eax, $100
        {$ifdef MSWINDOWS}
  lock  cmpxchg byte ptr [rbx].TSmallBlockType.Locked, ah
        {$else}
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.Locked, ah
        {$endif MSWINDOWS}
        jne     @TinySmallLocked
@FreeAndUnlock:
        // block type register, rcx=P, rdx=TSmallBlockPoolHeader
        // Adjust number of blocks in use, set rax = old first free block
        {$ifdef MSWINDOWS}
        add     [rbx].TSmallBlockType.FreememCount, 1
        {$else}
        add     [rsi].TSmallBlockType.FreememCount, 1
        {$endif MSWINDOWS}
        mov     rax, [rdx].TSmallBlockPoolHeader.FirstFreeBlock
        sub     [rdx].TSmallBlockPoolHeader.BlocksInUse, 1
        jz      @PoolIsNowEmpty
@StoreFreeBlock:
        // Store this as the new first free block
        mov     [rdx].TSmallBlockPoolHeader.FirstFreeBlock, rcx
        // Store the previous first free block as the block header
        lea     r9, [rax + IsFreeBlockFlag]
        mov     [rcx - BlockHeaderSize], r9
        // Was the pool full?
        test    rax, rax
        jnz     @SmallPoolWasNotFull
        // Insert the pool back into the linked list if it was full
        {$ifdef MSWINDOWS}
        mov     rcx, [rbx].TSmallBlockType.NextPartiallyFreePool
        mov     [rdx].TSmallBlockPoolHeader.PreviousPartiallyFreePool, rbx
        {$else}
        mov     rcx, [rsi].TSmallBlockType.NextPartiallyFreePool
        mov     [rdx].TSmallBlockPoolHeader.PreviousPartiallyFreePool, rsi
        {$endif MSWINDOWS}
        mov     [rdx].TSmallBlockPoolHeader.NextPartiallyFreePool, rcx
        mov     [rcx].TSmallBlockPoolHeader.PreviousPartiallyFreePool, rdx
        {$ifdef MSWINDOWS}
        mov     [rbx].TSmallBlockType.NextPartiallyFreePool, rdx
        {$else}
        mov     [rsi].TSmallBlockType.NextPartiallyFreePool, rdx
        {$endif MSWINDOWS}
@SmallPoolWasNotFull:
        // Try to release all pending bin from this block while we have the lock
        {$ifdef MSWINDOWS}
        cmp     dword ptr [rbx].TSmallBlockType.LastFreeCount, 0
        {$else}
        cmp     dword ptr [rsi].TSmallBlockType.LastFreeCount, 0
        {$endif MSWINDOWS}
        jne     @ProcessPendingBin
        // Release the lock and return the block size as FPC RTL MM
@NoBin: {$ifdef MSWINDOWS}
        mov     byte ptr [rbx].TSmallBlockType.Locked, false
        movzx   eax, word ptr [rbx].TSmallBlockType.BlockSize
        {$else}
        mov     byte ptr [rsi].TSmallBlockType.Locked, false
        movzx   eax, word ptr [rsi].TSmallBlockType.BlockSize
        {$endif MSWINDOWS}
        {$ifdef NOSFRAME}
        {$ifdef MSWINDOWS}
        pop     rbx
        {$endif MSWINDOWS}
        ret
@Void:  xor     eax, eax
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
@Void:  xor     eax, eax
        jmp     @Quit
        {$endif NOSFRAME}
@PoolIsNowEmpty:
        // FirstFreeBlock=nil means it is the sequential feed pool with a single block
        test    rax, rax
        {$ifdef FPCMM_MOONSHARD}
        jz      @EmptySequentialFeedPool
        {$else}
        jz      @IsSequentialFeedPool
        {$endif FPCMM_MOONSHARD}
        // Pool is now empty: Remove it from the linked list and free it
        mov     rax, [rdx].TSmallBlockPoolHeader.PreviousPartiallyFreePool
        mov     rcx, [rdx].TSmallBlockPoolHeader.NextPartiallyFreePool
        mov     TSmallBlockPoolHeader[rax].NextPartiallyFreePool, rcx
        mov     [rcx].TSmallBlockPoolHeader.PreviousPartiallyFreePool, rax
        // Is this the sequential feed pool? If so, stop sequential feeding
        xor     eax, eax
        {$ifdef MSWINDOWS}
        cmp     [rbx].TSmallBlockType.CurrentSequentialFeedPool, rdx
        {$else}
        cmp     [rsi].TSmallBlockType.CurrentSequentialFeedPool, rdx
        {$endif MSWINDOWS}
        jne     @NotSequentialFeedPool
@IsSequentialFeedPool:
        {$ifdef MSWINDOWS}
        mov     [rbx].TSmallBlockType.MaxSequentialFeedBlockAddress, rax
        {$else}
        mov     [rsi].TSmallBlockType.MaxSequentialFeedBlockAddress, rax
        {$endif MSWINDOWS}
@NotSequentialFeedPool:
        // Unlock blocktype and release this pool
        {$ifdef MSWINDOWS}
        mov     byte ptr [rbx].TSmallBlockType.Locked, false
        {$else}
        mov     byte ptr [rsi].TSmallBlockType.Locked, false
        {$endif MSWINDOWS}
        mov     rcx, rdx
        mov     rdx, [rdx - BlockHeaderSize]
        {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
        {$ifdef MSWINDOWS}
        mov     rax, rbx
        {$else}
        mov     rax, rsi
        {$endif MSWINDOWS}
        lea     r10, [rip + SmallBlockInfo]
        sub     rax, r10
        shr     eax, SmallBlockTypePO2 - 3 // 1 shl 3 = SizeOf(pointer)
        mov     r10, [r10 + rax].TSmallBlockInfo.SmallMediumBlockInfo
        {$else}
        lea     r10, [rip + SmallMediumBlockInfo]
        {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
        {$ifdef MSWINDOWS}
        call    FreeMediumBlock // rbx is non-volatile in the Win64 ABI
        movzx   eax, word ptr [rbx].TSmallBlockType.BlockSize
        {$else}
        movzx   eax, word ptr [rsi].TSmallBlockType.BlockSize
        push    rax
        call    FreeMediumBlock // no call nor BinLocked to avoid race condition
        pop     rax
        {$endif MSWINDOWS}
        {$ifdef NOSFRAME}
        {$ifdef MSWINDOWS}
        pop     rbx
        {$endif MSWINDOWS}
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
        {$endif NOSFRAME}
        {$ifdef FPCMM_MOONSHARD}
@EmptySequentialFeedPool:
        // Keep one empty pool after repeated single-block churn. Tiny classes
        // retain it immediately; larger small classes first prove reuse.
        // Those larger classes are global, not per-thread/per-arena: retaining
        // every one is bounded to about 1.2 MiB with the current pool table.
        {$ifdef MSWINDOWS}
        cmp     word ptr [rbx].TSmallBlockType.BlockSize, 256
        jbe     @StoreFreeBlock
        cmp     byte ptr [rbx].TSmallBlockType.EmptyPoolReuseScore, SmallBlockHotPoolThreshold
        jae     @StoreFreeBlock
        inc     byte ptr [rbx].TSmallBlockType.EmptyPoolReuseScore
        {$else}
        cmp     word ptr [rsi].TSmallBlockType.BlockSize, 256
        jbe     @StoreFreeBlock
        cmp     byte ptr [rsi].TSmallBlockType.EmptyPoolReuseScore, SmallBlockHotPoolThreshold
        jae     @StoreFreeBlock
        inc     byte ptr [rsi].TSmallBlockType.EmptyPoolReuseScore
        {$endif MSWINDOWS}
        jmp     @IsSequentialFeedPool
        {$endif FPCMM_MOONSHARD}
@ProcessPendingBin:
        // Release the next SmallLastFree list block while we own the lock
        {$ifdef MSWINDOWS}
        cmp     byte ptr [rbx].TSmallBlockType.LastFreeLocked, false
        {$else}
        cmp     byte ptr [rsi].TSmallBlockType.LastFreeLocked, false
        {$endif MSWINDOWS}
        jne     @NoBin
        {$ifdef MSWINDOWS}
        call    GetSmallLastFreeBlockRbx
        {$else}
        call    GetSmallLastFreeBlockRsi
        {$endif MSWINDOWS}
        jz      @NoBin
        mov     rcx, rax
        mov     rdx, [rax - BlockHeaderSize]
        // block type register, rcx=P, rdx=TSmallBlockPoolHeader
        jmp     @FreeAndUnlock // will loop until LastFreeCount=0
@NotSmallBlockInUse:
        test    dl, IsFreeBlockFlag + IsLargeBlockFlag
        // P is still in rcx/rdi first param register
        {$ifdef FPCMM_MS_MEDIUM}
        jnz     @FreeLarge
        mov     r10, rcx
        and     r10, not MediumBlockAlignmentMask
        mov     r10, [r10 + TMediumBlockPoolHeader.Reserved1]
        {$ifdef NOSFRAME}
        jmp     FreeMediumBlock
@FreeLarge:
        jmp     FreeLargeBlock
        {$else}
        call    FreeMediumBlock
        jmp     @Quit
@FreeLarge:
        call    FreeLargeBlock
        jmp     @Quit
        {$endif NOSFRAME}
        {$else}
        lea     r10, [rip + MediumBlockInfo]
        {$ifdef NOSFRAME}
        jz      FreeMediumBlock
        jmp     FreeLargeBlock // local function returns 0 or the block size
        {$else} // on Win64, a stack frame is required
        jz      @Medium
        call    FreeLargeBlock
        jmp     @Quit
@Medium:call    FreeMediumBlock
        jmp     @Quit
        {$endif NOSFRAME}
        {$endif FPCMM_MS_MEDIUM}
@TinySmallLocked:
        // This small block is locked: add rcx=P to the LastFree list block
        {$ifdef MSWINDOWS}
        mov     rax, rbx
        {$else}
        mov     rax, rsi
        {$endif MSWINDOWS}
        lea     r10, [rip + SmallBlockInfo]
        sub     rax, r10
        shr     eax, SmallBlockTypePO2 - 3 // 1 shl 3 = SizeOf(pointer)
        lea     r10, [r10 + rax].TSmallBlockInfo.SmallLastFree
        // r10 = @SmallLastFree[] of this block type
@Atom2: mov     eax, $100
        {$ifdef MSWINDOWS}
  lock  cmpxchg byte ptr [rbx].TSmallBlockType.LastFreeLocked, ah
        {$else}
  lock  cmpxchg byte ptr [rsi].TSmallBlockType.LastFreeLocked, ah
        {$endif MSWINDOWS}
        je      @Atom3
        pause
        jmp     @Atom2
@Atom3: mov     rax, [r10]
        mov     [rcx], rax  // very simple linked list
        mov     [r10], rcx
        {$ifdef MSWINDOWS}
        inc     dword ptr [rbx].TSmallBlockType.LastFreeCount
        mov     byte ptr [rbx].TSmallBlockType.LastFreeLocked, false
        movzx   eax, word ptr [rbx].TSmallBlockType.BlockSize
@Done:  // restore rbx and the stack frame before ret
        pop     rbx
        {$else}
        inc     dword ptr [rsi].TSmallBlockType.LastFreeCount
        mov     byte ptr [rsi].TSmallBlockType.LastFreeLocked, false
        movzx   eax, word ptr [rsi].TSmallBlockType.BlockSize
@Done:
        {$endif MSWINDOWS}
@Quit:
end;

// warning: FPC signature is not the same than Delphi: requires "var P"
function _ReallocMem(var P: pointer; Size: PtrUInt): pointer;
  {$ifdef NOSFRAME} nostackframe; {$endif} assembler;
asm
        {$ifdef MSWINDOWS}
        push    rdi
        push    rsi
        {$else}
        mov     rdx, Size
        {$endif MSWINDOWS}
        push    rbx
        push    r14
        push    P // for assignement in @Done
        mov     r14, qword ptr [P]
        test    rdx, rdx
        jz      @VoidSize  // ReallocMem(P,0)=FreeMem(P)
        test    r14, r14
        jz      @GetMemMoveFreeMem // ReallocMem(nil,Size)=GetMem(Size)
        mov     rcx, [r14 - BlockHeaderSize]
        test    cl, IsFreeBlockFlag + IsMediumBlockFlag + IsLargeBlockFlag
        jnz     @NotASmallBlock
        // -------------- TINY/SMALL block -------------
        // Get rbx=blocktype, rcx=available size, rax=inplaceresize
        mov     rbx, [rcx].TSmallBlockPoolHeader.BlockType
        lea     rax, [rdx * 4 + SmallBlockDownsizeCheckAdder]
        movzx   ecx, [rbx].TSmallBlockType.BlockSize
        sub     ecx, BlockHeaderSize
        cmp     rcx, rdx
        jb      @SmallUpsize
        // Downsize or small growup with enough space: reallocate only if need
        cmp     eax, ecx
        jb      @GetMemMoveFreeMem // r14=P rdx=size
@NoResize:
        // branchless execution if current block is good enough for this size
        mov     rax, r14 // keep original pointer
        pop     rcx
        {$ifdef NOSFRAME}
        pop     r14
        pop     rbx
        ret
        {$else}
        jmp     @Quit // on Win64, a stack frame is required
        {$endif NOSFRAME}
@VoidSize:
        push    rdx    // to set P=nil
        jmp     @DoFree // ReallocMem(P,0)=FreeMem(P)
@SmallUpsize:
        // State: r14=pointer, rdx=NewSize, rcx=CurrentBlockSize, rbx=CurrentBlockType
        // Small blocks always grow with at least 100% + SmallBlockUpsizeAdder bytes
        lea     P, qword ptr [rcx * 2 + SmallBlockUpsizeAdder]
        movzx   ebx, [rbx].TSmallBlockType.BlockSize
        sub     ebx, BlockHeaderSize + 8
        // r14=pointer, P=NextUpBlockSize, rdx=NewSize, rbx=OldSize-8
@AdjustGetMemMoveFreeMem:
        // New allocated size is max(requestedsize, minimumupsize)
        cmp     rdx, P
        cmova   P, rdx
        push    rdx
        call    _GetMem
        pop     rdx
        test    rax, rax
        jz      @Done
        jmp     @MoveFreeMem // rax=New r14=P rbx=size-8
@GetMemMoveFreeMem:
        // reallocate copy and free: r14=P rdx=size
        mov     rbx, rdx
        mov     P, rdx // P is the proper first argument register
        call    _GetMem
        test    rax, rax
        jz      @Done
        test    r14, r14 // ReallocMem(nil,Size)=GetMem(Size)
        jz      @Done
        sub     rbx, 8
@MoveFreeMem:
        // copy and free: rax=New r14=P rbx=size-8
        push    rax
        {$ifdef FPCMM_ERMS}
        cmp     rbx, ErmsMinSize // startup cost of 0..255 bytes
        jae     @erms
        {$endif FPCMM_ERMS}
        lea     rcx, [r14 + rbx]
        lea     rdx, [rax + rbx]
        neg     rbx
        jns     @Last8
        align   16
@By16:  movaps  xmm0, oword ptr [rcx + rbx]
        movaps  oword ptr [rdx + rbx], xmm0
        add     rbx, 16
        js      @By16
@Last8: mov     rax, qword ptr [rcx + rbx]
        mov     qword ptr [rdx + rbx], rax
@DoFree:mov     P, r14
        call    _FreeMem
        pop     rax
        jmp     @Done
        {$ifdef FPCMM_ERMS}
@erms:  cld
        mov     rsi, r14
        mov     rdi, rax
        lea     rcx, [rbx + 8]
        rep movsb
        jmp     @DoFree
        {$endif FPCMM_ERMS}
@NotASmallBlock:
        // Is this a medium block or a large block?
        test    cl, IsFreeBlockFlag + IsLargeBlockFlag
        jnz     @PossibleLargeBlock
        // -------------- MEDIUM block -------------
        // rcx=CurrentSize+Flags, r14=P, rdx=RequestedSize, r10=TMediumBlockInfo
        lea     rsi, [rdx + rdx]
        {$ifdef FPCMM_MS_MEDIUM}
        mov     r10, r14
        and     r10, not MediumBlockAlignmentMask
        mov     r10, [r10 + TMediumBlockPoolHeader.Reserved1]
        {$else}
        lea     r10, [rip + MediumBlockInfo]
        {$endif FPCMM_MS_MEDIUM}
        mov     rbx, rcx
        and     ecx, DropMediumAndLargeFlagsMask
        lea     rdi, [r14 + rcx]
        sub     ecx, BlockHeaderSize
        and     ebx, ExtractMediumAndLargeFlagsMask
        // Is it an upsize or a downsize?
        cmp     rdx, rcx
        ja      @MediumBlockUpsize
        // rcx=CurrentBlockSize-BlockHeaderSize, rbx=CurrentBlockFlags,
        // rdi=@NextBlock, r14=P, rdx=RequestedSize
        // Downsize reallocate and move data only if less than half the current size
        cmp     rsi, rcx
        jae     @NoResize
        // In-place downsize? Ensure not smaller than MinimumMediumBlockSize
        cmp     edx, MinimumMediumBlockSize - BlockHeaderSize
        jae     @MediumBlockInPlaceDownsize
        // Need to move to another Medium block pool, or into a Small block?
        cmp     edx, MediumInPlaceDownsizeLimit
        jb      @GetMemMoveFreeMem
        // No need to realloc: resize in-place (if not already at the minimum size)
        mov     edx, MinimumMediumBlockSize - BlockHeaderSize
        cmp     ecx, MinimumMediumBlockSize - BlockHeaderSize
        jna     @NoResize
@MediumBlockInPlaceDownsize:
        // Round up to the next medium block size
        lea     rsi, [rdx + BlockHeaderSize + MediumBlockGranularity - 1 - MediumBlockSizeOffset]
        and     rsi,  - MediumBlockGranularity
        add     rsi, MediumBlockSizeOffset
        // Get the size of the second split
        add     ecx, BlockHeaderSize
        sub     ecx, esi
        mov     ebx, ecx
        // Lock the medium blocks
        mov     rcx, r10
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, [r10 + TMediumBlockinfo.IsMultiThreadPtr]
        cmp     byte ptr [rax], false
        je      @MediumBlocksLocked1 // no lock if IsMultiThread=false
        {$endif FPCMM_ASSUMEMULTITHREAD}
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.Locked, ah
        je      @MediumBlocksLocked1
        call    LockMediumBlocks
@MediumBlocksLocked1:
        mov     ecx, ebx
        // Reread the flags - may have changed before medium blocks could be locked
        mov     rbx, ExtractMediumAndLargeFlagsMask
        and     rbx, [r14 - BlockHeaderSize]
@DoMediumInPlaceDownsize:
        // Set the new size in header, and get rbx = second split size
        or      rbx, rsi
        mov     [r14 - BlockHeaderSize], rbx
        mov     ebx, ecx
        // If the next block is used, flag its previous block as free
        mov     rdx, [rdi - BlockHeaderSize]
        test    dl, IsFreeBlockFlag
        jnz     @MediumDownsizeNextBlockFree
        or      rdx, PreviousMediumBlockIsFreeFlag
        mov     [rdi - BlockHeaderSize], rdx
        jmp     @MediumDownsizeDoSplit
@MediumDownsizeNextBlockFree:
        // If the next block is free, combine both
        mov     rcx, rdi
        and     rdx, DropMediumAndLargeFlagsMask
        add     rbx, rdx
        add     rdi, rdx
        cmp     edx, MinimumMediumBlockSize
        jb      @MediumDownsizeDoSplit
        call    RemoveMediumFreeBlock // rcx=APMediumFreeBlock
@MediumDownsizeDoSplit:
        // Store the trailing size field and free part header
        mov     [rdi - 16], rbx
        lea     rcx, [rbx + IsMediumBlockFlag + IsFreeBlockFlag];
        mov     [r14 + rsi - BlockHeaderSize], rcx
        // Bin this free block (if worth it)
        cmp     rbx, MinimumMediumBlockSize
        jb      @MediumBlockDownsizeDone
        lea     rcx, [r14 + rsi]
        mov     rdx, rbx
        call    InsertMediumBlockIntoBin // rcx=P edx=blocksize r10=Info
@MediumBlockDownsizeDone:
        // Unlock the medium blocks, and leave with the new pointer
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
        mov     rax, r14
        jmp     @Done
@MediumBlockUpsize:
        // ecx = Current Block Size - BlockHeaderSize, bl = Current Block Flags,
        // rdi = @Next Block, r14 = P, rdx = Requested Size
        // Try to make in-place upsize
        mov     rax, [rdi - BlockHeaderSize]
        test    al, IsFreeBlockFlag
        jz      @CannotUpsizeMediumBlockInPlace
        // Get rax = available size, rsi = available size with the next block
        and     rax, DropMediumAndLargeFlagsMask
        lea     rsi, [rax + rcx]
        cmp     rdx, rsi
        ja      @CannotUpsizeMediumBlockInPlace
        // Grow into the next block
        mov     rbx, rcx
        mov     rcx, r10
        {$ifndef FPCMM_ASSUMEMULTITHREAD}
        mov     rax, [r10 + TMediumBlockinfo.IsMultiThreadPtr]
        cmp     byte ptr [rax], false
        je      @MediumBlocksLocked2 // no lock if IsMultiThread=false
        {$endif FPCMM_ASSUMEMULTITHREAD}
        mov     eax, $100
  lock  cmpxchg byte ptr [rcx].TMediumBlockInfo.Locked, ah
        je      @MediumBlocksLocked2
        mov     rsi, rdx
        call    LockMediumBlocks
        mov     rdx, rsi
@MediumBlocksLocked2:
        // Re-read info once locked, and ensure next block is still free
        mov     rcx, rbx
        mov     rbx, ExtractMediumAndLargeFlagsMask
        and     rbx, [r14 - BlockHeaderSize]
        mov     rax, [rdi - BlockHeaderSize]
        test    al, IsFreeBlockFlag
        jz      @NextMediumBlockChanged
        and     eax, DropMediumAndLargeFlagsMask
        lea     rsi, [rax + rcx]
        cmp     rdx, rsi
        ja      @NextMediumBlockChanged
@DoMediumInPlaceUpsize:
        // Bin next free block (if worth it)
        cmp     eax, MinimumMediumBlockSize
        jb      @MediumInPlaceNoNextRemove
        push    rcx
        push    rdx
        mov     rcx, rdi
        call    RemoveMediumFreeBlock // rcx=APMediumFreeBlock
        pop     rdx
        pop     rcx
@MediumInPlaceNoNextRemove:
        // Medium blocks grow a minimum of 25% in in-place upsizes
        mov     eax, ecx
        shr     eax, 2
        add     eax, ecx
        // Get the maximum of the requested size and the minimum growth size
        xor     edi, edi
        sub     eax, edx
        adc     edi, -1
        and     eax, edi
        // Round up to the nearest block size granularity
        lea     rax, [rax + rdx + BlockHeaderSize + MediumBlockGranularity - 1 - MediumBlockSizeOffset]
        and     eax, -MediumBlockGranularity
        add     eax, MediumBlockSizeOffset
        // Calculate the size of the second split and check if it fits
        lea     rdx, [rsi + BlockHeaderSize]
        sub     edx, eax
        ja      @MediumInPlaceUpsizeSplit
        // Grab the whole block: Mark it as used in the next block, and adjust size
        and     qword ptr [r14 + rsi],  NOT PreviousMediumBlockIsFreeFlag
        add     rsi, BlockHeaderSize
        jmp     @MediumUpsizeInPlaceDone
@MediumInPlaceUpsizeSplit:
        // Store the size of the second split as the second last pointer
        mov     [r14 + rsi - BlockHeaderSize], rdx
        // Set the second split header
        lea     rdi, [rdx + IsMediumBlockFlag + IsFreeBlockFlag]
        mov     [r14 + rax - BlockHeaderSize], rdi
        mov     rsi, rax
        cmp     edx, MinimumMediumBlockSize
        jb      @MediumUpsizeInPlaceDone
        lea     rcx, [r14 + rax]
        call    InsertMediumBlockIntoBin // rcx=P edx=blocksize r10=Info
@MediumUpsizeInPlaceDone:
        // No need to move data at upsize: set the size and flags for this block
        or      rsi, rbx
        mov     [r14 - BlockHeaderSize], rsi
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
        mov     rax, r14
        jmp     @Done
@NextMediumBlockChanged:
        // The next block changed during lock: reallocate and move data
        mov     byte ptr [r10 + TMediumBlockInfo.Locked], false
@CannotUpsizeMediumBlockInPlace:
        // rcx=OldSize-8, rdx=NewSize
        mov     rbx, rcx
        mov     eax, ecx
        shr     eax, 2
        lea     P, qword ptr [rcx + rax] // NextUpBlockSize = OldSize+25%
        jmp     @AdjustGetMemMoveFreeMem // P=BlockSize, rdx=NewSize, rbx=OldSize-8
@PossibleLargeBlock:
        // -------------- LARGE block -------------
        test    cl, IsFreeBlockFlag + IsMediumBlockFlag
        jnz     @Error
        {$ifdef MSWINDOWS}
        mov     rcx, r14
        {$else}
        mov     rdi, r14
        mov     rsi, rdx
        {$endif MSWINDOWS}
        call    ReallocateLargeBlock // with restored proper registers
        jmp     @Done
@Error: xor     eax, eax
@Done:  // restore registers and the stack frame before ret
        pop     rcx
        mov     qword ptr [rcx], rax // store new pointer in var P
@Quit:  pop     r14
        pop     rbx
        {$ifdef MSWINDOWS}
        pop     rsi
        pop     rdi
        {$endif MSWINDOWS}
end;

function _AllocMem(Size: PtrUInt): pointer;
  {$ifdef NOSFRAME} nostackframe; {$endif} assembler;
asm
        push    rbx
        // Compute rbx = size rounded down to the last pointer
        lea     rbx, [Size - 1]
        and     rbx,  - 8
        // Perform the memory allocation
        call    _GetMem
        // Could a block be allocated? rcx = 0 if yes, -1 if no
        cmp     rax, 1
        sbb     rcx, rcx
        // Point rdx to the last pointer
        lea     rdx, [rax + rbx]
        // Compute Size (1..8 doesn't need to enter the SSE2 loop)
        or      rbx, rcx
        jz      @LastQ
        // Large blocks from mmap/VirtualAlloc are already zero filled
        cmp     rbx, MaximumMediumBlockSize - BlockHeaderSize
        jae     @Done
        {$ifdef FPCMM_ERMS}
        cmp     rbx, ErmsMinSize // startup cost of 0..255 bytes
        jae     @erms
        {$endif FPCMM_ERMS}
        neg     rbx
        pxor    xmm0, xmm0
        align   16
@FillLoop: // non-temporal movntdq not needed with small/medium size
        movaps  oword ptr [rdx + rbx], xmm0
        add     rbx, 16
        js      @FillLoop
        // fill the last pointer
@LastQ: xor     rcx, rcx
        mov     qword ptr [rdx], rcx
        {$ifdef FPCMM_ERMS}
        {$ifdef NOSFRAME}
        pop     rbx
        ret
        {$else}
        jmp     @Done // on Win64, a stack frame is required
        {$endif NOSFRAME}
        // ERMS has a startup cost, but "rep stosd" is fast enough on all CPUs
@erms:  mov     rcx, rbx
        push    rax
        {$ifdef MSWINDOWS}
        push    rdi
        {$endif MSWINDOWS}
        cld
        mov     rdi, rdx
        xor     eax, eax
        sub     rdi, rbx
        shr     ecx, 2
        mov     qword ptr [rdx], rax
        rep stosd
        {$ifdef MSWINDOWS}
        pop     rdi
        {$endif MSWINDOWS}
        pop     rax
        {$endif FPCMM_ERMS}
@Done:  // restore rbx register and the stack frame before ret
        pop     rbx
end;

function _MemSize(P: pointer): PtrUInt;
begin
  // AFAIK used only by fpc_AnsiStr_SetLength() in FPC RTL
  // also used by our static SQLite3 for its xSize() callback
  P := PPointer(PByte(P) - BlockHeaderSize)^;
  if (PtrUInt(P) and (IsMediumBlockFlag or IsLargeBlockFlag)) = 0 then
    result := PSmallBlockPoolHeader(PtrUInt(P) and DropSmallFlagsMask).
      BlockType.BlockSize - BlockHeaderSize
  else
  begin
    result := (PtrUInt(P) and DropMediumAndLargeFlagsMask) - BlockHeaderSize;
    if (PtrUInt(P) and IsMediumBlockFlag) = 0 then
      dec(result, LargeBlockHeaderSize);
  end;
end;

function _FreeMemSize(P: pointer; size: PtrUInt): PtrInt;
begin
  // size = 0 needs to call _FreeMem() because GetMem(P,0) returned something
  result := _FreeMem(P); // P=nil will return 0
  // returns the chunk size - only used by heaptrc AFAIK
end;


{ ********* Information Gathering }

{$ifdef FPCMM_STANDALONE}

procedure Assert(flag: boolean);
begin
end;

{$else}

function _GetFPCHeapStatus: TFPCHeapStatus;
var
  mm: PMMStatus;
begin
  mm := @HeapStatus;
  {$ifdef FPCMM_DEBUG}
  result.MaxHeapSize := mm^.Medium.PeakBytes + mm^.Large.PeakBytes;
  {$else}
  result.MaxHeapSize := 0;
  {$endif FPCMM_DEBUG}
  result.MaxHeapUsed := result.MaxHeapSize;
  result.CurrHeapSize := mm^.Medium.CurrentBytes + mm^.Large.CurrentBytes;
  result.CurrHeapUsed := result.CurrHeapSize;
  result.CurrHeapFree := 0;
end;

function _GetHeapInfo: Utf8String;
begin
  // RetrieveMemoryManagerInfo from mormot.core.log expects RawUtf8 as result
  result := GetHeapStatus(' - fpcx64mm: ', 16, 16, {flags=}true, {sameline=}true);
end;

function _GetHeapStatus: THeapStatus;
begin
  // use this deprecated 32-bit structure to return hidden information
  FillChar(result, sizeof(result), 0);
  PShortString(@result.TotalAddrSpace)^ := 'fpcx64mm'; // magic
  PPointer(@result.Unused)^ := @_GetHeapInfo;
end;

type
  // match both TSmallBlockStatus and TSmallBlockContention
  TRes = array[0..2] of PtrUInt;
  // details are allocated on the stack, not the heap
  TResArray = array[0..(NumSmallInfoBlock * 2) - 1] of TRes;

procedure QuickSortRes(var Res: TResArray; L, R, Level: PtrInt);
var
  I, J, P: PtrInt;
  pivot: PtrUInt;
  tmp: TRes;
begin
  if L < R then
    repeat
      I := L;
      J := R;
      P := (L + R) shr 1;
      repeat
        pivot := Res[P, Level]; // Level is 0..2
        while Res[I, Level] > pivot do
          inc(I);
        while Res[J, Level] < pivot do
          dec(J);
        if I <= J then
        begin
          tmp := Res[J];
          Res[J] := Res[I];
          Res[I] := tmp;
          if P = I then
            P := J
          else if P = J then
            P := I;
          inc(I);
          dec(J);
        end;
      until I > J;
      if J - L < R - I then
      begin
        // use recursion only for smaller range
        if L < J then
          QuickSortRes(Res, L, J, Level);
        L := I;
      end
      else
      begin
        if I < R then
          QuickSortRes(Res, I, R, Level);
        R := J;
      end;
    until L >= R;
end;

procedure SetSmallBlockStatus(var res: TResArray; out small, tiny: cardinal);
var
  i, a: integer;
  p: PSmallBlockType;
  d: ^TSmallBlockStatus;
begin
  small := 0;
  tiny := 0;
  d := @res;
  p := @SmallBlockInfo;
  // gather TSmallBlockInfo.Small[] info
  for i := 1 to NumSmallBlockTypes do
  begin
    inc(small, ord(p^.GetmemCount <> 0));
    d^.Total := p^.GetmemCount;
    d^.Current := p^.GetmemCount - p^.FreememCount;
    d^.BlockSize := p^.BlockSize;
    inc(d);
    inc(p);
  end;
  // gather TSmallBlockInfo.Tiny[] info
  for a := 1 to NumTinyBlockArenas do
  begin
    d := @res; // aggregate counters
    for i := 1 to NumTinyBlockTypes do
    begin
      inc(tiny, ord(p^.GetmemCount <> 0));
      inc(d^.Total, p^.GetmemCount);
      inc(d^.Current, p^.GetmemCount - p^.FreememCount);
      inc(d);
      inc(p);
    end;
  end;
  assert(p = @SmallBlockInfo.GetmemLookup);
end;

function SortSmallBlockStatus(var res: TResArray; maxcount, orderby: PtrInt;
  count, bytes: PPtrUInt): PtrInt;
var
  i: PtrInt;
begin
  QuickSortRes(res, 0, NumSmallBlockTypes - 1, orderby);
  if count <> nil then
  begin
    count^ := 0;
    for i := 0 to NumSmallBlockTypes - 1 do
      inc(count^, res[i, orderby]);
  end;
  if bytes <> nil then
  begin
    bytes^ := 0;
    for i := 0 to NumSmallBlockTypes - 1 do
      inc(bytes^, res[i, orderby] * res[i, ord(obBlockSize)]);
  end;
  result := maxcount;
  if result > NumSmallBlockTypes then
    result := NumSmallBlockTypes;
  while (result > 0) and
        (res[result - 1, orderby] = 0) do
    dec(result);
end;

function SetSmallBlockContention(var res: TResArray; maxcount: integer): integer;
var
  i: integer;
  siz: cardinal;
  p: PCardinal;
  d: ^TSmallBlockContention;
begin
  result := 0;
  d := @res;
  p := @SmallBlockInfo.GetmemSleepCount;
  siz := 0;
  for i := 1 to length(SmallBlockInfo.GetmemSleepCount) do
  begin
    inc(siz, SmallBlockGranularity);
    if p^ <> 0 then
    begin
      d^.GetmemSleepCount := p^;
      d^.GetmemBlockSize := siz;
      d^.Reserved := 0;
      inc(d);
      inc(result);
    end;
    inc(p);
  end;
  if result = 0 then
    exit;
  QuickSortRes(res, 0, result - 1, 0); // sort by Level=0=GetmemSleepCount
  if result > maxcount then
    result := maxcount;
end;

var // use a pre-allocated buffer to avoid any heap usage during status output
  WrStrBuf: array[0 .. 1023] of AnsiChar; // typically less than 600 bytes
  WrStrPos: PtrInt;
  WrStrOnSameLine: boolean;

procedure W(const txt: ShortString);
var
  p, n: PtrInt;
begin
  n := ord(txt[0]);
  if n = 0 then
    exit;
  p := WrStrPos;
  inc(n, p);
  if n >= high(WrStrBuf) then
    exit; // paranoid
  Move(txt[1], WrStrBuf[p], ord(txt[0]));
  WrStrPos := n;
end;

const
  K_: array[0..4] of string[1] = (
    'P', 'T', 'G', 'M', 'K');

procedure K(const txt: ShortString; i: PtrUInt);
var
  j, n: PtrUInt;
  kk: PShortString;
  tmp: ShortString;
begin
  W(txt);
  kk := nil;
  n := PtrUInt(1) shl 50;
  for j := 0 to high(K_) do
    if i >= n then
    begin
      i := i div n;
      kk := @K_[j];
      break;
    end
    else
      n := n shr 10;
  str(i, tmp);
  W(tmp);
  if kk <> nil then
    W(kk^);
end;

procedure S(const txt: ShortString; i: PtrUInt);
var
  tmp: ShortString;
begin
  W(txt);
  str(i, tmp);
  W(tmp);
end;

procedure LF(const txt: ShortString = '');
begin
  if txt[0] <> #0 then
    W(txt);
  if WrStrOnSameLine then
    W(' ')
  else
    W({$ifdef OSWINDOWS} #13#10 {$else} #10 {$endif});
end;

procedure WriteHeapStatusDetail(const arena: TMMStatusArena;
  const name: ShortString);
begin
  K(name, arena.CurrentBytes);
  K('B/', arena.CumulativeBytes);
  W('B ');
  {$ifdef FPCMM_DEBUG}
  K('   peak=', arena.PeakBytes);
  K('B current=', arena.CumulativeAlloc - arena.CumulativeFree);
  K(' alloc=', arena.CumulativeAlloc);
  K(' free=', arena.CumulativeFree);
  {$endif FPCMM_DEBUG}
  K(' sleep=', arena.SleepCount);
  LF;
end;

function GetHeapStatus(const context: ShortString; smallblockstatuscount,
  smallblockcontentioncount: integer; compilationflags, onsameline: boolean): PAnsiChar;
var
  res: TResArray; // no heap allocation involved
  i, n: PtrInt;
  t, b: PtrUInt;
  small, tiny: cardinal;
begin
  WrStrOnSameLine := onsameline;
  WrStrPos := 0;
  if context[0] <> #0 then
    LF(context);
  if compilationflags then
    LF(' Flags:' + FPCMM_FLAGS);
  with CurrentHeapStatus do
  begin
    K(' Small:  ', SmallBlocks);
    K('/', SmallBlocksSize);
    K('B  including tiny<=', SmallBlockSizes[NumTinyBlockTypes - 1]);
    S('B arenas=', NumTinyBlockArenas + 1);
    {$ifdef FPCMM_SMALLNOTWITHMEDIUM}
    {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
    S(' pools=', length(SmallMediumBlockInfo));
    {$else}
    W(' fed from its own pool');
    {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
    {$else}
    W(' fed from Medium');
    {$endif FPCMM_SMALLNOTWITHMEDIUM}
    LF;
    WriteHeapStatusDetail(Medium, ' Medium: ');
    WriteHeapStatusDetail(Large,  ' Large:  ');
    if SleepCount <> 0 then
    begin
      K(' Total Sleep: count=', SleepCount);
      {$ifdef FPCMM_SLEEPTSC} K(' rdtsc=', SleepCycles); {$endif}
      LF;
    end;
    if SmallGetmemSleepCount <> 0 then
    begin
      K(' Small GetMem Sleep: count=', SmallGetmemSleepCount);
      LF;
    end;
  end;
  if (smallblockcontentioncount > 0) and
     (CurrentHeapStatus.SmallGetmemSleepCount <> 0) then
  begin
    n := SetSmallBlockContention(res, smallblockcontentioncount);
    for i := 0 to n - 1 do
      with TSmallBlockContention(res[i]) do
      begin
        S(' ', GetmemBlockSize);
        K('=' , GetmemSleepCount);
        if (i and 7 = 7) or
           (i = n - 1) then
          LF;
      end;
  end;
  if smallblockstatuscount > 0 then
  begin
    SetSmallBlockStatus(res, small, tiny);
    n := SortSmallBlockStatus(res, smallblockstatuscount, ord(obTotal), @t, @b) - 1;
    K(' Small Blocks since beginning: ', t);
    K('/', b);
    K('B (as small=', small);
    S('/', NumSmallBlockTypes);
    K(' tiny=', tiny);
    S('/', NumTinyBlockArenas * NumTinyBlockTypes);
    LF(')');
    for i := 0 to n do
      with TSmallBlockStatus(res[i]) do
      begin
        S('  ', BlockSize);
        K('=', Total);
        if (i and 7 = 7) or
           (i = n) then
          LF;
      end;
    n := SortSmallBlockStatus(res, smallblockstatuscount, ord(obCurrent), @t, @b) - 1;
    K(' Small Blocks current: ', t);
    K('/', b);
    LF('B');
    for i := 0 to n do
      with TSmallBlockStatus(res[i]) do
      begin
        S('  ', BlockSize);
        K('=', Current);
        if (i and 7 = 7) or
           (i = n) then
          LF;
      end;
  end;
  LF;
  WrStrBuf[WrStrPos] := #0; // makes PAnsiChar
  result := @WrStrBuf;
end;

procedure WriteHeapStatus(const context: ShortString; smallblockstatuscount,
  smallblockcontentioncount: integer; compilationflags: boolean);
begin
  GetHeapStatus(context,  smallblockstatuscount, smallblockcontentioncount,
    compilationflags, {onsameline=}false);
  {$ifdef MSWINDOWS} // write all text at once
  {$I-}
  write(PAnsiChar(@WrStrBuf));
  ioresult;
  {$I+}
  {$else}
  fpwrite(StdOutputHandle, @WrStrBuf, WrStrPos); // POSIX
  {$endif MSWINDOWS}
end;

function GetSmallBlockStatus(maxcount: integer; orderby: TSmallBlockOrderBy;
  count, bytes: PPtrUInt; small, tiny: PCardinal): TSmallBlockStatusDynArray;
var
  res: TResArray;
  sm, ti: cardinal;
begin
  assert(SizeOf(TRes) = SizeOf(TSmallBlockStatus));
  result := nil;
  if maxcount <= 0 then
    exit;
  SetSmallBlockStatus(res, sm, ti);
  if small <> nil then
    small^ := sm;
  if tiny <> nil then
    tiny^ := ti;
  maxcount := SortSmallBlockStatus(res, maxcount, ord(orderby), count, bytes);
  if maxcount = 0 then
    exit;
  SetLength(result, maxcount);
  Move(res[0], result[0], maxcount * SizeOf(res[0]));
end;

function GetSmallBlockContention(maxcount: integer): TSmallBlockContentionDynArray;
var
  n: integer;
  res: TResArray;
begin
  result := nil;
  if maxcount <= 0 then
    exit;
  n := SetSmallBlockContention(res, maxcount);
  if n = 0 then
    exit;
  SetLength(result, n);
  Move(res[0], result[0], n * SizeOf(res[0]));
end;

{$endif FPCMM_STANDALONE}

function CurrentHeapStatus: TMMStatus;
var
  i: PtrInt;
  small, pending: PtrUInt;
  p: PSmallBlockType;
begin
  result := HeapStatus;
  small := 0;
  for i := 0 to high(SmallBlockInfo.GetmemSleepCount) do
    inc(small, SmallBlockInfo.GetmemSleepCount[i]);
  result.SmallGetmemSleepCount := small;
  p := @SmallBlockInfo;
  for i := 1 to NumSmallInfoBlock do
  begin
    small := p^.GetmemCount - p^.FreememCount;
    // A contended FreeMem has already released ownership, even if the block
    // still waits in SmallLastFree for the allocator to recycle it.  Sample
    // the pending count once and saturate because this is a lock-free status
    // snapshot and the three counters may move between reads.
    pending := p^.LastFreeCount;
    if pending < small then
      dec(small, pending)
    else
      small := 0;
    if small <> 0 then
    begin
      inc(result.SmallBlocks, small);
      inc(result.SmallBlocksSize, small * p^.BlockSize);
    end;
    inc(p);
  end;
end;


{ ********* Initialization and Finalization }

procedure InitializeMediumPool(var Info: TMediumBlockInfo);
var
  i: PtrInt;
  medium: PMediumFreeBlock;
begin
  {$ifndef FPCMM_ASSUMEMULTITHREAD}
  Info.IsMultiThreadPtr := @IsMultiThread;
  {$endif FPCMM_ASSUMEMULTITHREAD}
  Info.PoolsCircularList.PreviousMediumBlockPoolHeader := @Info.PoolsCircularList;
  Info.PoolsCircularList.NextMediumBlockPoolHeader := @Info.PoolsCircularList;
  for i := 0 to MediumBlockBinCount - 1 do
  begin
    medium := @Info.Bins[i];
    medium.PreviousFreeBlock := medium;
    medium.NextFreeBlock := medium;
  end;
  {$ifdef FPCMM_MEDIUMPREFETCH}
  Info.Prefetch := OsAllocMedium(MediumBlockPoolSizeMem);
  {$endif FPCMM_MEDIUMPREFETCH}
end;

procedure InitializeMemoryManager;
var
  small: PSmallBlockType;
  a, i, min, poolsize, num, perpool, size, start, next: PtrInt;
begin
  {$ifdef FPCMM_MS_MEDIUM}
  MediumBlockInfoLookup[0] := @MediumBlockInfo;
  for i := 1 to high(MediumBlockInfoLookup) do
    MediumBlockInfoLookup[i] := @MediumBlockInfoExtra[i];
  {$endif FPCMM_MS_MEDIUM}
  InitializeMediumPool(MediumBlockInfo);
  {$ifdef FPCMM_MS_MEDIUM}
  for i := 1 to high(MediumBlockInfoExtra) do
    InitializeMediumPool(MediumBlockInfoExtra[i]);
  {$endif FPCMM_MS_MEDIUM}
  {$ifdef FPCMM_SMALLNOTWITHMEDIUM}
  for i := 0 to high(SmallMediumBlockInfo) do
    InitializeMediumPool(SmallMediumBlockInfo[i]);
  {$endif FPCMM_SMALLNOTWITHMEDIUM}
  SmallBlockInfo.IsMultiThreadPtr := @IsMultiThread; // call GOT if needed
  small := @SmallBlockInfo;
  assert(SizeOf(small^) = 1 shl SmallBlockTypePO2);  // exactly 64 bytes
  {$ifdef FPCMM_MS_TABLE}
  assert(NumSmallBlockTypeSlots = NumTinyBlockTypes); // 64 slots = 4096B
  assert(NumSmallBlockTypes = NumSmallBlockTypeSlots);
  assert(NumSmallBlockClasses = 44);
  {$endif FPCMM_MS_TABLE}
  assert(length(SmallBlockInfo.GetmemSleepCount) =
    length(SmallBlockInfo.GetmemLookup));
  for a := 0 to NumTinyBlockArenas do
    for i := 0 to NumSmallBlockTypes - 1 do
    begin
      if (i = NumTinyBlockTypes) and
         (a > 0) then
        break;
      size := SmallBlockSizes[i];
      assert(size and 15 = 0);
      small^.BlockSize := size;
      small^.PreviousPartiallyFreePool := pointer(small);
      small^.NextPartiallyFreePool := pointer(small);
      small^.MaxSequentialFeedBlockAddress := pointer(0);
      small^.NextSequentialFeedBlockAddress := pointer(1);
      min := ((size * MinimumSmallBlocksPerPool +
         (SmallBlockPoolHeaderSize + MediumBlockGranularity - 1 - MediumBlockSizeOffset))
         and -MediumBlockGranularity) + MediumBlockSizeOffset;
      if min < MinimumMediumBlockSize then
        min := MinimumMediumBlockSize;
      num := (min + (- MinimumMediumBlockSize +
        MediumBlockBinsPerGroup * MediumBlockGranularity div 2)) div
        (MediumBlockBinsPerGroup * MediumBlockGranularity);
      if num > 7 then
        num := 7;
      small^.AllowedGroupsForBlockPoolBitmap := byte(byte(-1) shl num);
      small^.MinimumBlockPoolSize := MinimumMediumBlockSize +
        num * (MediumBlockBinsPerGroup * MediumBlockGranularity);
      poolsize := ((size * TargetSmallBlocksPerPool +
        (SmallBlockPoolHeaderSize + MediumBlockGranularity - 1 - MediumBlockSizeOffset))
        and -MediumBlockGranularity) + MediumBlockSizeOffset;
      if poolsize < OptimalSmallBlockPoolSizeLowerLimit then
        poolsize := OptimalSmallBlockPoolSizeLowerLimit;
      if poolsize > OptimalSmallBlockPoolSizeUpperLimit then
        poolsize := OptimalSmallBlockPoolSizeUpperLimit;
      perpool := (poolsize - SmallBlockPoolHeaderSize) div size;
      small^.OptimalBlockPoolSize := ((perpool * size +
         (SmallBlockPoolHeaderSize + MediumBlockGranularity - 1 - MediumBlockSizeOffset))
          and -MediumBlockGranularity) + MediumBlockSizeOffset;
      inc(small);
    end;
  assert(small = @SmallBlockInfo.GetmemLookup);
  start := 0;
  with SmallBlockInfo do
    for i := 0 to NumSmallBlockClasses - 1 do
    begin
      next := PtrUInt(SmallBlockSizes[i]) div SmallBlockGranularity;
      while start < next do
      begin
        GetmemLookup[start] := i;
        inc(start);
      end;
    end;
  {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
  num := 0;
  for i := 0 to high(SmallBlockInfo.SmallMediumBlockInfo) do
  begin
    SmallBlockInfo.SmallMediumBlockInfo[i] := @SmallMediumBlockInfo[num];
    if num = high(SmallMediumBlockInfo) then
      num := 0
    else if i = NumSmallBlockTypes - 1 then
      dec(num) // last Small[] slot is unused: skip for better distribution
    else
      inc(num);
    //if SmallBlockInfo.Small[i].BlockSize = 16 then write(num:4);
  end;
  {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
  LargeBlocksCircularList.PreviousLargeBlockHeader := @LargeBlocksCircularList;
  LargeBlocksCircularList.NextLargeBlockHeader := @LargeBlocksCircularList;
end;

{$I-} // no console output error check in write/writeln below

{$ifdef FPCMM_REPORTMEMORYLEAKS}

var
  MemoryLeakReported: boolean;

procedure StartReport;
begin
  if MemoryLeakReported then
    exit;
  writeln {$ifndef MSWINDOWS} (#27'[1;31m') {$endif}; // lightred posix console
  WriteHeapStatus('WARNING! THIS PROGRAM LEAKS MEMORY!'#13#10'Memory Status:');
  writeln('Leaks Identified:' {$ifndef MSWINDOWS} + #27'[1;37m' {$endif});
  MemoryLeakReported := true;
end;

{$ifdef FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
var
  ObjectLeaksCount, ObjectLeaksRaiseCount: integer;
{$ifdef MSWINDOWS}
  LastMemInfo: TMemInfo; // simple cache

function SeemsRealPointer(p: pointer): boolean;
var
  meminfo: TMemInfo;
begin
  result := false;
  if PtrUInt(p) <= 65535 then
    exit; // first 64KB is not a valid pointer by definition
  if (LastMemInfo.State <> 0) and
     (PtrUInt(p) - LastMemInfo.BaseAddress < LastMemInfo.RegionSize) then
    result := true // quick check against last valid memory region
  else
  begin
    // VirtualQuery API is slow but better than raising an exception
    // see https://stackoverflow.com/a/37547837/458259
    FillChar(meminfo, SizeOf(meminfo), 0);
    result := (VirtualQuery(p, @meminfo, SizeOf(meminfo)) = SizeOf(meminfo)) and
              (meminfo.State = MEM_COMMIT) and
              (PtrUInt(p) - meminfo.BaseAddress < meminfo.RegionSize) and
              (meminfo.Protect and PAGE_VALID <> 0) and
              (meminfo.Protect and PAGE_GUARD = 0);
    if result then
      LastMemInfo := meminfo;
  end;
end;
{$else}
function SeemsRealPointer(p: pointer): boolean;
begin
  // let the GPF happen silently in the kernel
  result := (PtrUInt(p) > 65535) and
            (fpaccess(p, F_OK) <> 0) and
            (fpgeterrno <> ESysEFAULT);
end;
{$endif MSWINDOWS}

function SeemsClassName(P: PAnsiChar): boolean;
var
  l: PtrInt;
begin
  result := false;
  l := ord(P[0]);
  if (l = 0) or
     not (P[1] in ['A' .. 'z']) then
    exit;
  repeat
    if P[l] <= ' ' then
      exit;
    dec(l);
  until l = 0;
  result := true;
end;

{$endif FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}

procedure MediumMemoryLeakReport(
  var Info: TMediumBlockInfo; p: PMediumBlockPoolHeader);
var
  block: PByte;
  header, size: PtrUInt;
  {$ifdef FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
  first, last: PByte;
  vmt: PAnsiChar;
  instancesize, blocksize: PtrInt;
  classname: PShortString;
  {$endif FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
begin
  if (Info.SequentialFeedBytesLeft = 0) or
     (PtrUInt(Info.LastSequentiallyFed) < PtrUInt(p)) or
     (PtrUInt(Info.LastSequentiallyFed) > PtrUInt(p) + MediumBlockPoolSize) then
    block := Pointer(PByte(p) + MediumBlockPoolHeaderSize)
  else if Info.SequentialFeedBytesLeft <>
            MediumBlockPoolSize - MediumBlockPoolHeaderSize then
      block := Info.LastSequentiallyFed
    else
      exit;
  repeat
    header := PPtrUInt(block - BlockHeaderSize)^;
    size := header and DropMediumAndLargeFlagsMask;
    if size = 0 then
      exit;
    if header and IsFreeBlockFlag = 0 then
      if header and IsSmallBlockPoolInUseFlag <> 0 then
      begin
        {$ifdef FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
        if PSmallBlockPoolHeader(block).BlocksInUse > 0 then // some leaks
        begin
          blocksize := PSmallBlockPoolHeader(block).BlockType.BlockSize;
          first := PByte(block) + SmallBlockPoolHeaderSize;
          with PSmallBlockPoolHeader(block).BlockType^ do
            if (CurrentSequentialFeedPool <> pointer(block)) or
               (PtrUInt(NextSequentialFeedBlockAddress) >
                PtrUInt(MaxSequentialFeedBlockAddress)) then
              last := PByte(block) + (PPtrUInt(PByte(block) - BlockHeaderSize)^
                and DropMediumAndLargeFlagsMask) - BlockSize
            else
              last := Pointer(PByte(NextSequentialFeedBlockAddress) - 1);
          while (first <= last) and
                (ObjectLeaksRaiseCount < 64) do
          begin
            if ((PPtrUInt(first - BlockHeaderSize)^ and IsFreeBlockFlag) = 0) then
            begin
              vmt := PPointer(first)^; // _FreeMem() ensured vmt=nil/$b10dle55
              if (vmt <> nil) and
                 ((PtrUInt(vmt) and (SizeOf(Pointer) - 1)) = 0) and
                 {$ifdef FPCMM_REPORTMEMORYLEAKS}
                 (PtrUInt(vmt) <> REPORTMEMORYLEAK_FREEDHEXSPEAK) and
                 // FreeMem marked freed blocks with BLOODLESS hexspeak magic
                 {$endif FPCMM_REPORTMEMORYLEAKS}
                 SeemsRealPointer(vmt) then
              try
                // try to access the TObject VMT
                instancesize := PPtrInt(vmt + vmtInstanceSize)^;
                if (instancesize >= sizeof(vmt)) and
                   (instancesize <= blocksize) then
                begin
                  classname := PPointer(vmt + vmtClassName)^;
                  if SeemsRealPointer(classname) and
                     SeemsClassName(pointer(classname)) then
                  begin
                     StartReport;
                     writeln(' probable ', classname^, ' leak (', instancesize,
                       '/', blocksize, ' bytes) at $', HexStr(first));
                     inc(ObjectLeaksCount);
                  end;
                end;
              except
                // intercept and ignore any GPF - SeemsRealPointer() not enough
                inc(ObjectLeaksRaiseCount);
                {$ifdef MSWINDOWS}
                LastMemInfo.State := 0; // reset VirtualQuery() cache
                {$endif MSWINDOWS}
              end;
            end;
            inc(first, blocksize);
          end;
        end;
        {$endif FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
      end
      else
      begin
        StartReport;
        writeln(' medium block leak of ', size, ' bytes');
      end;
    inc(block, size);
  until false;
end;

{$else}

{$undef FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}

{$endif FPCMM_REPORTMEMORYLEAKS}

procedure FreeMediumPool(var Info: TMediumBlockInfo);
var
  medium, nextmedium: PMediumBlockPoolHeader;
  bin: PMediumFreeBlock;
  i: PtrInt;
  {$ifdef FPCMM_REPORTMEMORYLEAKS}
  list, next: PPointer;
  {$endif FPCMM_REPORTMEMORYLEAKS}
begin
  {$ifdef FPCMM_REPORTMEMORYLEAKS}
  list := Info.LastFree;
  {$endif FPCMM_REPORTMEMORYLEAKS}
  Info.LastFree := nil;
  // All pools owned by Info are released just below. Calling the generic
  // _FreeMem() dispatcher here is both redundant and wrong for a pending
  // small-pool medium block: IsSmallBlockPoolInUseFlag has the same value as
  // IsLargeBlockFlag, so _FreeMem() would route it to FreeLargeBlock.
  {$ifdef FPCMM_REPORTMEMORYLEAKS}
  while list <> nil do
  begin
    next := list^;
    PPtrUInt(PByte(list) - BlockHeaderSize)^ :=
      PPtrUInt(PByte(list) - BlockHeaderSize)^ or IsFreeBlockFlag;
    list := next;
  end;
  {$endif FPCMM_REPORTMEMORYLEAKS}
  medium := Info.PoolsCircularList.NextMediumBlockPoolHeader;
  while medium <> @Info.PoolsCircularList do
  begin
    {$ifdef FPCMM_REPORTMEMORYLEAKS}
    MediumMemoryLeakReport(Info, medium);
    {$endif FPCMM_REPORTMEMORYLEAKS}
    nextmedium := medium.NextMediumBlockPoolHeader;
    FreeMedium(medium, Info);
    medium := nextmedium;
  end;
  Info.PoolsCircularList.PreviousMediumBlockPoolHeader := @Info.PoolsCircularList;
  Info.PoolsCircularList.NextMediumBlockPoolHeader := @Info.PoolsCircularList;
  for i := 0 to MediumBlockBinCount - 1 do
  begin
    bin := @Info.Bins[i];
    bin.PreviousFreeBlock := bin;
    bin.NextFreeBlock := bin;
  end;
  Info.BinGroupBitmap := 0;
  Info.SequentialFeedBytesLeft := 0;
  for i := 0 to MediumBlockBinGroupCount - 1 do
    Info.BinBitmaps[i] := 0;
  {$ifdef FPCMM_MEDIUMPREFETCH}
  if Info.Prefetch <> nil then
    OsFreeMedium(Info.Prefetch, MediumBlockPoolSizeMem);
  {$endif FPCMM_MEDIUMPREFETCH}
end;

{$ifdef FPCMM_SMALLLASTFREE_TEST}
procedure Fpcx64mmTestLockSmallBlockType(P: pointer; Locked: boolean);
var
  pool: PSmallBlockPoolHeader;
begin
  pool := PSmallBlockPoolHeader(
    PPtrUInt(PByte(P) - BlockHeaderSize)^ and DropSmallFlagsMask);
  pool^.BlockType^.Locked := Locked;
end;

procedure Fpcx64mmTestLockSmallRequestClasses(Size: PtrUInt;
  ClassCount: cardinal; Locked: boolean);
var
  arena, classindex, offset: cardinal;
  blocktype: PSmallBlockType;
begin
  if (ClassCount = 0) or
     (Size > MaximumSmallBlockSize - BlockHeaderSize) then
    exit;
  classindex := SmallBlockInfo.GetmemLookup[
    (Size + BlockHeaderSize - 1) div SmallBlockGranularity];
  if classindex + ClassCount > NumSmallBlockTypes then
    ClassCount := NumSmallBlockTypes - classindex;
  blocktype := @SmallBlockInfo.Small[classindex];
  for offset := 0 to ClassCount - 1 do
    PSmallBlockType(PByte(blocktype) +
      offset * SizeOf(TSmallBlockType))^.Locked := Locked;
  if classindex >= NumTinyBlockTypes then
    exit;
  for arena := 0 to NumTinyBlockArenas - 1 do
  begin
    blocktype := @SmallBlockInfo.Tiny[arena][classindex];
    for offset := 0 to ClassCount - 1 do
      PSmallBlockType(PByte(blocktype) +
        offset * SizeOf(TSmallBlockType))^.Locked := Locked;
  end;
end;

function Fpcx64mmTestSmallGetmemSleepCount: cardinal;
var
  i: cardinal;
begin
  result := 0;
  for i := 0 to high(SmallBlockInfo.GetmemSleepCount) do
    inc(result, SmallBlockInfo.GetmemSleepCount[i]);
end;

function Fpcx64mmTestSmallLastFreeCount(P: pointer): cardinal;
var
  pool: PSmallBlockPoolHeader;
begin
  pool := PSmallBlockPoolHeader(
    PPtrUInt(PByte(P) - BlockHeaderSize)^ and DropSmallFlagsMask);
  result := pool^.BlockType^.LastFreeCount;
end;

procedure Fpcx64mmTestCorruptSmallLastFreeHead(P: pointer);
var
  blocktype: PSmallBlockType;
  index: PtrUInt;
begin
  blocktype := PSmallBlockPoolHeader(
    PPtrUInt(PByte(P) - BlockHeaderSize)^ and DropSmallFlagsMask)^.BlockType;
  index := (PtrUInt(blocktype) - PtrUInt(@SmallBlockInfo)) div
    SizeOf(TSmallBlockType);
  SmallBlockInfo.SmallLastFree[index] := Pointer(1);
end;
{$endif FPCMM_SMALLLASTFREE_TEST}

{$ifdef FPCMM_SMALLPOOL_REUSE_TEST}
function Fpcx64mmTestSmallBlockType(P: pointer): pointer;
begin
  result := PSmallBlockPoolHeader(
    PPtrUInt(PByte(P) - BlockHeaderSize)^ and DropSmallFlagsMask)^.BlockType;
end;

function Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType: pointer): cardinal;
begin
  result := PSmallBlockType(BlockType)^.EmptyPoolReuseScore;
end;

function Fpcx64mmTestSmallRetainedPool(BlockType: pointer): pointer;
begin
  if PSmallBlockType(BlockType)^.MaxSequentialFeedBlockAddress <> nil then
    result := PSmallBlockType(BlockType)^.CurrentSequentialFeedPool
  else
    result := nil;
end;
{$endif FPCMM_SMALLPOOL_REUSE_TEST}

{$ifdef FPCMM_MEDIUMLASTFREE_TEST}
function TestMediumInfo(P: pointer): PMediumBlockInfo;
begin
  {$ifdef FPCMM_MS_MEDIUM}
  result := pointer(PMediumBlockPoolHeader(
    PtrUInt(P) and not MediumBlockAlignmentMask)^.Reserved1);
  {$else}
  result := @MediumBlockInfo;
  {$endif FPCMM_MS_MEDIUM}
end;

procedure Fpcx64mmTestLockMedium(P: pointer; Locked: boolean);
begin
  TestMediumInfo(P)^.Locked := Locked;
end;

function Fpcx64mmTestMediumLastFree(P: pointer): pointer;
begin
  result := TestMediumInfo(P)^.LastFree;
end;

procedure Fpcx64mmTestCorruptMediumLastFree(P: pointer);
begin
  TestMediumInfo(P)^.LastFree := Pointer(1);
end;

function Fpcx64mmTestSmallPool(P: pointer): pointer;
begin
  result := pointer(PPtrUInt(PByte(P) - BlockHeaderSize)^ and
    DropSmallFlagsMask);
end;

function Fpcx64mmTestSmallMediumInfo(P: pointer): pointer;
var
  blocktype: PSmallBlockType;
  index: PtrUInt;
begin
  blocktype := PSmallBlockPoolHeader(Fpcx64mmTestSmallPool(P))^.BlockType;
  {$ifdef FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
  index := (PtrUInt(blocktype) - PtrUInt(@SmallBlockInfo)) shr
    SmallBlockTypePO2;
  result := SmallBlockInfo.SmallMediumBlockInfo[index];
  {$else}
  result := @SmallMediumBlockInfo;
  {$endif FPCMM_MULTIPLESMALLNOTWITHMEDIUM}
end;

procedure Fpcx64mmTestLockMediumInfo(Info: pointer; Locked: boolean);
begin
  PMediumBlockInfo(Info)^.Locked := Locked;
end;

function Fpcx64mmTestMediumInfoLastFree(Info: pointer): pointer;
begin
  result := PMediumBlockInfo(Info)^.LastFree;
end;

function Fpcx64mmTestBlockFlags(P: pointer): PtrUInt;
begin
  result := PPtrUInt(PByte(P) - BlockHeaderSize)^ and
    ExtractMediumAndLargeFlagsMask;
end;
{$endif FPCMM_MEDIUMLASTFREE_TEST}

procedure FreeAllMemory;
var
  large, nextlarge: PLargeBlockHeader;
  p: PSmallBlockType;
  i, size: PtrUInt;
  list, next: PPointer;
  {$ifdef FPCMM_REPORTMEMORYLEAKS}
  leak, leaks: PtrUInt;
  {$endif FPCMM_REPORTMEMORYLEAKS}
begin
  {$ifdef FPCMM_REPORTMEMORYLEAKS}
  leaks := 0;
  writeln('FPCMM_REPORTMEMORYLEAKS_BEGIN');
  {$endif FPCMM_REPORTMEMORYLEAKS}
  p := @SmallBlockInfo;
  for i := 0 to high(SmallBlockInfo.SmallLastFree) do
  begin
    list := SmallBlockInfo.SmallLastFree[i];
    SmallBlockInfo.SmallLastFree[i] := nil;
    p^.LastFreeCount := 0;
    while list <> nil do
    begin
      next := list^;
      _FreeMem(list); // not a leak, just an unexpected context
      list := next;
    end;
    inc(p);
  end;
  p := @SmallBlockInfo;
  for i := 1 to NumSmallInfoBlock do
  begin
    p^.PreviousPartiallyFreePool := pointer(p);
    p^.NextPartiallyFreePool := pointer(p);
    p^.NextSequentialFeedBlockAddress := pointer(1);
    p^.MaxSequentialFeedBlockAddress := nil;
    {$ifdef FPCMM_REPORTMEMORYLEAKS}
    leak := p^.GetmemCount - p^.FreememCount;
    if leak <> 0 then
    begin
      StartReport;
      inc(leaks, leak);
      writeln(' small block leak x', leak, ' of size=', p^.BlockSize,
        '  (GetMem=', p^.GetmemCount, ' FreeMem=', p^.FreememCount, ')');
    end;
    {$endif FPCMM_REPORTMEMORYLEAKS}
    inc(p);
  end;
  {$ifdef FPCMM_REPORTMEMORYLEAKS}
  if leaks <> 0 then
    writeln(' Total small block leaks = ', leaks);
  {$endif FPCMM_REPORTMEMORYLEAKS}
  {$ifdef FPCMM_SMALLNOTWITHMEDIUM}
  for i := 0 to high(SmallMediumBlockInfo) do
    FreeMediumPool(SmallMediumBlockInfo[i]);
  {$endif FPCMM_SMALLNOTWITHMEDIUM}
  {$ifdef FPCMM_MS_MEDIUM}
  for i := 1 to high(MediumBlockInfoExtra) do
    FreeMediumPool(MediumBlockInfoExtra[i]);
  {$endif FPCMM_MS_MEDIUM}
  FreeMediumPool(MediumBlockInfo);
  {$ifdef FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
  if ObjectLeaksCount <> 0 then
    writeln(' Total objects leaks = ', ObjectLeaksCount);
  {$endif FPCMM_REPORTMEMORYLEAKS_EXPERIMENTAL}
  large := LargeBlocksCircularList.NextLargeBlockHeader;
  while large <> @LargeBlocksCircularList do
  begin
    size := large.BlockSizeAndFlags and DropMediumAndLargeFlagsMask;
    {$ifdef FPCMM_REPORTMEMORYLEAKS}
    StartReport;
    writeln(' large block leak of ', size, ' bytes');
    {$endif FPCMM_REPORTMEMORYLEAKS}
    nextlarge := large.NextLargeBlockHeader;
    FreeLarge(large, size);
    large := nextlarge;
  end;
  LargeBlocksCircularList.PreviousLargeBlockHeader := @LargeBlocksCircularList;
  LargeBlocksCircularList.NextLargeBlockHeader := @LargeBlocksCircularList;
  {$ifdef FPCMM_REPORTMEMORYLEAKS}
  writeln('FPCMM_REPORTMEMORYLEAKS_DONE');
  {$endif FPCMM_REPORTMEMORYLEAKS}
end;

{$I+}

{$ifndef FPCMM_STANDALONE}

const
  NewMM: TMemoryManager = (
    NeedLock:         false;
    {$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
    GetMem:           @DebugGetMem;
    FreeMem:          @DebugFreeMem;
    FreememSize:      @DebugFreeMemSize;
    AllocMem:         @DebugAllocMem;
    ReallocMem:       @DebugReallocMem;
    MemSize:          @DebugMemSize;
    {$else}
    GetMem:           @_Getmem;
    FreeMem:          @_FreeMem;
    FreememSize:      @_FreememSize;
    AllocMem:         @_AllocMem;
    ReallocMem:       @_ReAllocMem;
    MemSize:          @_MemSize;
    {$endif FPCX64MM_DIAGNOSTIC_ACTIVE}
    InitThread:       nil;
    DoneThread:       nil;
    RelocateHeap:     nil;
    GetHeapStatus:    @_GetHeapStatus;
    GetFPCHeapStatus: @_GetFPCHeapStatus);

var
  OldMM: TMemoryManager;


procedure FinalizeInstalledMemoryManager;
begin
  {$ifdef FPCX64MM_DIAGNOSTIC_ACTIVE}
  Fpcx64mmDebugVerifyHeap;
  DiagReportLeaks;
  {$endif FPCX64MM_DIAGNOSTIC_ACTIVE}
  SetMemoryManager(OldMM);
  FreeAllMemory;
  {$if defined(FPCX64MM_DIAGNOSTIC_ACTIVE) or
      defined(FPCMM_REPORTMEMORYLEAKS)}
  Flush(Output);
  {$endif}
end;


initialization
  InitializeMemoryManager;
  GetMemoryManager(OldMM);
  SetMemoryManager(NewMM);
  {$ifndef FPCMM_UNINSTALL_AT_EXIT}
  SetMemoryManagerFinalizeProc(@FinalizeInstalledMemoryManager);
  {$endif FPCMM_UNINSTALL_AT_EXIT}

finalization
  { Units pulled in while this MM is initialized finalize after this unit.
    They must keep releasing managed values through the still-live manager;
    production teardown is therefore registered with System and runs only
    after all unit finalizers.  Keep the historical early teardown only for
    controlled allocator diagnostics. }
  {$ifdef FPCMM_UNINSTALL_AT_EXIT}
  FinalizeInstalledMemoryManager;
  {$endif FPCMM_UNINSTALL_AT_EXIT}

{$endif FPCMM_STANDALONE}

{$endif FPCX64MM_AVAILABLE}

end.

