# MoonCompiler Fixes

This is a human-readable catalogue of MoonCompiler compiler and RTL repairs.
Each independent
repair answers four questions: what failed, where the root cause was, why the
narrow repair was selected, and which permanent repro protects it. The catalogue
is grouped by subsystem; each subsection or table row describes a separate
problem and a separate semantic commit. Links are relative and open directly in
GitHub.

Packaging and documentation changes are not listed here: they do not change
compiler semantics.
AUTOINLINE remains enabled in Release; the related defects were repaired at
their specific producer, optimizer, and lifetime sites.

## Dead register copies before typed x86-64 calls

A virtual constructor followed by field initialization could retain a register
copy used only for the old indirect-call operand. The CALL lifetime query
conservatively treated every register as an input. Typed call nodes now attach
their actual caller parameter registers and ABI preserved set; lifetime and
dead-copy cleanup use that information together with the current call operand.
Instruction motion stays conservative. Unknown, assembler and variadic calls
keep the previous behavior, including their implicit ABI inputs.

Local Win64/Linux linked-code controls remove one instruction and three bytes
from the constructor-and-field form; Debug and live constructor arguments stay
unchanged. Cached inline PPUs need no new format. The existing optimizer-core
and tail-forwarding gates cover retained value/address/constant wins and ABI
contracts. This code reduction is not a measured runtime speedup.

## Unused call frames after managed getter lowering

An inline chain such as `Box.GetChild.GetText <> ''` can lose its last call
during managed-result lowering, after the outgoing stack area was reserved.
Release now checks the allocated physical body before generating the prologue
and drops that unused area only when calls, stack operands, assembler and EH
requirements are absent. Real locals and stack arguments keep their frame;
normal entry/exit still preserves nonvolatile registers and unwind metadata.
Debug is unchanged. Local Win64/Linux getter, fault and loaded-PPU controls
cover the new leaf path; the existing
[`optimizer-core` gates](../qualification/optimizer-core/) preserve loop-address,
value-in-register and constant-register improvements.

## Every source directory of a `**` tree

`-Fu<dir>/**` is meant to stand for all directories of a tree, but it
skipped fifteen names outright, ignoring case: `lib`, `bin`, `build`,
`units`, `dcu`, `obj`, `backup`, `win32`, `win64`, `linux64`, `debug`,
`release`, `__history`, `__recovery`, `.git`. The names stood for build
output, and many are ordinary source directories: upstream Indy keeps every
unit under `Lib/`, so the `-Fu../Indy/**` of [Project Build](PROJECT_BUILD.md)
found none, and MoonORMot keeps `mormot.lib.*` in `lib/`, so a project with
its own mORMot in its tree silently compiled `mormot.lib.z` and
`mormot.lib.static` from the mormot next to the toolchain against its own
core. The list did not even do its job: a `-FU` directory of another name
still gave a Release build the Debug unit through `**`. Now only two kinds of
directories stay out, by what they are: hidden ones (a name starting with a
dot), which are not entered, and directories that hold compiled units but no
Pascal source - build output of any name, where a PPU would otherwise be
found instead of its source and linked as compiled with other options; the
walk goes on below them. Each directory is read once, and the duplicate-unit
warning comes from that same reading.
[`product_config_gate.py`](../qualification/build-driver/product_config_gate.py)
builds Indy's `Lib/`, a project's own `vendor/mormot/{core,lib}` and Debug
then Release through the default and through user `-FU` directories; before
the repair the first two fail and so does the user `-FU` case (the default
unit directories were protected by the name `units`).

## A stale PPU beside an unrelated source in a `**` tree

The walk excluded a directory containing PPUs only, but let it in when it
also contained any Pascal source. Unit lookup tries a PPU before a source in
each directory. Thus `bin/other.pas` let an old `bin/dupunit.ppu` win over
`src/dupunit.pas`: the program compiled and ran the old unit. Recursive paths
now supply sources only; PPUs still come from the current output directory or
an explicit `-Fu` path. The product gate builds a PPU from a source outside
the project, puts it beside an unrelated source, and proves `-Fu./**` selects
the project source in Debug and Release. Its negative control selects the old
PPU with an explicit `-Fu`.

## One order for a `**` tree from the project file and the command line

A path read from a project file or `fpc.cfg` is added in front of the list,
and the expanded tree was inserted there one directory at a time, so it came
out reversed: the last directory by name and the deepest one won - a copy in
`src/old` over its original in `src` - while the duplicate-unit warning named
the original as the one found. The command line kept the order. Both now
give the documented one, a directory before its subdirectories; the gate
builds one tree from both, with a hidden copy that must not be entered.

## A directory link back into its own tree

A directory link or junction is followed like a directory, but one leading
back into its own tree made the walk repeat the tree inside itself until the
OS refused the path - twenty rounds on Win64 at the path length limit, forty
on Linux where the kernel stops following links, each round the whole tree
again - and the compile then picked a unit path it could not open. The walk
now compares the identity of the directory a link leads to (device and
inode, volume and file index) with the directories it is inside and does not
follow such a link; every other link is followed. The gate puts a junction
or a symbolic link back to the root next to an ordinary linked directory.

## Search path entries compared as the file system compares names

Each directory added to a search path was compared with every entry already
there (`CompareText`), and the unit path is copied into the object and
library paths the same way: for a tree of N directories that is N²/2
comparisons three times - 1.5 s of every build for the 3755 directories of a
`**` over the MoonBot source tree on Win64. The comparison also ignored case
on Linux, where `Src` and `src` are two directories: from the command line
the second was dropped silently. A search path now keeps the names it holds
in a hash set, keyed as the file system compares names (as they are on
Linux, case-folded on Windows); the gate builds `Src/` and `src/` on Linux
from both the command line and the project file.

## Unit lookup only in directories that can hold a unit

A unit, or the source of a loaded unit, was looked for in every directory of
the unit path, several file names per directory; the units of the RTL and of
the mormot next to the toolchain come after the project's directories, so
each of them cost a probe of every project directory. In the MoonBot source
tree 117 of the 3753 directories under `**` hold a Pascal file. The `**`
walk now marks a directory where it saw no unit source and no compiled unit,
and the unit lookup (`search_unit`, the unit-existence check of
`registerunit`, and `FindFile` for a unit file name) passes it by; object
files, libraries and include files are still searched there. The walk and
the first probe of a directory see the same listing (the directory cache is
not refreshed during a compile either), and what the compiler writes itself
is found in its output directory before the path is searched. On that tree
the lookups fell from 284 940 file checks to 29 790 for an empty program; a
build of a program over the RTL, generics, RTTI and the mORMot core, network
and crypto units (`-Fu./**` in the project file) against main: Win64,
interleaved with a byte-identical control, full build 8.85 s against 9.57 s,
rebuild with nothing to compile 2.25 s against 2.47 s; Linux (Zen 5), the
same way, 3.31 s against 3.74 s and 0.86 s against 1.25 s. The gate reads
`-vt`: no unit file is tried in the directories of data of a tree, and an
include file in an include-only directory is still found.

## The lines of a project file in their order

`<Project>.mooncompiler` is read with the reader of the configuration, which
puts each path in front of the ones before it: its later lines were searched
first, the reverse of the same options on the command line that
[Project Build](PROJECT_BUILD.md) says the file is written as. With
`-Fu./**` above `-Fu../Common`, a unit in both was taken from `../Common`
without a word. While the project file is read its paths now go to lists of
their own in the file's order, and those go in front of the configuration's
paths afterwards; the command line still comes before both, and the
configuration's own convention is unchanged. The gate puts one unit in two
directories named on two lines: the compiler of main takes the second from
the project file and the first from the command line; now both take the
first.

## Delphi's short unit names ZLib and Zip

Delphi 12.2 finds `uses ZLib` and `uses Zip` through the unit scope `System`:
no unit has the short name, so `System.ZLib` and `System.Zip` answer. This
compiler looks a name up as it is before it tries the namespaces of `-FN`, as
Delphi does, but the toolchain installs FPC units with those short names: the
binding of an external zlib (`packages/zlib`) and paszlib's `zip`. MoonBot's
`MoonTrades` (`uses zLib`) and the websocket client (`zlib` in its FPC
branch) therefore took the FPC binding: on Win64 a program that needed
`zlib1.dll` beside it, and `TZDecompressionStream` not found at all. The
product configuration now aliases the two names (`-UaZLib=System.ZLib`,
`-UaZip=System.Zip`), as it aliases the `System.` names of the RTL units. An
alias acts on the uses clause of a source only; a precompiled unit that
depends on the FPC unit (`libpng` on `zlib`, Linux) keeps loading it by the
name its PPU records, and no installed object changes. The rule behind it -
a unit the product ships as `System.X` is what `uses X` reaches - is checked
by [`unit_scope_gate.py`](../qualification/build-driver/unit_scope_gate.py):
every capture on the product unit path fails it, and a program written as
Delphi code is written (`uses zLib, Zip`) builds with the product
configuration, runs and imports no zlib library; before the aliases it
reports these two captures on Win64 and on Linux and the program does not
build. On Linux the websocket client now links `System.ZLib` (155 of its
symbols, none of the binding's); since "One zlib in a program" below, with no
`libz` behind it.

The aliases broke the other half of Delphi's rule: a project with a unit of
its own named `ZLib` (an old Delphi-era `ZLib.pas` with `TCompressionStream`)
got `System.ZLib` instead. Delphi takes a unit by the name as written before it
tries its unit scopes; `System.ZLib` answers only through the scope. (Delphi's
own aliases do win over a project's unit of the name - `-AFoo=Bar`, and
`WinTypes=Windows` of its `dcc64.cfg`, take the aliased unit although the
project has a `WinTypes.pas`; Delphi resolves `ZLib` by scope, not by alias.)
An alias of the toolchain's configuration now gives way to a unit of the
program of that name - beside the program, in its unit output directory, in a
unit path of the command line, of the project options file or of the using
unit (`fppu.programunitexists`) - and steps over only the toolchain's own
units; an alias of the command line or of the project file holds, as Delphi's
`-A` does. `unit_scope_gate.py` builds a program with units `ZLib` and `Zip` of
its own - beside it, in a `-Fu` of its command line, in a `-Fu` of its project
file - and requires that it runs with them; the compiler before the repair
fails all three (`Identifier not found "ProjectZLibMarker"`).

A unit of the program is one the search itself would take: a `**` tree gives
its sources and never a PPU another build left in it, and a directory without
units gives none ([Project Build](PROJECT_BUILD.md)). `programunitexists`
first looked for a PPU in every directory of the program's paths; with the
`**` search that yields sources only, a `zlib.ppu` left in a `**` tree took
the name from the alias, and the search, passing that PPU by, found FPC's
`zlib` binding - `uses zLib, Zip` stopped with `Identifier not found
"TZCompressionStream"`. It now asks the program's path lists as the search
does (`TSearchPathList.FindFile`). `unit_scope_gate.py` also builds the
program with its units in a subdirectory of the project's `**` tree, and
`uses zLib, Zip` in a tree that holds `zlib.ppu` and `zip.ppu` of another
build and no source of them; the compiler before this repair fails the
latter.

## The dictionary hashers on Linux

The Linux packages are built as PIC (`-Cg`), and `Generics.Hashes` turned
`FPC_PIC` into `DISABLE_X86_CPUINTEL`: x86-64 ignored that switch until FPC
67bab6fb (2026-02, for the old assembler of OpenBSD) made it obey, and from
then on every dictionary key on Linux was hashed by the Pascal `xxHash32`
and `crc32c` was the table routine, while Win64 used the SSE4.2 instruction.
Only the i386 table code of `crc32cfast` reads data by absolute address; PIC
now takes out just that (`PUREPASCAL`), so `crc32csse42` and the hand-laid
`xxHash32` run on Linux in their SysV spelling (a string lookup 14-34 %
faster on Cascade Lake, Haswell and Zen 5). The numeric Variant record
keeps the avalanche of `xxHash32` on Linux, where it had it before
(CRC32C of consecutive numbers fills 8 buckets per hit in linear probing).
[`asm_block_routines_semantic`](../RTL-test/semantic/asm_block_routines_semantic.dpr)
and [`hasher_asm_semantic`](../RTL-test/semantic/hasher_asm_semantic.dpr)
check the values, the buffers on a page edge and the hasher each comparer
takes; `rtl_asm_layout_gate.py` requires both routines on both systems.

## Reading past the buffer in `crc32cfast`

The Pascal `crc32cfast` - the `crc32c` of a CPU without SSE4.2, a virtual
machine with the default CPU model included - read `cardinal(buf^)` for each
single byte of the unaligned head and the tail, four bytes where it needed
one: a buffer of 1-3 bytes at the end of a page before an unmapped one
faulted. It reads a byte now; the values are the same. The page-edge cases of
[`hasher_asm_semantic`](../RTL-test/semantic/hasher_asm_semantic.dpr) reach it
on such a CPU.

## Hand-written routines that move the stack without telling the unwinder

A routine written in assembler has to describe what it does to `rsp` and to
the callee-saved registers it saves (the compiler does it for its own
frames). `xxHash32` pushed `rbx` (and `rsi`/`rdi` on Win64) with nothing
told: a fault on a key that was not there hung a Linux release program at
100 % CPU and killed a debug one past its `try/except`; on Win64 it was
caught with the caller's registers wrong. The same held for `cpu.CPUID`,
`cpu.InterlockedCompareExchange128` (whose `cmpxchg16b` faults on a target
that is not 16-byte aligned; its compiler frame could not say where `rbx`
went), `Math.FloatExceptionsUnmasked`, `SHA1Transform` on Linux, the Win64
`SHA1Transform` and the `MD5Transform` of a BMI1 build, whose `.seh_`
directives stood in front of their instructions, and a Win64 `signals`
routine whose two pushes `leave` threw away. Each routine now describes its frame (Linux CFI, Win64 SEH, the
code bytes of the laid-out ones unchanged), or no longer moves `rsp`
(`FloatExceptionsUnmasked` uses the red zone or the home area; the
never-called `FloatControlState` is gone). The AT&T reader accepts
`.cfi_offset` and `.cfi_restore` as the Intel one does, so an AT&T routine
can tell a saved register.
[`hasher_asm_semantic`](../RTL-test/semantic/hasher_asm_semantic.dpr) faults
inside the hashers and SHA-1, and
[`cpu_cmpxchg16b_semantic`](../RTL-test/semantic/cpu_cmpxchg16b_semantic.dpr)
inside `cmpxchg16b`; both check the caller's registers behind the `except`.
`rtl_asm_layout_gate.py` walks every routine of the toolchain with
[`unwind_frames.py`](../qualification/performance/tools/unwind_frames.py) and
compares the stack at every instruction with its unwind information, after
its [fixture](../qualification/performance/tools/unwind_fixture.pas) shows
the walk reports silent frames.

## Win64 frames of 4 KB and more

A frame of a page or more is probed page by page. The prologue moved `rsp`
first, probed the pages above it, and put the unwind code of the allocation
behind the probes: at every probe the unwinder took the frame for 8 bytes -
a stack overflow in such a routine, the very fault the probes are for, was
unwound to a wrong caller - and `rsp` pointed below committed memory while
they ran. Windows could not deliver that overflow at all: the process died
with `STATUS_STACK_OVERFLOW` and no `EStackOverflow`, no report, where a
routine of a smaller frame raised it. The probes now go below the old `rsp`,
top down, and `rsp` moves once behind them, as MSVC's `__chkstk` does; the
allocation code holds from that instruction on. Only routines of such frames
change - 75 in 41 objects of the installed toolchain, every other object is
byte for byte the same - and each keeps its instruction count (the largest
probe takes a 32-bit displacement; a frame of more than five pages loops
with four instructions a page, as before): 59 keep their code size, 16 grow
by 32 bytes of alignment, 512 bytes in all.
[`win64_large_frame_overflow_semantic`](../RTL-test/semantic/win64_large_frame_overflow_semantic.dpr)
overflows the stack in frames of 16 and 64 KB and catches `EStackOverflow`;
`unwind_frames.py` reports none of these routines any more.

## zlib objects without unwind tables

The private zlib objects of `System.ZLib` on Win64 were built with
`-fno-asynchronous-unwind-tables`, a flag of the freestanding set that keeps
the objects free of outside symbols, which unwind tables do not need: every
zlib routine that moves `rsp` looked like a leaf to the Win64 unwinder. The
unit's allocator raises `EOutOfMemory` from inside `deflateInit`/`inflateInit`,
and a buffer that is not there faults inside `inflate`; neither exception
reached the caller's `except` intact - a debug or `-O2` program died of it
unhandled, an `-O3` one caught it with the caller's registers wrong and ran
on. The objects keep their unwind tables now (the same GCC 16.1, which
rebuilds the old objects byte for byte with the old flags). The loops are the
same; what changes is how a routine keeps the callee-saved registers - `push`
in its prologue, as SEH wants, where GCC stored them into the frame on the
paths that needed them - a cost per call, not per byte: the `zlib` program
of Pulse sees the old and the new objects within 1.5 % of each other in every
case. [`zlib_semantic`](../RTL-test/semantic/zlib_semantic.dpr) raises through
the allocator and faults inside `inflate`. The Linux objects, built the
same way, carry `.eh_frame`.
[`zlib_objects_gate.py`](../qualification/build-driver/zlib_objects_gate.py)
fails on objects without `.pdata`/`.xdata` (COFF) or `.eh_frame` (ELF), or
with a routine `unwind_frames.py` reports.

## zlib copying by single bytes

`-DZ_SOLO`, which keeps the zlib objects of `System.ZLib` free of the C
library, also defines `NO_MEMCPY` (zlib's `zutil.h`): zlib copies through its
own `zmemcpy`, and GCC's `-O2` left it a loop over single bytes (`zmemzero`
was already a 16-byte loop). It copies the output of every `inflate` call
into the window and every byte deflate reads and hands out: an exchange
websocket message cost 1.25 times what it costs on Delphi 12.2 (Pulse
`zlib/websocket-inflate-256`, 609 against 762 cycles on the host). `build.py`
now compiles `zutil.c` and the inflate side (`inflate.c`, `inffast.c`,
`inftrees.c`) at `-O3`: `zmemcpy` moves 16 bytes a step when source and
destination lie 16 bytes or more apart (the byte loop stays for pointers
closer than that, as the C code's meaning requires), a tail by 8 and single
bytes, and no library routine comes in (`-fno-tree-loop-distribute-patterns`
keeps the loops loops). The deflate side stays at `-O2` - `-O3` made the 4 KB
trade packet 2-3 % dearer - and takes zlib 1.3.1's `LIT_MEM`: literals and
distances in two buffers instead of the one buffer of three bytes a symbol
that 1.2.12 brought with the repair of CVE-2018-25032 (the pending buffer
stays clear of the symbols in both layouts). A deflate stream holds 16 KB
more for it (80 KB of pending buffer instead of 64 at `memLevel` 8). On the
host's measurement core, against the objects before: a websocket message
-27 % (948 -> 693 core cycles), the inflate of the trade packet -10 %, and
every deflate row 3-5 % cheaper (the packet -5.4 %, the market history
-5.1 %, the 1 MB candle blob -3.3 %); against Delphi the websocket row is
0.917 and the deflate of the packet 0.855. The objects grow by code only: `zutil` 2082 -> 2438
bytes, `inffast` 2465 -> 6201, `inflate` 18811 -> 21135, `inftrees` 2578 ->
4690; `deflate` and `trees` shrink a little. `zlib_objects_gate.py` fails
while `zmemcpy` or `zmemzero` has no loop that stores 8 bytes or more a step
(it takes the byte loop of the old objects for one before it looks), and the
Pulse rows of the product's forms stand against Delphi.

`-DZ_SOLO` also leaves `zutil.h` and `zconf.h` without the 4- and 8-byte
integer types (`Z_U4`, `Z_U8`), and `crc32.c` of zlib 1.3.1 without its word
type drops the braided CRC - five 8-byte words a step - for the table of one
byte a step (1 KB of table in the object where the braided code keeps 9 KB).
Since mORMot compresses through `System.ZLib` ("One zlib in a program"
below) it computes the CRC of every ZIP entry it writes there, where its zlib
1.2.11 ran a 4-byte loop, and every gzip stream pays it on every byte.
`build.py` names the types (`-DZ_U4=unsigned -DZ_U8="unsigned long long"`,
the same on both targets, `z_crc_t` 32-bit); only `crc32.o` changes. On the
host a ZIP entry of the market history is 3.7 % cheaper to write (Pulse
`zlib/zip-add-history`, 175.2 -> 168.7 core cycles a byte; mORMot's 1.2.11
wrote it for 178.2), the rows without a CRC stay where they were.
`zlib_objects_gate.py` fails while `moonzlib_crc32.o` carries no
`crc_braid_table`; on the objects before it does.

Without `UNALIGNED_OK`, which Debian and Ubuntu define for their amd64 zlib,
`longest_match` of `deflate.c` compares the window a byte at a time: four
byte compares reject a candidate of the hash chain, and a match grows a byte
a compare. With it two 16-bit compares reject a candidate and a match grows
two bytes a compare (x86-64 loads 16 bits from any address); the compressed
bytes are the same - of every deflate form of Pulse's `zlib` program, and
the same as the system `libz` writes. Once mORMot compressed through
`System.ZLib` ("One zlib in a program" below), a ZIP entry of the market
history (level 6) cost 5.3 % more on Zen 4 and 4.8 % more on Haswell than
with the system `libz` of Ubuntu (the same bytes at another address: 4.8 and
3.9 %). `build.py` builds `deflate.c` with it on Linux. On Linux the
entry is then 0.4 % cheaper than the system `libz` on Zen 4 and 1.8 % on
Haswell, the trade packet, the candle blob and the fastest level of the
history deflate 0.8-4.1 % faster than before (a C stand: every build of the
objects and the system `libz` linked into one process, core cycles by
`perf_event_open`, 31 rounds taken in turn). On Win64 (Zen 3, Pulse `zlib`,
the objects before and after at four places of the code) the entry is 3.4 %
and the fastest level of the history 4.4 % cheaper, the candle blob the same,
and the 4.6 KB trade packet 1.3-2.2 % dearer on each of its three paths; a C
stand whose streams take their buffers from `malloc` sees the packet within
0.3 % either way. The Win64 build now combines the two 16-bit candidate
checks with the original byte-by-byte match extension. In the product Pulse
program on the host, seven fresh processes per side with sibling-idle samples
and an identical-binary control put all three packet paths at 0.982-0.985 of
the full-flag object, ZIP add at 0.983, and fastest history at 1.001; the
control is 0.999-1.002. The compressed bytes and oracle match. The C stand
with both variants in one process also has ZIP/history no dearer, while the
Pascal stand with the product allocator isolates the packet gain. Only
`deflate.o` changes on Win64. `zlib_objects_gate.py` now requires the 16-bit
candidate compares and the target's byte or word match extension; the old
Win64 full-flag object fails the byte-scan check. Inflate is untouched.

## One zlib in a program

A program had up to three zlibs, chosen by unit and platform. `System.ZLib`
linked the zlib 1.3.1 objects above on Win64 and the system `libz` on Linux.
MoonORMot's `mormot.lib.z` - behind `System.Zip`, mORMot's HTTP compression
and every other deflate of mORMot, and in every program with
`System.Net.HttpClient` (`mormot.net.http` uses `mormot.core.zip`) - took
mORMot's static objects of zlib 1.2.11 on Win64, a zlib older than the repair
of CVE-2018-25032 (deflate corrupting memory on input with many distant
matches), and the system `libz` on Linux. The objects of `System.ZLib` are now
built for Linux as well (`build.py --target x86_64-linux`: the same sources and
zlib flags, position-independent with hidden symbols, their `.eh_frame` kept),
and the compiler defines `MOONCOMPILER_SYSTEM_ZLIB` on both targets, next to
`NOPATCHRTL`: MoonORMot's `mormot.lib.z` then takes its `ZLIBRTL` choice - the
one Delphi Win64 makes, the zlib of the compiler's RTL - naming `System.ZLib`
itself. A program carries one zlib, 1.3.1, and needs no zlib library;
libdeflate keeps mORMot's whole-buffer calls and checksums on Linux, as
before (it is not zlib). The symbol is the compiler's, so every build of
MoonORMot by this compiler gets it - with the product configuration or with
a gate's own options; an older toolchain, stock FPC and an upstream mORMot
(which does not know the symbol, and whose `ZLIBRTL` does not build beside
libdeflate on Linux) keep their choice, Delphi sees none of it (a dcc64 image
of a program over `mormot.lib.z` and `mormot.core.zip` is the same section for
section, build time stamps aside), and `-uMOONCOMPILER_SYSTEM_ZLIB` gives
MoonORMot's own choice back for measurements against it. `System.Zip` handed
the stream fields `PAnsiChar`, which the `PByte` fields of `System.ZLib`'s
`z_stream` (Delphi's shape) do not take; it hands them untyped pointers.
[`unit_scope_gate.py`](../qualification/build-driver/unit_scope_gate.py)
builds `uses zLib, Zip` and requires no zlib DLL or `NEEDED libz` and no zlib
build in the image other than `System.ZLib`'s, by zlib's own marks
(" deflate 1.3.1 Copyright ..."); on the toolchain before, it reports
`deflate 1.2.11, inflate 1.2.11` on Win64 and `libz.so.1` on Linux.
[`zlib_exchange`](../RTL-test/oracles/zlib_exchange.dpr) writes zlib, raw and
gzip streams and a ZIP archive with one build and reads them with another:
our Win64 and Linux builds and Delphi 12.2 read each other's files, and
Python's zlib and zipfile (the system libz of a Linux server) read all three
into the same bytes. On Win64 a program of `System.ZLib` alone links the same
zlib objects as before but the braided CRC's tables (above, 9 KB); a program
of `System.Zip` loads 6 KB less and one of `System.Net.HttpClient` 47 KB less
than with MoonORMot's own zlib (`-uMOONCOMPILER_SYSTEM_ZLIB`), mORMot's zlib
gone from them. On Linux zlib is inside the program: a program of
`System.ZLib` alone loads 66 KB more, of `System.Zip` 90 KB and of
`System.Net.HttpClient` 65 KB, and none of them needs `libz.so.1`. A
deflate stream through mORMot holds 16 KB more, as `System.ZLib`'s always did
(`LIT_MEM`: 284 448 bytes against 268 064 with zlib 1.2.11); an inflate
stream the same (7 152 bytes).

On Linux the objects are built as the distributions build zlib, without
`-DZ_SOLO`: every Linux program of this toolchain links the C library - the
system unit's PSABI exception handling links `libc` and `libgcc_s`
(`rtl/inc/psabieh.inc`) - and zlib copies and clears through `memcpy` and
`memset`, which the C library picks for the processor when the program loads,
instead of the 16-byte loops of `zutil.c`. zlib's default allocator comes
along (`malloc`/`free`) and is never called: `System.ZLib` and `mormot.lib.z`
hand every stream the program's own. The window copy after every `inflate`
call made an exchange websocket message (Pulse
`zlib/websocket-inflate-256`) 4.2-7.4 % dearer than the system `libz` on
Zen 2 and 2.2 % on Haswell (mORMot's path of it 7.5-9.0 % on Zen 2); with
the C library's copy it is -2.2..+2.7 % on Zen 2 (mORMot's path
-1.7..+2.7 %) and -0.7 % on Haswell, at four places of the code in the page,
the same bytes twice within 0.5 %. Four Linux objects change (`deflate`,
`inflate`, `trees`, `zutil`); Win64 has no C runtime to take and keeps
`-DZ_SOLO`.

## Numbers the inline assembler reads

Both readers of x86-64 inline assembler - AT&T (`raatt.pas`, `rax86att.pas`)
and Intel (`rax86int.pas`) - turned some spellings into other numbers without
a message. An inventory of 924 spellings, assembled by GNU as 2.46 for AT&T
and by Delphi 12.2 for Intel, found them; the imported base and upstream FPC
`main` have all of them. The product (RTL, packages, runtime, MoonORMot, the
Pulse programs) uses none: its objects are byte-identical before and after.

- An AT&T octal number read its first digit twice: `.byte 017` was 0x4F,
  `movl $017,%eax` moved 0x4F, `(%rax,%rcx,010)` was a wrong scale and
  `.byte 0100` a false range error. The digit is added once, and the octal
  branch also takes further zeros (`0017`).
- The readers build an expression as text and append each operand's value,
  so two operands without an operator merged into one decimal number:
  `.byte 08` (a `0`, then an `8`) was 8, `.byte 018` 18, `.byte 0b12` 12,
  `db 1 2` 12. GNU as and Delphi refuse these, and now so do the readers. A
  lone `0b`, a backward label reference for GNU as, is no longer the number 0.
- A character in an AT&T `.word`, `.long`, `.quad` or `.dc.a` was written as
  one byte, which moved everything after it. A string in a data directive is
  now the number it is in an operand (`movl $'ab'` = $6162): `.word 'a'` is
  61 00. The Intel `dw`, `dd` and `dq` wrote a string as its characters
  (`dd 'abcd'` = 61 62 63 64) where TP and Delphi store the number
  (64 63 62 61), and `dw ''` added a byte from the reader's buffer; they now
  store the number, `''` is 0.
- A string escape read a fixed width, past the end of the string: `"\x4"`
  took a character behind the string (0x4C), `"a\0"` failed on buffer
  garbage, `"\x41B"` was `AB`. `\` now takes up to three digits and `\x` all
  its hex digits, as GNU as does.
- A string longer than the 255 characters the reader holds was cut, and an
  `.asciz` of exactly 255 characters lost its terminator. The longer string
  is refused; the terminator is written apart.
- The expression evaluator used one set of ranks for both dialects, unary
  NOT among the lowest. GNU as ranks `& | ^` above `+ -` and binds a prefix
  operator to its operand, so `4+1&3` is 5 (FPC made 1) and `-(1)>>1` is
  0x7FFF...F (FPC made 0); Delphi ranks NOT between `+ -` and AND and shifts
  right arithmetically, so `not 0 and $FF` is $FF (FPC made -1) and
  `-8 shr 1` is -4. The evaluator now follows its reader. Common to both:
  `(1 or 2)` was a false error, the parenthesis being popped as an operator;
  `5-8 shr 1` was 0x8000000000000001, a binary minus being glued to the next
  number, which is right only for a prefix; `[reg-7 shr 1]` subtracted
  `-7 shr 1` instead of `7 shr 1`; a shift of 64 or more kept its value (the
  x86 count mask) where GNU as and Delphi shift everything out;
  `$8000000000000000 div -1` crashed the compiler. A negative shift count is
  refused.
- In AT&T, `!` was a bitwise not; GNU as reads it as a logical not and the FPC
  manual lists it as not supported, so it is refused, and `~`, the bitwise
  not of GNU as, is read (it was refused). A single `<` or `>` is a
  comparison for GNU as and was read as a shift; it is refused.
- The Intel reader reads an address or an operand as a sum of terms -
  registers, symbols, bracket groups, constant pieces - and evaluates each
  piece alone. NOT, AND, OR and XOR bind looser than `+`, so a piece with one
  of them outside parentheses is right only as the sole term:
  `[rax+5 and 3]` is `(rax+5) and 3`, but the reader added `5 and 3` to the
  register, and `fs:5 and 3` is `(fs:5) and 3`. Such an operand is refused, as
  Delphi does; `[5 and 3]` stays `[1]`. The factor of a scale is right only
  under `*` and `shl`: `[rcx*(4) shr 1]` is `(rcx*4) shr 1`, not `rcx*2`; it
  is refused, and so is a scale written twice, `[rax+rcx*2*2]`, which kept
  the last factor. A minus between terms outside brackets was glued to the
  next number: `[rax]-5 shr 1` was `rax-3` (Delphi `rax-2`). A constant read
  before a piece, as the offset of `TRec.Field`, was added apart:
  `TRec.Field+5 and 3` was `Field+1` where Delphi reads `(Field+5) and 3`,
  and `TRec.Field 5` their sum; the piece now continues that constant's
  expression.
- A symbol leaves the expression text in both readers, and the reader
  dropped the `+` before it, so what followed took the symbol's place:
  `.quad sym-5>>1` added `(-5)>>1` = 0x7FFF...FD instead of subtracting 2,
  `.quad sym-5&3` was `sym+3` (GNU as: `sym-1`), Intel `dq sym-5 shr 1` the
  same. The symbol's place is now 0. `5-offset x`, `5*offset x` and
  `5 offset x` were `x+5`; a symbol can only be added, and they are refused,
  as in Delphi.
- A `.single` or `.double` value beyond its range became an infinity; it is
  refused, as GNU as does.

Permanent test: [qualification/compiler-asm-numbers](../qualification/compiler-asm-numbers/README.md).

## Immediates and displacements the x86-64 encoding cannot hold

- A dword immediate was written without a range check:
  `movl $0x100000000,%eax` and `mov eax, 4294967296` encoded 0. It is checked
  like the byte and word immediates of the same encoder.
- `imul r64, r/m64, imm32` and `push imm32` sign-extend the immediate in
  64-bit mode, but their templates in `x86ins.dat` wrote it unchecked:
  `imul rax,rax,$80000000` multiplied by -2^31 and `push $80000000` pushed
  0xFFFFFFFF80000000. They now use the sign-extended code of the other 64-bit
  templates (`\254`, `\256`); the tables are regenerated.
- A displacement of a 64-bit address was cut to its low 32 bits:
  `0xFFFFFFFF(%rax)` addressed `-1(%rax)`, `0x100000000(%rax)` `(%rax)` and
  `(0x80000000)` 0xFFFFFFFF80000000. It is refused. A 32-bit address, and a
  `lea` into a 32- or 16-bit register, keep wrapping: their result is taken
  modulo 2^32, so the low half is exact. The code generator itself writes
  `leal -2654435761(%rcx),%eax` for cardinal arithmetic. Delphi 12.2 cuts
  such displacements silently; MoonCompiler does not repeat that.

Permanent test: [qualification/compiler-asm-numbers](../qualification/compiler-asm-numbers/README.md).

## Alignments the directive cannot carry

An alignment is kept in a byte that holds 1 to 64 (1 to 32 with a fill or a
limit); any other value became no alignment: `.balign 128`, `.balign 4096`,
`.p2align 7` and `align 20` aligned nothing, and `.p2align 4,0x90` - a fill
without a limit - emitted nothing at all. The readers refuse an alignment the
directive cannot carry and emit the fill-only form.

Permanent test: [qualification/compiler-asm-numbers](../qualification/compiler-asm-numbers/README.md).

## A MOV pair that stores back the value just loaded

The x86 peephole rule MovMov2Mov 1 treats `mov mem,%reg; mov %reg,mem` as a
store of the value `mem` already holds: it removes the second MOV and, when
`%reg` is not used afterwards, the first one too (Mov2Nop 6). Two premises of
the rule were false.

`%reg` dies with the pair only if nothing after the store reads it. The rule
asked `RegUsedAfterInstruction` about the load itself; the load writes `%reg`,
so the answer was "not used" for every load, and a live load disappeared. At
-O3 such a pair comes from spill coalescing: a local copy of a stack-passed
pointer shares the parameter's slot. In mORMot 2 `SyslogMessage` the copy
`start := destbuffer` became `movq 16(%rbp),%rdx; movq %rdx,16(%rbp)`; without
the load, `destbuffer^ := '<'` wrote through the stale `%rdx`, which held the
message text - a string constant in the corpus test `Debugging`, which stopped
on an access violation (Linux; Win64 gets the same shape under more register
pressure). Liveness is now asked after the store, the last reader, before the
store is removed.

After `mov (%reg),%reg` the store `mov %reg,(%reg)` goes through the new
`%reg`, not back where the value came from: `q := PPtrInt(q^); q^ :=
PtrInt(q)` in a loop lost its store at -O2 and -O3. The store is kept when its
address uses the register the load writes.

Both defects came with the imported base; upstream FPC `main` and release
`ccaa5fbaf` have them too.

Permanent regression tests:

- [RTL-test/semantic/mov_storeback_semantic.dpr](../RTL-test/semantic/mov_storeback_semantic.dpr)

## A scalar SSE store that left its place

`movapd %xmm0,%xmm1; movsd %xmm1,mem` is one store of `%xmm0` when `%xmm1`
dies with the pair, and the x86 peephole (`OptPass1_V_MOVAP`, the rule
"(V)MOVA*(V)MOVS*2(V)MOVS* 1") merges the two. Up to -O2 the pair is adjacent.
At -O3 the rule looks for the store past the instructions which do not mention
`%xmm1`, and it put the merged store at the place of the copy, in front of
all of them. Nothing was asked about those instructions.

- They may read the memory the store writes. "The difference with the value of
  the last call" is `_time := Clock; _delta := _time - FOld; FOld := _time`
  (`TPTCTimer.Delta`, packages/ptc): the code was `call Clock; movsd
  %xmm0,FOld; subsd FOld,%xmm0`, a difference of zero on every call.
- They may compute the address of the store. The plane rotation of numlib
  (`bandrd1`, `bandrd2`: `u := c*a[i] - s*a[j]; a[j] := s*a[i] + c*a[j];
  a[i] := u`) keeps `u` in a register while the second statement computes its
  indexes; the store of `u` went up with the registers of `a[i]` in its
  operand and used what they held there - the index of `a[j]`, and in
  `bandrd2` the pointer as the index.

The merged store now stays where the store stood and reads `%xmm0` there; the
copy goes. That needs `%xmm0` unchanged between the two. Where it is changed,
the store may still go up to the copy if this cannot be told from the
outside (`WriteMayMoveUp`): the registers of its address are not written
between the two, and every instruction between them is a move or integer
arithmetic over registers, constants, cells of the frame and data of a symbol
which provably do not overlap the store. Such instructions raise no exception,
so no handler sees the store done before its time. Everything else - a read
through a pointer, floating point arithmetic, a division - leaves the pair as
the code generator wrote it.

The defect came with the imported base; upstream FPC `main` (2026-09-28) and
release `ccaa5fbaf` have it: a program they compile at -O3 shows both forms.
The installed packages of the release were compiled below -O3 and carry these
routines correct. With the RTL and the packages at -O3 the three routines
above were miscompiled in the installed units (`ptc` on both targets,
`numlib` on Win64, where its reals are `Double`).

On 2026-09-29 `main` (`c02ea9482`), the -O3 RTL and packages have 114958
functions on Linux and 147498 on Win64 (`1e040aa37` had 147500).
The repair changes 8 functions on Linux and 5 on Win64. The three routines named
above got the instruction their meaning needs (one each). In
`DecodeDateDay`, `DecodeDateWeek` and `IncMonth` (Linux) the store of the
parameter now stands next to its reload and the reload is gone, one
instruction less. In six more (`DecodeDate`, `TRectF.EqualsTo`,
`PhysicalSizeToPixels`, `PixelsToPhysicalSize` on Linux,
`TXYZAHelper.FromSpectrumRangeReflect`, `TFPReportExportPDF.RenderCheckbox`
on Win64) a store stands one to four instructions lower, the instructions are
the same. `ConvUnitInc` and `ConvUnitDec` (Linux) are the case of the second
rule: the store still goes up, the code is the same. The Pulse programs and
the mORMot corpus (`mormot2tests` at -O3) have no function changed on either
target.

Permanent regression tests:

- [RTL-test/semantic/sse_store_place_semantic.dpr](../RTL-test/semantic/sse_store_place_semantic.dpr)

## A constant added in front of an operation which reads the register

`add $8,%reg; add x,%reg` became `add x,%reg; add $8,%reg` (x86 peephole,
`OptPass1Add` and `OptPass1Sub`, the rules "Add/sub swap 1a" and "1b"): the
constant goes behind the other addition or subtraction, where it may join an
address or the next constant. The rule asked that the second operation writes
`%reg`. It did not ask whether the second operation reads `%reg` - as its
source or in the address of its memory operand - and then the operation read
the register without the constant.

- A reader of a binary format steps over a block whose length stands in its
  header: `Inc(P, 8); Inc(P, PInt64(P)^)`. The length was read eight bytes in
  front of the header.
- `X := X + 3; X := X + X` gave `2 * X + 3`.

-O1 is correct; -O2 and above were wrong (at -O2 the two operations are
adjacent, at -O3 the rule finds the second one further down). The swap is now
left out when the first operand of the second operation holds the register.

The defect came with the imported base; upstream FPC `main` (2026-09-13) and
release `ccaa5fbaf` have it. No function of the -O3 RTL, the packages, the
Pulse programs and the mORMot corpus has the form.

Permanent regression tests:

- [RTL-test/semantic/add_swap_semantic.dpr](../RTL-test/semantic/add_swap_semantic.dpr)

## Two subtractions of constants with a negative sum

`sub $3,%reg; sub $-8,%reg` is one operation with the sum of the constants
(`OptPass1Sub`). Where the sum is negative the rule changes its sign and
means an addition - its message is "SUB; ADD/SUB -> ADD" - but it wrote the
opcode `sub`: `Dec(X, 3); Dec(X, -8)` subtracted 5 from `X`, `X := X - 3;
X := X - Y` with `Y` known to be -8 the same. Operands of 64 bits only: the
constant of a narrower operation is masked and never negative. -O2 and above.

The defect came with the imported base; upstream FPC `main` (2026-09-13) and
release `ccaa5fbaf` have it. No function of the -O3 RTL, the packages, the
Pulse programs and the mORMot corpus has the form.

Permanent regression tests:

- [RTL-test/semantic/sub_merge_semantic.dpr](../RTL-test/semantic/sub_merge_semantic.dpr)

## A comparison of a register with itself

`RegLoadedWithNewValue` tells the x86 peephole that an instruction gives a
register a value which does not depend on what the register held; the load in
front of such an instruction is dead and goes. `xor %reg,%reg` is the known
case, and the rule took it from the table of instructions: an opcode marked
"reads nothing when both operands are one register" (`cmp`, `sbb`, `sub`,
`xchg`, `xor`) with both operands that register. `cmp %reg,%reg` reads
nothing, and it writes nothing either: the register keeps its value, and the
load in front of the comparison is the only one the later reads have.
`xchg %reg,%reg` leaves the value too.

`if X < X`, `if X <= X`, `if X <> X` with `X` read behind the comparison, and
an inlined `Larger(Z, Z)`, lost the load of the variable: the code behind the
comparison read what the register happened to hold. -O2 for the comparisons
written in place, -O3 for the inlined one. The rule now asks that the
instruction writes its second operand and is not `xchg`.

The defect came with the imported base; upstream FPC `main` (2026-09-13) and
release `ccaa5fbaf` have it. No function of the -O3 RTL, the packages, the
Pulse programs and the mORMot corpus has the form.

Permanent regression tests:

- [RTL-test/semantic/compare_self_semantic.dpr](../RTL-test/semantic/compare_self_semantic.dpr)

## The instruction right behind a copied register

Behind `mov %src,%copy` the x86 peephole (`OptPass1MOV`) gives `%src` to the
readers of the copy and drops the move once the last reader it rewrote no
longer needs the copy. At -O3 the search runs on across branches that meet
again, and it starts behind the instruction right after the move: that one
was never asked whether it reads the copy. Two ways leave it a reader.

A comparison of the copy with its source is not rewritten (it stays
`cmp %copy,%src`, the repair of runtime loop bounds in the table below).
`Y := K; if Y < K then ... else ...; Result := Y * 1000 ...` took the wrong
branch: every relation, 64 and 32 bits, signed and unsigned, a copy made by
an inlined routine, a copy compared and then stored.

A reader that became the next instruction in the same pass, when a move
between the two went, is rewritten only on the next pass - after the move it
needed was dropped. mORMot compares values by RTTI so: `_BC_Ord` and
`_BC_Float` of `mormot.core.data` (`RTTI_ORD_COMPARE[Info^.RttiOrd](A, B,
Info, Compared)`, behind `BinaryCompare` and every comparison of an ordinal
or a real field by RTTI) read the first byte of the type through a register
nobody loaded; `BinaryCompare` of two `Integer` values stopped on an access
violation (Win64), of two `Byte` values answered -1 for 200 against 3 and
then crashed (Linux).

-O3 and -O4, Win64 and Linux; -O1 and -O2 look one instruction ahead. The
move is now dropped only when nothing between it and the last reader uses the
copy - the question the same search already asked before it dropped a move
overwritten later (Mov2Nop 3a). A skipped reader keeps the move until the next
pass rewrites it. Of the -O3 RTL, the packages, the Pulse programs and the
mORMot corpus only `_BC_Ord` and `_BC_Float` changed, with the same
instructions reading the right register.

The unchecked instruction came with the imported base (upstream FPC `main`,
2026-09-29, drops the move the same way); release `ccaa5fbaf` has the
defect.

Permanent regression tests:

- [RTL-test/semantic/copy_first_reader_semantic.dpr](../RTL-test/semantic/copy_first_reader_semantic.dpr)

## A read and a write of one memory under two names

The x86 peephole moves a read of memory to the instruction which uses the
value (`mov (%rcx),%rax ... imul $1000,%rax,%rdx` is `imul
$1000,(%rcx),%rdx`), takes a second read of a cell from the register of the
first one, merges two loads and two stores of 8 bytes into one load and one
store of 16, swaps a comparison with the move behind it. At -O3 the
instructions of such a pair need not be adjacent, and what stands between them
may write the memory. The rules asked `RefModifiedBetween`, and it counted a
write only if it went through the same address expression. A variable of the
unit written by its name was no write to what a pointer looks at; a write
through one pointer was no write to the target of another; a write through a
copy of the pointer in another register was no write at all. The merge of
moves asked `RefsMightOverlap`, which took an operand with a symbol and an
operand without one for different memory.

Forms which were wrong:

- The error code of a file operation inside a `try` block: `{$I-} Reset(F,
  1); {$I+} Err := IOResult;` gave 0 for a file which does not exist, and the
  `finally` block closed the file which was never opened. `IOResult` reads
  the code and clears it; inlined into a routine whose locals live in the
  frame, the clearing went through a second register and the read was moved
  behind it. -O3. In the installed units: `IsZip` and `UnzipFile` of
  `unzip51g` (seven places on Linux, eight on Win64).
- `TCustomDictionary.SetValue` of rtl-generics keeps the old value for the
  notification, stores the new one and notifies: the specialization in
  `chmsitemap` read the old value after the new one was stored.
- `X := P^; Cell := Cell + 5; Y := X * 1000` with `P = @Cell`; the same with
  a test of a bit. -O3.
- `Target^[0] := M[0]; Target^[1] := M[1]` with `Target = @M[1]`, a copy
  which shifts an array by one cell: the merged move read both cells before it
  wrote the first. -O2 and above.

Release `ccaa5fbaf` and upstream FPC `main` (2026-09-13) have the defect. In
the release `IOResult` is called, not inlined, and its installed units were
compiled below -O3: the forms of the first two items are not wrong there.
Delphi 12.2 is not the oracle of this class: it reads a value through a
pointer, writes the variable by its name and takes the value again from its
register (83 of 9600 generated calls); the values are those of the order of
the statements, which -O1 keeps.

One question for every rule now: memory is another memory only where that is
certain (`RefsApart`, `TX86AsmOptimizer.CellsApart`).

- A cell of the frame and data a symbol addresses.
- The data of two symbols.
- Two operands with the same registers and the same symbol whose offsets and
  sizes do not meet.
- A cell of the frame and anything addressed without the registers of the
  frame, in a routine whose frame is private (`FramePrivate`): it takes the
  address of no cell, hands the registers of the frame to nobody, has no
  handler, no implicit `finally`, no assembler block and no allocation on the
  stack, and is no outlined `finally` body.

Two address expressions which are not these prove nothing. A call, a string
instruction, a push and an instruction the table does not describe write
memory nobody names. `RefModifiedBetween` counts every write which is not
certainly to other memory; the swap of two instructions asks
`MemoryOrderFree`, a load which goes up asks `MemoryWrittenBetween`.

The moves of one assignment of a record or a set have no order among
themselves in the language. `g_concatcopy` gives the moves of one copy a
number (`taicpu.blockcopy`), and the merge of moves asks its former question
for the moves of one copy and the certain one for the moves of two statements.

Where the read may not go down, what can be kept is kept:

- an extension of the value goes up to the read (`mov (%rax),%al ... movzbl
  %al,%esi` is `movzbl (%rax),%esi` at the place of the read) when its target
  is not used in between (rule "MovMovXX2MovXX 3");
- a register of an address which is written in between by a move that
  repeats the move which loaded it counts as unchanged
  (`RegKeepsValueBetween`): the index of `Items[Kind]` is extended in front
  of each of the two reads of the element.

What changed in the code, by function, against the compiler without the
repair (2026-09-29, on `main` 37644b63d; -O3 RTL and packages: Win64 147498
functions, Linux 114958; the 27 Pulse programs with their units: Win64 27409;
mORMot corpus `mormot2tests` at -O3: Win64 22223; 26 programs and the corpus
on Linux 40437):

| | Win64 units | Win64 programs | Win64 mORMot | Linux units | Linux programs and mORMot |
|---|---|---|---|---|---|
| changed | 20 | 12 | 14 | 108 | 49 |
| shorter | 1 | 0 | 3 | 94 | 2 |
| longer | 12 | 0 | 2 | 9 | 2 |
| the same instructions in another order | 7 | 12 | 9 | 5 | 45 |

- Wrong before and correct now: `IsZip` (+3 instructions) and `UnzipFile`
  (+2 on Win64, +1 on Linux) of `unzip51g`, `TCustomDictionary.SetValue` in
  `chmsitemap` (the same instructions in the right order).
- Shorter. On Linux 93 functions copy a set or a record from a constant to
  the frame with moves of 16 bytes (-504 instructions): the former question
  compared the scale of an index the operands do not have and refused. The
  extension which goes up saves an instruction in `gzrewind` (paszlib),
  `THttpSocket.GetHeader`, `THttpSocket.GetBody` (-2) and, on Win64,
  `TDwarfReader.ParseCompilationUnits`.
- The same instructions in another order: the read stands where the
  statement stands, in front of a write which is not certainly to other
  memory, instead of behind it. `TSynSystemTime.ToIsoDate` and its three
  neighbours, `DynArrayLoadHeader`, `TFastReader.ReadVarUInt32Array`,
  `TDwarfReader.ReadLeb128` and `SkipAttr`, `TJSContext.FromVarRec`, the
  socket options of `ssockets`, `custfcgi` and `fphttpserver`,
  `unzOpenCurrentFile`, `TPasResolver.CheckTypeCastRes`,
  `TPas2jsCompiler.WriteOptions`, three routines of `ptc` and
  `TCustomIniFile.ReadTime` on Linux. The programs Pulse measures have only
  such functions changed.
- Longer, the price of the order of the statements:
  - `ERREXIT1`..`ERREXIT4`, `WARNMS1`, `WARNMS2`, `TRACEMS1`, `TRACEMS2` of
    pasjpeg (+1 to +4): `cinfo^.err^.msg_code := ...;
    cinfo^.err^.msg_parm.i[0] := ...` reads the pointer `cinfo^.err` again
    behind each store through it;
  - `TSHA512Base.Init` (Win64, +16): the unrolled loop `for I := 0 to 7 do
    Context[I] := Seed512Hash[I]` is eight statements, the target is behind
    `Self`, the source is a variable of the unit; pairs of them are no longer
    one move of 16 bytes;
  - `THttpMetrics.LoadFromReader` (+1, Linux +2), where the register of the
    extension is taken in between, and `THttpClientSocket.RequestInternal`
    (+1), where the store goes through the address of a nested record;
  - `TX11WindowDisplay.Open` of `ptc` (Linux, +7) and the outlined `finally`
    of `TFPExpressionParser.ExtractIdentifierNames` (Win64, +1): a read of a
    field stays in front of a store to a cell of a frame which is not
    private.

Permanent regression tests:

- [RTL-test/semantic/memory_order_semantic.dpr](../RTL-test/semantic/memory_order_semantic.dpr)
  also checks eight sequential overlapping array assignments: the old -O3
  vectorized adjacent pairs and read later elements before earlier writes.
- [qualification/optimizer-core/memory-order](../qualification/optimizer-core/memory-order/README.md):
  programs written by a generator in which one memory has two names, with the
  values counted from the order of the statements, at -O1 to -O4; the
  routines in which the memory is certainly another one, counted in the -O3
  object.

## A mask applied to a value which is not used

`movzwl Flags,%eax; andl $2,%eax` with `%eax` not used behind the AND: what is
left of the operation are its flags. The x86 peephole (`OptPass1Movx`, the
rule "MovxOp2Op 2") removes the extension and gives the operation the operand
the value was read from. With a TEST behind the AND the two became one TEST
of the variable. Without one the AND stayed an AND, now with the variable as
its destination: `andw $2,Flags` cleared the other bits of the variable.

The value of a mask is not used where the variable which took it gets another
value before it is read - `K := N and 2` followed by `K := ...` on every
path - and the computation stays in the code. `N := W; K := N and 2; ...;
K := 5` wrote `W and 2` to `W`: a variable of the unit at -O2, a byte and a
field behind a pointer at -O3. The rule now makes the AND a TEST whenever the
value is not used.

The defect came with the imported base; upstream FPC `main` (2026-09-13) and
release `ccaa5fbaf` have it. The generated programs of the memory-order gate
found it. No function of the -O3 RTL, the packages, the Pulse programs and the
mORMot corpus has the form.

Permanent regression tests:

- [RTL-test/semantic/and_dead_semantic.dpr](../RTL-test/semantic/and_dead_semantic.dpr)

## A loop over a local array which a nested routine replaces

At -O3 a `for` loop over a local dynamic array or string takes the pointer of
the data from the variable once, in front of the loop, and walks it
(`implicit_array_base_is_loop_invariant` in `compiler/optloop.pas`). The body
must not give the variable a new value. A call was taken to be harmless for
every local whose address is not taken and which no anonymous function
captures (`invalidatesimplicitarraybase`). A nested routine names the local of
the routine around it without either:

```pascal
procedure Swap;
begin
  L := B;
end;

begin
  L := A;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    if I = 1 then
      Swap;
  end;
```

The loop went on reading `A`. So it did after `SetLength(L, N)` in the nested
routine, which moves the array, after a new string, `Delete`, `Insert` or a
written character, when the nested routine was reached through another one,
two levels deep, through its address or from the cleanup of a nested routine,
and in the loop of a nested routine over the array of the routine around it,
which calls a routine beside it. -O1 and -O2 were correct. Release `ccaa5fbaf`
has the defect.

A call is a barrier now when it reaches a routine which writes the variable:
see [What a call does to a local](OPTIMIZER.md#what-a-call-does-to-a-local).
The first version of the repair made every call a barrier for the local of a
routine around; ten nested routines of the -O3 RTL, packages and mORMot, whose
loops call what cannot reach the array (`TStream.ReadBuffer`, `CompareText`),
multiplied the index again. It was replaced by the summary read from the
trees as parsed.

The independent -O3 comparison with `main` 12115b7ca found no changed
function in the RTL, packages, Pulse programs or `mormot2tests` on either
target; the corpus counts are recorded below with the record-field repair.

Permanent test: [qualification/optimizer-core/nested-local](../qualification/optimizer-core/nested-local/README.md).

## The fields of a local record which a loop keeps in temps

At -O3 the fields of a local record which a loop reads and writes live in
temps, so in registers, while the loop runs (`optimize_record_writes` in
`compiler/optloop.pas`): they are loaded in front of the loop and stored back
behind it. That puts the stores off until the loop is left by its end, and
nobody asked who looks at the record before:

```pascal
try
  for I := 0 to N - 1 do
  begin
    R.Sum := R.Sum + Get(I);
    R.Count := R.Count + 1;
  end;
except
  Log(R.Count);
end;
Result := R.Sum;
```

After an exception in `Get` the handler and the code behind the `try` found
`R` as it was in front of the loop. So did a `finally` block around the loop,
after an exception and after `Exit`, and the code behind the label of a `goto`
which leaves the loop. On Win64 the body of a `finally` block is a routine of
its own, which reads and writes the frame: a `finally` block inside the loop
found the old fields with no exception at all, and what it wrote to a field
was lost. -O1 and -O2 were correct. Release `ccaa5fbaf` has the defect.

A field somebody looks at stays in the record now: see
[The fields of a local record in a loop](OPTIMIZER.md#the-fields-of-a-local-record-in-a-loop).
The other fields of the same record, and the records nobody looks at, keep
their registers; so does every field when the loop cannot raise an exception
and has no `Exit`.

The continuation of a `try..except` begins at its handler, not at the start
of the routine. The first version scanned the whole routine outside the try:
a read of `R.Sum` *before* the try made the loop store `R.Sum` to the frame on
every iteration, although neither the handler nor any code after the try
could see it. The scan now follows statement tails after the try; a surrounding
loop or a `goto` keeps the conservative scan because it can revisit earlier
statements. `ShapeBeforeGuardRead` in the permanent test catches the lost
register promotion on both targets.

An implicit `Finalize` of a managed local record is another observer: on an
exception or `Exit` from the loop it runs before the delayed field stores.
The earlier repair looked only for explicit reads and gave `Finalize` stale
fields. A record with a custom `Finalize` now keeps its written fields in the
record when the loop may take such an edge. Normal, nontrapping loops still
promote them. `ManagedException`, `ManagedExit` and `ShapeManagedNoTrap` in the
permanent gate cover the values and the retained loop shape.

In the independent comparison with `main` 12115b7ca at -O3, no function
changed: RTL and packages (Linux 114958 functions, Win64 147498), 24 Pulse
programs (Linux 22062, Win64 25207), and `mormot2tests` (Linux 17857,
Win64 22223). The comparison used the same program sources and pinned
mORMot on each side.

Permanent test: [qualification/optimizer-core/record-fields](../qualification/optimizer-core/record-fields/README.md).

## ELF TLS global-dynamic call padding

With native ELF threadvars enabled at compiler build time, the x86-64 internal
assembler could insert a branch pad between the raw `66 66 48` prefixes and
`call __tls_get_addr`. This breaks the 16-byte TLSGD sequence and can fail the link with
`TLS transition ... failed`. The existing branch-pad selector now declines
calls immediately preceded by raw bytes; ordinary calls retain their layout
rule. The [TLS GD placement gate](../qualification/optimizer-core/placement/tls_gd_pad_semantic/run_gate.py)
checks the object relocations and uninterrupted sequence across call phases.
The standard product compiler currently builds without `tls_threadvars` and
uses `FPC_THREADVAR_RELOCATE`; this repair guards the opt-in ELF TLS path.

## CSE availability across Boolean evaluation modes

A value evaluated only on a short-circuit branch must not become available
to a following always-evaluated expression. The availability repair in
`optcse.pas` and the `tw41809`/`tw41809a` tests were ported from
[FPC MR !1509](https://gitlab.com/freepascal.org/fpc/source/-/merge_requests/1509)
by J. Gareth "Kit" Moreton (CuriousKit). This is an upstream contribution
integrated into MoonCompiler, not an independently developed alternative.
MoonCompiler also carries the broader
[Boolean-mode regression](../tests/test/opt/tcseshortcutavailability1.pp) and an
[inline-independent mixed-mode test](../tests/test/opt/tcsemixedbooleanavailability1.pp).
The latter and Devil's generated `flow` matrix fail when conditional-availability
protection is disabled on the current compiler, rather than depending on an
older inliner's code shape.

## Managed inline results in outlined finalizers

On Win64, a `finally` body can be compiled as a separate routine sharing its
parent's temporary allocator. Inline getters introduced managed temporaries
after the parent had already decided whether it needed implicit cleanup,
causing internal error 200405231. Outlined finalizers now undergo inline
expansion and first pass before that decision, propagating cleanup and call
requirements to the parent.

This adapts the x86-64 approach from
[fibodevy's Unleashed repair](https://github.com/unleashedpascal/compiler/commit/cc953fc0f5e1767907e3e460bbfd8c0fd8444b65).
The [regression](../tests/test/cg/tmoonfinallymanagedresults1.pp) covers getters,
strings, interfaces, managed records and arrays through normal return, `Exit`
and exceptions. Devil additionally varies result type, inline depth and the
presence of another managed local.

## Wide-character pointers in text output

`Write`/`WriteLn` rejected `PWideChar`, including `PChar` in the Unicode profile.
The compiler now converts that argument through the existing Unicode text-output
helper, preserving zero termination, text-file encoding and field formatting.
No new RTL helper is required.

The [byte-level test](../tests/test/cg/tmoontextpointer1.pp) checks UTF-8 output,
pointer aliases, nil, embedded zero, padding and single evaluation. Three
negative controls retain rejection of pointer input, ordinary untyped-pointer
output and a second formatting qualifier. Unicode field-width accounting
continues to follow the existing MoonCompiler Unicode-string output path.

## Capturing compiler-created `with` targets

A class reference produced by a constructor, getter or indexed expression used
a temporary that anonymous routines could not capture. The compiler now stores
the evaluated pointer in a lexical local, using the approach proposed by
[fibodevy in FPC MR !1424](https://gitlab.com/freepascal.org/fpc/source/-/merge_requests/1424)
and extending MoonCompiler's existing record-rvalue handling. It does not take
ownership of the object or reevaluate the producer.

A separate defect appeared when two closures captured the same compiler-created
local: lookup by its internal name missed the already-created capture field.
Reusing the symbol's capture mapping prevents duplicate fields and internal
error 2022011602.

Tests cover [object producers](../tests/test/cg/tmoonwithobjectcapture1.pp) and
[shared capture mappings](../tests/test/cg/tmoonwithcapturemapping1.pp). Devil
also checks that an object capture sees later object mutation while a returned
record capture keeps its copied value.

## Compiler-owned jump-tracking lists

Three early exits in the x86 MOV optimizer failed to release their jump-tracking
list. This leaked memory in the compiler process, not the generated application.
The ownership defect was reported by runewalsh in
[FPC MR !1549](https://gitlab.com/freepascal.org/fpc/source/-/merge_requests/1549).

All three exits now release the list. An instrumented self-build created
104,882 lists: before the repair seven remained; afterwards all were released.
The optional [compiler-resource gate](../qualification/optimizer-core/resources/README.md)
checks the allocation family's lifetime across an entire self-build.

## Preserving the result with an inherited Exit

An inline block temporarily hid fc_exit, because its own Exit jumps to a local
label. Consequently, SSA checks stopped seeing the caller function's
pre-existing exit and could treat a later inline path as the sole definition of
the return register.

The compiler now separately retains the inherited exit and considers it when
moving both register and reference results. This narrowly fixes root cause
#41558 without changing ordinary Exit handling.

Permanent regression tests:

- [tests/webtbs/tw41558.pp](../tests/webtbs/tw41558.pp)

## Domain of folded UInt64 arithmetic

An explicit UInt64(...) cast preserves the unsigned type, but arithmetic on two
explicitly typed UInt64 constants is folded in the signed Int64 domain—as
Delphi 12.2 does: an independent overload probe resolves UInt64*UInt64 to the
Int64 overload. An early repair preserved UInt64 through folding in every mode
and was disproved by that probe; preservation was removed for 64-bit types and
retained only for Int128/UInt128, which have no Delphi domain. The regression
locks down the restored Delphi behavior through RTTI for both forms.

Permanent regression tests:

- [tests/webtbs/tw41827.pp](../tests/webtbs/tw41827.pp)

## Respecting disabled range checks in for bounds

Constant for bounds are checked only when range checking is enabled. Under
{$R-}, explicit enum values outside the declared range remain valid, and the
loop must use the requested ordinal bounds. The regression contains all three
bound forms.

Permanent regression tests:

- [tests/webtbs/tw41678.pp](../tests/webtbs/tw41678.pp)

## Respecting disabled range checks while folding Succ

Folding Succ for enums, Char, and Boolean now carries the active range checking
state into the ordinal constant. This is the same language boundary as for for,
but a separate repair in a different compiler stage.

Permanent regression tests:

- [tests/webtbs/tw41678.pp](../tests/webtbs/tw41678.pp)

## Determining memory size after dereferencing a register parameter

A register parameter is first converted to a reference, and only then is the
width of the addressable memory determined. The address-register size is reset
only when no explicit data type exists; the ordinary instruction reader then
derives the actual operand size. This is a general invariant rather than a
one-off MOVSS patch.

Permanent regression tests:

- [tests/webtbs/tw41630.pp](../tests/webtbs/tw41630.pp)

## Readonly storage and results for untyped constref

An untyped constref can forward readonly storage without treating the read as
an assignment. Accepted non-reference actuals, such as function results, are
materialized for the call; existing references retain their addresses.
The valid_const check does not permit arbitrary scalar literals or arithmetic
expressions. Tests cover storage identity, direct and forwarded consumers,
integer/FP/managed results, simultaneous temporaries and rejection boundaries.

Permanent regression tests:

- [tests/webtbs/tw41766.pp](../tests/webtbs/tw41766.pp)
- [tests/webtbs/tw41766a.pp](../tests/webtbs/tw41766a.pp)
- [tests/webtbs/tw41766b.pp](../tests/webtbs/tw41766b.pp), [tw41766c.pp](../tests/webtbs/tw41766c.pp)

## Immediate normalization when narrowing x86 operations

Arithmetic folds with MOV/MOVZX narrowed the byte/word operand, but did not
convert the constant to the new immediate domain. Under O2/O3 the assembler
received a number that did not fit the narrowed encoding.

Three equivalent paths are unified in one helper that masks only a constant and
only on actual narrowing. Equal width, widening, and register paths are
unchanged; the short machine operation is retained.

Permanent regression tests:

- [tests/test/cg/tnarrowimm1.pp](../tests/test/cg/tnarrowimm1.pp)
- [tests/webtbs/tw41480.pp](../tests/webtbs/tw41480.pp)

## Excluding generic methods from legacy VMT RTTI

A published open-generic method has no callable unspecialized body, yet the
legacy writer counted and wrote it into the method table. The VMT then contained
a reference to a nonexistent generic-template symbol, and a valid Delphi class
failed at link time.

The counting and writing predicates are now symmetric and exclude
tprocdef.is_generic, as the extended-RTTI filters already do. Ordinary
published methods and actually created specializations are unaffected.

Permanent regression tests:

- [tests/webtbs/tw41410.pp](../tests/webtbs/tw41410.pp)

## Initializing static aggregates with a custom lifecycle

Implicit finalization already handled managed static variables, but the paired
initialization callback accepted only a top-level record/object. A fixed array
of advanced records could therefore receive Finalize without Initialize.

Allowing all managed arrays would add a useless startup walk over ordinary BSS
string arrays and still miss wrappers. A single value-storage predicate was
introduced, recursive only for records, fixed arrays, and old-style objects.
Reference class/interface types are deliberately excluded. An assembly negative
control proves that a large static string array is still initialized by one
zero-fill.

Permanent regression tests:

- [tests/test/cg/tarrayinit1.pp](../tests/test/cg/tarrayinit1.pp)
- [tests/test/cg/uarrayinit1.pp](../tests/test/cg/uarrayinit1.pp)
- [tests/webtbs/tw41451.pp](../tests/webtbs/tw41451.pp)

## Preserving distinct-type identity in helper keys

The key for a record/object helper was always built from the base structure's
symbol table. Several distinct record aliases shared one key, and lookup chose
the last helper registered for any one of them.

With df_unique, the key now uses the distinct type's own identity; ordinary
aliases continue to share the structural key. Registration during parsing and
lookup use one common builder, so the second diverging producer was removed.

Permanent regression tests:

- [tests/webtbs/tw41564.pp](../tests/webtbs/tw41564.pp)

## Materializing a helper instance that is not an lvalue

A record-valued field property was marked nf_no_lvalue, but helper lookup passed
the backing field directly as hidden Self. A mutating helper could then alter
the result of reading a property, whereas an equivalent getter created a value.

The existing materialization of constants/addresses was moved into the common
consumer do_member_read and accepts nf_no_lvalue. A genuine lvalue keeps its
address; a non-lvalue follows the normal assignment into a temporary value and
normal cleanup, including managed types.

Permanent regression tests:

- [tests/webtbs/tw41589.pp](../tests/webtbs/tw41589.pp)

## Preserving the with instance during generic specialization

Implicit specialization retains the actual with target, so hidden Self is not
incorrectly rebuilt from the enclosing method. One regression covers
member-scope and global with calls.

Permanent regression tests:

- [tests/webtbs/tw41711.pp](../tests/webtbs/tw41711.pp)
- [tests/webtbs/tw41712.pp](../tests/webtbs/tw41712.pp)

## Generic-type constraints in an implementation header

A Delphi-style implementation generic routine does not repeat constraints from
the member/interface declaration. While its implementation signature is parsed,
the fresh type parameter has undefineddef, and the old check rejected it before
matching it with the already validated declaration.

Deferral is permitted only for undefined generic parameters in an implementation
header when a generic declaration with the same name and arity exists. Complete
header matching remains required; standalone unconstrained generics, generic
bodies, forwards, and mismatched headers are still rejected.

Permanent regression tests:

- [tests/webtbs/tw41770.pp](../tests/webtbs/tw41770.pp)

## Deferred VMT for partial generic specialization

A specialization whose arguments still contain enclosing-generic parameters has
no generated method bodies. Phase 2 already did not place such a definition in
pending specializations, but ncgvmt still emitted a VMT with references to
nonexistent bodies.

The existing unresolved-parameters predicate was applied to tstoreddef and uses
the same invariant to defer VMT emission. VMT layout is still built to validate
overrides in partial descendants; concrete specializations and the remaining
generic paths are unchanged.

Permanent regression tests:

- [tests/webtbs/tw41788.pp](../tests/webtbs/tw41788.pp)

## An implicit generic call under unary not

In Delphi implicit-generics mode, the parser left a generic-method name as a
bare specialization, and unary not wrapped it before parsing <T>. The angle
brackets were read as comparisons, and the valid call failed at the comma.

The ordinary factor path is unchanged. Only a bare specialization before < or [
is resolved at the same precedence level before wrapping in not; the postfix
call is also completed before the next binary operator. This preserves
not/call/and grouping and does not alter non-generic not.

Permanent regression tests:

- [tests/webtbs/tw41612b.pp](../tests/webtbs/tw41612b.pp)

## Nested implicit generic specializations

The first type argument of an inline specialization remained a bare
specialization. If it was itself generic, the parent checked an incomplete node
and the adjacent >> was read by the scanner as a shift.

Before checking the parent, only that nested bare specialization is resolved,
and it uses the same temporary type context as ordinary parsing of generic
arguments. Comparisons and shifts retain their old parsing, while nested
class/array types become valid.

Permanent regression tests:

- [tests/webtbs/tw41612c.pp](../tests/webtbs/tw41612c.pp)

## Preserving absolute storage through constant propagation

An absolute conversion is a view of backing storage. Constant propagation
entered the conversion and replaced only the backing node, turning a constant
inline argument into a numeric address instead of materialized memory.

Propagation stops at the absolute boundary, as CSE already does. This preserves
the defining assignment; ordinary temporary constants and all non-absolute
conversions remain optimization candidates.

Permanent regression tests:

- [tests/test/cg/tabsolute2.pp](../tests/test/cg/tabsolute2.pp)

## Keeping distinct absolute views in memory

An absolute variable and its backing symbol can have one register class but
different field layouts. If both are held as independent register variables,
inline partial writes operate on different snapshots and lose fields.

Different type definitions are now considered incompatible for register
promotion, and the shared storage remains in memory. The other absolute paths
are unchanged.

Permanent regression tests:

- [tests/test/cg/tabsolute1.pp](../tests/test/cg/tabsolute1.pp)

## Signed constant division below `aWord` width

When calculating the magic value for signed division, the sign contribution
remains in the operand's actual N-bit domain. The deterministic regression
checks div, mod, and reverse recomposition.

Permanent regression tests:

- [tests/test/cg/tmoddiv7.pp](../tests/test/cg/tmoddiv7.pp)

## Preserving a record field whose address escapes to an external call

A field passed as var, out, or constref is excluded from O3 field promotion: the
call needs the original storage address; otherwise it receives a temporary while
the loop continues reading a stale register.

Storage-preserving conversions are tracked by the canonical
TTypeConvNode.retains_value_location, rather than a new copy of the type
comparison. This covers same-size views and provenance after inlining without a
separate exception list.

Permanent regression tests:

- [tests/test/cg/tconstrefvirt.pp](../tests/test/cg/tconstrefvirt.pp)
- [tests/test/cg/trecordloop1.pp](../tests/test/cg/trecordloop1.pp)
- [tests/test/cg/trecordloop2.pp](../tests/test/cg/trecordloop2.pp)

## Delphi width for floating-point calculations

Floating expressions are evaluated at the target Delphi width, explicitly wider
operands are retained, untyped real literals receive Delphi width, and
intrinsics follow the measured result rules. This is a separate model of
floating-point computation; the Abs(Currency) repair is not mixed into it.

Permanent regression tests:

- [tests/test/cg/taddreal4.pp](../tests/test/cg/taddreal4.pp)
- [tests/test/cg/tintrinsicwidth1.pp](../tests/test/cg/tintrinsicwidth1.pp)

## Abs(Currency) over a scaled integer

Abs commutes with the scale of Currency, so the operation is performed directly
on the exact scaled Int64, without an intermediate floating-point value. The
same commit contains an exact model over 100000 values.

Permanent regression tests:

- [tests/test/cg/tabscurrency1.pp](../tests/test/cg/tabscurrency1.pp)

## BSF/BSR semantics for zero input

For a possibly zero input, the result no longer depends on whether a preloaded
destination survived register allocation: a zero-flag fallback is used. For a
proven nonzero input, the scan remains one instruction.

Permanent regression tests:

- [tests/test/cg/tbsx3.pp](../tests/test/cg/tbsx3.pp)

## Managed and aliased semantics during inlining

A call is not inlined when a managed by-value argument requires its own copy:
an ordinary inline temporary lives as the caller, not as the callee. Safe
read-only managed parameters remain permitted.

Ordinary managed locals (String, interface, dynamic array, and records without
custom Initialize) may be inlined: they become caller temporaries, and their
reverse-order cleanup wraps exactly the inlined body and runs on normal/Exit/
exception paths at the callee return point. A custom managed record with custom
Initialize remains outside the inliner. A native temporary is initialized in
the caller prologue, so inlining would otherwise observably move Initialize
ahead of statements before the call. This is a narrow boundary, not a general
AUTOINLINE ban for managed locals.

A const-by-reference call with non-local storage remains a call because current
CSE cannot retain that alias across mutation inside the callee. Focused tests
lock down lifecycle and aliasing.

Permanent regression tests:

- [tests/test/cg/tautoinline1.pp](../tests/test/cg/tautoinline1.pp)
- [tests/test/cg/tautoinline3.pp](../tests/test/cg/tautoinline3.pp)
- [RTL-test/semantic/inline_managed_locals_semantic.dpr](../RTL-test/semantic/inline_managed_locals_semantic.dpr)

## Wrapping folded integer arithmetic with overflow checking disabled

After AUTOINLINE, constant propagation could see a wider intermediate and report
a compile-time overflow even though unchecked runtime arithmetic must truncate
to the declared result width.

For integers under {$Q-}, the low bits are retained and a typed constant is
created; ordinary range adaptation performs the same wrap. Checked arithmetic,
pointers, and non-integer ordinals are unchanged. The regression covers +, -,
and *.

Permanent regression tests:

- [tests/test/cg/tautoinline2.pp](../tests/test/cg/tautoinline2.pp)

## Retaining an untyped storage view through inlining

An assignment-side cast from untyped var/out is a view of caller storage, so the
declared parameter size need not match the view type. AUTOINLINE replaced the
formal load with the actual argument and lost provenance; repeated type checking
then rejected valid low-level Delphi code.

A narrow flag is stored on the conversion node, copied and serialized by the
standard PPU mechanism, and considered only where formal storage already retains
the same lvalue. Typed parameters still use ordinary size checking; the O3 test
also proves that the call did not become noinline.

Permanent regression tests:

- [tests/test/cg/tautoinline4.pp](../tests/test/cg/tautoinline4.pp)

## Replacing inline parameters in hidden receiver nodes

Cross-unit autoinlining copied a qualified method call together with
call_self_node/call_vmt_node, but the common AST walker does not visit these
cached hidden trees. The consumer PPU retained the producer Self symbol without
a location, causing internal error 200109092.

During parameter replacement, only the two hidden receiver trees are visited;
the global optimizer walker is unchanged. The two-pass PPU regression is
mandatory: building in one process kept the producer symbol table alive and
masked the defect.

Permanent regression tests:

- [tests/test/cg/lab_002_unicode_const_pointer_unit.pas](../tests/test/cg/lab_002_unicode_const_pointer_unit.pas)
- [tests/test/cg/tautoinline5.pp](../tests/test/cg/tautoinline5.pp)

## Procedural types copied from a routine

The type of `@Routine`, and of the field in which a function reference keeps
a method passed with `@`, is a copy of the routine's definition. A call
through such a type is an indirect call of whatever routine the variable
holds, but the copy kept what the routine says about its own body, options
the language rejects on a procedural type, and calls through the type were
compiled by them (upstream FPC `main` has the same copy and the same
readers):

- `inline`: the inliner selects calls by the mark and then reads fields that
  only a routine has, so a call through such a type stopped the compiler: an
  access violation while reporting the call as not inlined, internal error
  200412021 in release 1.0.0. An explicitly inline routine failed at every
  optimization level; at -O3 AUTOINLINE makes any small routine one, as in
  `packages/vcl-compat/tests/utthreading.pp`, which passes a small method
  with `@` to a `reference to` parameter.
- `noreturn`: every call through the type was taken for one that never
  returns, whatever routine the variable held, and -O3 then folded the
  statements after the call with the values from before it: a loop summing
  through `Q := @Stop; Q := @Go; Q()` returned 1 instead of 6. For small
  routines the inline mark had hidden this behind the crash above.
- `internconst` (`Odd`, `Sqr` and `Swap` fold a constant argument by an
  intrinsic number of the routine): a call through the type with a constant
  argument read that number off the procedural type, internal error 88 at
  every level.
- `assembler`: the type was taken for one of a `safecall` routine without the
  safecall wrapper, and a call through it did not check the HRESULT, so when
  the variable held another `safecall` routine, its failure was lost instead
  of raising the exception.

The copy now drops these options together with the import names, and a call
through such a type is compiled like every other indirect call.

An intrinsic of the compiler (`internproc`: `Abs`, `Sqrt`, `Sin`, `PopCnt`
and others) is expanded in place at every call and has no body. Its address
was taken without an error: a call through it read the intrinsic number
beyond the procedural type (`Fatal: Unknown internal procedure number` with
a different number on every run), and `P := @Abs` into an untyped pointer
failed only at link time. Taking that address is now a compile-time error,
as in Delphi 12.2, and only a call of the routine itself is expanded as an
intrinsic.

The Delphi form `Run(Method)` was not affected: its function reference calls
the method directly. The objects of the RTL, the packages and the Pulse
programs are byte-identical before and after on Win64 and Linux.

Permanent regression tests:

- [qualification/suite/tests/smoke/procvar_copied_from_routine.pas](../qualification/suite/tests/smoke/procvar_copied_from_routine.pas)
- [qualification/suite/tests/smoke/procvar_of_intrinsic_rejected.pas](../qualification/suite/tests/smoke/procvar_of_intrinsic_rejected.pas)
- `run_service_regressions_gate` compiles
  [packages/vcl-compat/tests/utthreading.pp](../packages/vcl-compat/tests/utthreading.pp) at -O3

## A method, a procedure variable or a routine given to `reference to`

Delphi code gives a method to a function reference without `@`
(`P := C.Step`, `TTask.Run(DoWork)`), and Delphi 12.2 then behaves as if the
anonymous method `procedure(A) begin C.Step(A) end` were written: the object
expression is evaluated at every call, and the locals it reads are captured.
The same holds there for a procedure variable, an event field, a property
and a function result given the same way. The Invoke the compiler builds in
the capturer did evaluate the object at the call, but nothing it read was
captured (upstream FPC `main` has the same code; its issue #39765, a local
object, is open since 2022):

- The search for Self and for the symbols to capture ran after the object
  expression had been moved into the Invoke, over the emptied node, and took
  only locals of nested routines. An object in a local variable, a
  parameter, a local record, an inline or `absolute` variable, a `with`
  target, an array element with a local index, a type-helper receiver or a
  field of an unrelated class was read from the frame of another routine: an
  access violation, or silently another value (a parameter at -O3, garbage
  from a type helper, a local record left unchanged). The Self of the current
  class was captured only by a heuristic added upstream for #39978. The
  callback declared `pd: tprocdef absolute arg` but was given `@pd`, the
  address of the variable; it had simply never found anything.
- The Invoke and its interface were named after the declaration of the method
  or of the variable, so in one routine a second conversion of the same
  method with another object, or of the same variable after it changed,
  reused the first Invoke: `P := A.Step; Q := B.Step` called A twice. Two
  overloads of one routine shared the name and got the interface of the first:
  `Q := Put` for `Put(const S: string)` called `Put(Integer)` with the address
  of the string.
- An event field, a property or a function result given to a reference
  stopped the compiler (internal error 2022022102): the name was looked for
  among loaded procedure symbols only.
- The interface of the reference was put into the symtable that declares the
  method or the procedural type. A class of another unit, compiled already,
  never emitted it: the program did not link (`Undefined symbol:
  IID_$..._$FUNCREFINTF_...`). A class of the interface of the unit being
  compiled has its references written when the interface ends; a conversion
  in the initialization of the unit, whose capturer the unit writes into its
  .ppu, made the compiler write the new entry without them (internal error
  2019022201).
- In the main block of a program and in the initialization of a unit -O2
  keeps a variable no other routine reads in a register; the Invoke, another
  routine, read it from memory the register never reached: another object or
  an access violation.

Every local, parameter and Self the moved expression reads is now captured
as an anonymous function captures it, and what cannot be captured - a var or
out parameter, the result, a call of a nested routine - is refused as Delphi
refuses it (E2555) instead of reading a foreign frame. A conversion whose
Invoke evaluates an expression gets an Invoke of its own; a routine without
an object keeps one shared Invoke, and an overload gets the next interface
name. In Delphi mode a procedure variable is read at every call, as Delphi
does. In the FPC modes it keeps the value it has at the conversion, the
documented FPC behaviour, now per conversion. The interface of what is
declared at unit level in another unit or in the interface of this one goes
into the implementation of the unit that converts; what is declared in a
routine keeps it in the routine's scope. A variable of the program or of a
unit the moved expression reads stays in memory, as for a read from a nested
routine.

The RTL, the packages and the Pulse programs contain no such conversion
besides one objfpc pair in `TComponent.GetObservers`, whose code does not
change; their objects are byte-identical before and after.

Permanent regression tests:

- [qualification/suite/tests/smoke/funcref_value_sources.pas](../qualification/suite/tests/smoke/funcref_value_sources.pas)
  (one source with Delphi 12.2: every source of the object and of the
  procedure variable, overloads, two conversions in one routine)
- [qualification/suite/tests/smoke/funcref_value_snapshot_objfpc.pas](../qualification/suite/tests/smoke/funcref_value_snapshot_objfpc.pas)
- [qualification/suite/tests/smoke/funcref_value_var_param_rejected.pas](../qualification/suite/tests/smoke/funcref_value_var_param_rejected.pas)
- [qualification/suite/tests/smoke/funcref_value_nested_call_rejected.pas](../qualification/suite/tests/smoke/funcref_value_nested_call_rejected.pas)
- [qualification/suite/tests/smoke/funcref_value_units.pas](../qualification/suite/tests/smoke/funcref_value_units.pas)
  with its two units (one source with Delphi 12.2: another unit's class, the
  class of a unit's interface in its initialization, the main block at -O2)

## `safecall` routines written in assembler

On Win64 and on Linux x86-64 a `safecall` routine runs in an implicit frame
that turns an exception into an HRESULT, and it returns the HRESULT of that
wrapper. Since 2019 (upstream r43578) the wrapper was not built for an
`assembler` body, but the implicit frame was still requested by the calling
convention, and the Win64 exception path asked the convention too: its
handler stored into a result variable that did not exist, and the compiler
stopped with an access violation on every `safecall; assembler` routine on
Win64. On Linux a Delphi-mode asm body without locals was refused
(`NOSTACKFRAME but local stack size is 8`), and in the FPC modes a direct
call did not check the HRESULT that a call through a procedure variable of
the same type checked.

Delphi 12.2 wraps a `safecall` routine written in assembler like any other:
the body runs in the frame, an exception in it becomes an HRESULT that the
caller raises as `ESafecallException`, and a normal exit returns S_OK - the
value the body leaves in EAX is not the result. The wrapper is now a property
of the calling convention, as there: an assembler body gets it too, and the
return value is loaded from the wrapper's variable. No routine of the RTL,
the packages, MoonORMot or MoonBot is `safecall; assembler`; the objects are
byte-identical before and after.

The same wrapper is required when Delphi mode infers `assembler` from an
`asm` body without that directive. An explicit `nostackframe` conflicts with
the wrapper's local HRESULT and is now rejected at the declaration; it used
to stop code generation with an internal error.

Permanent regression tests:

- [qualification/suite/tests/smoke/safecall_assembler.pas](../qualification/suite/tests/smoke/safecall_assembler.pas)
  (one source with Delphi 12.2)
- [qualification/suite/tests/smoke/procvar_copied_from_routine.pas](../qualification/suite/tests/smoke/procvar_copied_from_routine.pas)
  (the `assembler` form, now on Win64 as well)
- [qualification/suite/tests/smoke/safecall_nostackframe_rejected.pas](../qualification/suite/tests/smoke/safecall_nostackframe_rejected.pas)
  (an explicit frame conflict gets a source diagnostic)

## A `reference to` type written inside a generic

A function reference type written in the var section of a method of a
generic class or of a generic routine (`var F: reference to function:
Integer;` - FPC syntax: Delphi 12.2 declares method reference types by name
only) became, in each specialization, an interface marked as a specialization
but without the generic it specializes. An anonymous function of a
specialization carries the same mark without a generic by design, and the
rule that takes two specializations of one generic with equal parameters for
equal types (`compare_defs_ext`) took the two missing generics for one: the
assignment of the anonymous function to the reference was a conversion
between equal types and was dropped, so the reference got the first bytes of
the function's code and `fpc_intf_assign` crashed on them. A call through the
reference stopped the compiler in the visibility check, which requires the
generic of a specialization (internal error 2024041201). A named reference
type and the same code outside generics were not affected; upstream FPC
`main` has the same code.

Such an interface is no longer marked as a specialization: it is a type of
the specialized body, as a local record there is. The objects of the RTL,
the packages and the Pulse programs are byte-identical before and after.

Permanent regression test:
[qualification/suite/tests/smoke/generic_inline_funcref.pas](../qualification/suite/tests/smoke/generic_inline_funcref.pas)
(the named types checked against Delphi 12.2, the inline types against them)

## A method of a value given to a method pointer

A method pointer to a method of a value - a record, an old-style object, the
type a helper extends (`M := R.Step`, `Call(I.Bump)`, `@R.Step` in the FPC
modes) - carries the address of the value as Self, and every call through the
pointer changes the value itself. Delphi 12.2 keeps a variable, or a part of
one, in its own storage for that, and a value that is no variable (a function
result, an expression, a record constructor) in a temporary, one per place in
the source: that of a routine or of the main block lives until it ends, that
of the initialization of a unit with the variables of the unit, until its
finalization has run. The load that
builds the pointer never said that its receiver must be in memory - a call of
the method says it through the Self parameter, `@` says it for its operand -
and the code generator took the receiver where it found it:

- at -O2 and -O3 a record the size of a register, a record with one field, a
  record parameter or a variable of a helper's type was kept in a register: a
  record of 1, 2 or 4 bytes stopped the compiler (internal error 200306031), a
  record of 8 bytes gave Self its value instead of its address (an access
  violation, or another object), a Double and a field of a record in a record
  stopped it too (internal error 200610311) - in a routine, in the main block
  of a program, in the initialization of a unit, and for a var, out or
  `[ref]` parameter once the routine was inlined;
- a function result at any level: a small one was in a register (internal
  error or access violation), a large one in a temporary freed at once, which
  the next temporary took (`M := MakeBig(1).Step; X := MakeBig(7).V; M(2)`
  changed the second value);
- that calls through the pointer write the value was not known: an inlined
  routine used the caller's variable for its value parameter, and the pointer
  changed the caller's variable (already at -O-); at -O3 an inlined getter
  gave its field instead of a copy.

Upstream FPC `main` has the same code.

The load now keeps the value in memory before the pointer is built: a
variable, or a part of one, is marked as `@` marks its operand - not a
register, its address taken, written - and a value that is no variable is
first stored in a hidden variable, found again by its place in the source, so
that the body of an unrolled loop keeps one: a local of the routine, a static
in a block of the main block (whose statics the main block finalizes at its
end), a static of the unit in its initialization and finalization. A unit
whose first managed variable is such a static gets its finalization, which
the compiler used to decide before the code of the initialization was made.
The code generator
asks the same question (`method_self_is_address`), and such a receiver met in
a register is an internal error instead of a wrong Self. Delphi refuses `@` of
a method (E2036) and a typecast of a method to `TMethod` (E2089); the FPC `@`
form stays, and the typecast is refused here too.

The RTL, the packages, MoonORMot (mormot2tests) and MoonBot contain one such
pointer: `reader.OnEntity := @ProcessEntity` in the methods of the object
`TLoader` of fcl-xml's `xmlread`, whose Self is a var parameter already in
memory. Its code does not change; `xmlread.ppu` records that the address of
that Self is taken. All objects of the RTL, the packages and the Pulse
programs are byte-identical before and after.

Permanent regression tests:

- [qualification/suite/tests/smoke/method_value_receivers.pas](../qualification/suite/tests/smoke/method_value_receivers.pas)
  with [its unit](../qualification/suite/tests/smoke/method_value_receivers_unit.pas)
  (one source with Delphi 12.2: records of every register size, parameters,
  parts of values, values that are no variable, objects, helpers, the main
  block, the initialization of a unit, inlining, reads after calls through
  the pointer)
- [qualification/suite/tests/smoke/method_value_receivers_objfpc.pas](../qualification/suite/tests/smoke/method_value_receivers_objfpc.pas)
  (the `@` form)
- [qualification/suite/tests/smoke/method_value_lifetime.pas](../qualification/suite/tests/smoke/method_value_lifetime.pas)
  with [its unit](../qualification/suite/tests/smoke/method_value_lifetime_unit.pas)
  (one source with Delphi 12.2: when the value that is no variable is
  finalized - a routine, a loop, the main block, the initialization of a unit)
- [qualification/suite/tests/smoke/method_value_implicit_finalization.pas](../qualification/suite/tests/smoke/method_value_implicit_finalization.pas)
  with [its unit](../qualification/suite/tests/smoke/method_value_implicit_finalization_unit.pas)
  (the unit has no explicit finalization: its hidden managed value is released
  after the main block, including when the program loads the compiled PPU)

## What the finalization of the units writes

A program whose standard output or error goes to a file or a pipe lost what
the finalization sections of its units wrote - a summary, a verdict, the
last lines of a log - on every way out: the end of the program, `Halt` in
the main block or in a finalization, an exception in either, `ExitProc`;
`Output` and `ErrOutput` alike. On a console the same text appeared: the RTL
writes a console at every line, a file only when its buffer is full or
flushed. `InternalExit` (rtl/inc/system.inc) flushed the standard files once,
before `FinalizeUnits`, and never after it. Delphi 12.2 closes `Input`,
`Output` and `ErrOutput` in the finalization of System, the last unit
finalized. Upstream FPC `main` has the same order.

`InternalExit` now flushes the standard files a second time once the units
are finalized; the first flush stays, so what was written before is out
before a finalization can crash or hang. A `Halt` or an exception inside a
finalization enters `InternalExit` again, which finalizes the remaining
units and flushes after them. The memory manager keeps its own flush after
the leak report it writes later. A GUI program on Windows has no standard
output; its message box of errors is shown by `system_exit`, as before.

An I/O error left pending at the exit (`{$I-}` code that does not look at
`IOResult`, in the main block or in the last finalization) no longer keeps
the standard files from being written. `Flush` returned at once while
`InOutRes` was not 0; now it writes the buffer whatever is pending, as
Delphi's `Close` and `Flush` do, and leaves the pending error as it is. On
Linux the low-level write set `InOutRes` to 0 when it succeeded, which would
have erased the pending error on the way; it now sets it only on failure, as
on Windows.

The second flush is one call in `InternalExit`, inside its aligned slot on
Win64 and Linux.

Permanent regression tests:

- [qualification/suite/tests/smoke/finalization_output.pas](../qualification/suite/tests/smoke/finalization_output.pas)
  with [its unit](../qualification/suite/tests/smoke/finalization_output_unit.pas)
  (one source with Delphi 12.2; the gates run it with its output in a file:
  the finalization writes the verdict)
- [qualification/suite/tests/smoke/io_error_exit_flush.pas](../qualification/suite/tests/smoke/io_error_exit_flush.pas)
  with [its unit](../qualification/suite/tests/smoke/io_error_exit_flush_unit.pas)
  (one source with Delphi 12.2: the finalization writes the verdict and then
  leaves an I/O error pending; FPC forces buffering so a Linux pipe cannot
  auto-flush the verdict before the exit flush)

## I/O after an error left pending

An I/O routine that fails under `{$I-}` leaves its error in `InOutRes` until
`IOResult` is called. The RTL kept the Turbo Pascal rule that every I/O
routine returns at once while an error is pending: `Write` and `WriteLn` to
any file and to the console, every `Read`, `Eof` and `Eoln` (which answered
True), `Reset`, `Rewrite`, `Append`, `Flush`, `Close`, `Erase`, `Rename`,
the untyped and typed file routines and `MkDir`, `ChDir`, `RmDir`. One
`IOResult` forgotten after a failed `Reset` silenced everything the thread
wrote and read after it; `Eof` of an untyped file answered False, so a
`while not Eof(F)` loop over `BlockRead` never ended. Delphi 12.2 has no
such rule (oracle: every routine above, one program under both compilers):
each routine does its work, a pending error survives the routines that
succeed, and a routine that fails puts its own error in its place.

The routines no longer return on a pending error. Where the RTL judged a
call of its own by `InOutRes` - the open of a text file (a failed one is
closed), the reading of the next block of a text file, `Rename`,
`BlockWrite` and `BlockRead` without a count (a short count is error 101 or
100), the "file not found" that `ChDir` reports as "path not found", the
device check that makes the console write every line - it now looks at that
call alone, and a pending error comes back when the call succeeds. `Write`
of an enumeration value cleared a pending error when it succeeded; it no
longer touches it. On Linux the low-level routines set `InOutRes` to 0 when
they succeeded, which erased a pending error on the way; they now set it
only on failure, as on Windows. So does the text driver of `AssignStream`
(fcl-base `streamio`, used by the fcl-db exports and the resource reader of
`fpcres`), whose every function started with `InOutRes:=0`: the flush at the
end of each `Write` statement erased a pending error.

What changes for code written for the old rule: code that runs several I/O
routines under `{$I-}` and asks `IOResult` once at the end sees the error of
the last routine that failed rather than the first, as in Delphi (a failed
`Rewrite` followed by `Write` and `Close` reports 103, file not open); the
routines after the failed one are done - a `Rewrite` of the destination after
a failed `Reset` of the source empties the destination, as in Delphi, where
the old rule skipped it and the destination kept what it held; and
code that asks `IOResult` right after its own `Reset` or `Rewrite` without
clearing an error left before still blames its own call for it, as before,
but the call has now been done - the file is open, or created.

The compiler's `TCFileStream.SetSize` used the old rule to skip `Truncate`
when its preceding `Seek` failed. With the new rule, `SetSize(-1)` at position
2 truncated an 8-byte file to 2 bytes while still reporting the seek error.
It now reads `IOResult` after `Seek` and truncates only on success; a successful
resize still truncates and reports its own result. The regression builds the
actual compiler stream class on both targets in O-, O2 and O3.

Permanent regression tests:

- [qualification/suite/tests/smoke/io_pending_error.pas](../qualification/suite/tests/smoke/io_pending_error.pas)
  (one source with Delphi 12.2: every routine above with an error pending,
  the pending error checked after each; the verdict itself is written with
  an error pending)
- [qualification/suite/tests/smoke/compiler_cstream_setsize.pas](../qualification/suite/tests/smoke/compiler_cstream_setsize.pas)
  (a failed seek keeps the file intact; a successful resize still works)

## One I/O check per Read or Write statement

With I/O checks on (`{$I+}`, the product profile's `-Ci`), the compiler
checked `InOutRes` after every item of a `Read` or `Write` statement, so a
statement stopped at the item where an error was found. Delphi 12.2 checks
once, after the statement (oracle: text and typed files, an error left
pending before the statement): `Write(F, 'a', 1, 'b')` writes all three and
then raises `EInOutError`, `Readln(G, I, J)` stores both numbers and moves
to the next line, `Write(T, A, B, C)` on a `file of Integer` writes three
records. Here the statement stopped after its first item; a number read
into a byte was read but not stored, since the check stood between the read
and the assignment, and the next statement went on in the middle of the
line.

The items of a statement no longer get a check of their own; the end call
of a text file (`fpc_write_end`, `fpc_writeln_end`, `fpc_read_end`,
`fpc_readln_end`) and the last item of a typed file carry the one check of
the statement. The exception and its code are the same; every item has been
done when it is raised. A statement of N items calls `fpc_iocheck` once
instead of N+1 times.

Permanent regression test:

- [qualification/suite/tests/smoke/io_check_statement.pas](../qualification/suite/tests/smoke/io_check_statement.pas)
  (one source with Delphi 12.2: text write and read, a byte read through the
  compiler's temporary, typed write and read, and an error in the first item;
  MoonCompiler also checks its `WriteStr` and `ReadStr` forms)

## The exit code of an unhandled exception

A program ended by an exception that nobody handled exited with code 217;
with Delphi 12.2 the same program exits with 1 (oracle: an exception of any
class, an access violation, `Abort` in the main block, an exception in a
thread of `BeginThread`). Services and scripts read that code. Delphi's
`SysUtils.ExceptHandler` shows the exception and calls `Halt(1)`; System's
own fallback, when no handler is installed or the installed one returns, is
runtime error 217. Here `SysUtils.CatchUnhandledException` wrote the report
and returned, and System ended the program with 217.

`CatchUnhandledException` now ends with `Halt(1)`, as `ExceptHandler`; the
217 of System stays for a handler that returns and for a program without
SysUtils - with the product runtime there is none, the compiler adds the
monitor unit (`fpwinmonitor`/`fpmonitor`) and SysUtils with it to every
program. Code 1 is also what a program's own `Halt(1)` gives; a check that
has to tell the two apart reads the report, whose first line is "An
unhandled exception occurred at". The reporting gate
(`run_reporting_gate.py`, which expected 217) does so now, and so does the
mORMot stage of the runner: an exit with 1 and nothing but environment
failures in the report passes only when the run log holds no such report
(`mormot_suite_result`). The report is also written
without I/O checks: with an I/O error left pending, its first `Writeln`
raised `EInOutError` inside the handler, so the program printed "File not
found" from the handler instead of its own exception (Delphi 12.2 loses both
the report and the exit code there). A handler installed on top of it, such
as `Moon.Diagnostics`, calls it after its own report and exits with 1 too.

An exception raised in the initialization or finalization of a unit also
ends with 1 and its report here. Delphi prints "Runtime error 217" there -
its `InitUnits` and `FinalizeUnits` first finalize the remaining units,
SysUtils and its handler among them, and re-raise - and then crashes with
an access violation, so a script sees 0xC0000005; that path is not copied.

Permanent regression test:

- [qualification/suite/tests/smoke/unhandled_exit_code.pas](../qualification/suite/tests/smoke/unhandled_exit_code.pas)
  (one source with Delphi 12.2; the gates run it in the modes main, thread
  and pending and expect exit code 1 and the exception's own message)

## Line information of a backtrace with an I/O error left pending

The line information of a backtrace (`lnfodwrf`, which `-gl` links in and
the product profile always does) reads the executable with the RTL's own
file routines, and `OpenExeFile` judged its `Reset` by `IOResult`. An I/O
error the program had left pending made that open look failed - and ate the
program's error - and `OpenDwarf` remembers a failed open of a file for the
rest of the run: one `IOResult` forgotten before the first backtrace took
the routine names and line numbers out of every backtrace of the process,
the report of an unhandled exception included. It was so before the change
of the rule above; with the rule the executable was, in addition, left open.

`GetLineInfo` clears `InOutRes` before it reads the executable and gives the
program its pending error back after.

Permanent regression test:

- [qualification/suite/tests/smoke/lineinfo_pending_io.pas](../qualification/suite/tests/smoke/lineinfo_pending_io.pas)
  (MoonCompiler only, built with `-gl`: a backtrace string with an error
  pending and one after, both with a line; the error still pending)

## x86 comparison semantics when removing a mask

The AND/CMP peephole always narrowed CMP to mask width. That is valid for
equality, but changes SF/OF/CF for relational consumers; an already narrow CMP
was also rewritten unnecessarily. The observable result was incorrect byte
extraction from a returned record with AUTOINLINE disabled.

If the original width is already covered by the mask, it is preserved. A wider
comparison is narrowed only for a nonnegative constant and only when every live
flags consumer tests equality. Otherwise AND+CMP remains; the proven fast
cmpb/cmpw/cmpl optimization is retained.

Permanent regression tests:

- [tests/test/cg/tandcmp1.pp](../tests/test/cg/tandcmp1.pp)

## Retaining the source-register definition for CMOV

In #41781, O3 silently lost every path argument: OptPass2CMOVcc replaced a late
CMOV with a constant MOV and removed its defining MOV after checking uses only
after replacement, so it missed an earlier CMOV between them.

Removal is allowed only when the source register is unused both between the
defining MOV and the transformed CMOV and afterwards. A minimal two-CMOV/Jcc
test proves the result, while the assembly control proves the valid CMOV-to-MOV
optimization remains.

Permanent regression tests:

- [tests/test/cg/tcmovliveness1.pp](../tests/test/cg/tcmovliveness1.pp)

## Defining the destination for an empty runtime set range

For a reversed runtime range, a separate destination retained stale bits because
fpc_varset_set_range returned before copying the source set. The existing copy
moved before the empty-range return: the destination is always defined before
optional mutation, with no extra work on forward and aliased paths.

Tests cover constant/runtime, checked, alias, boundary, based-set, and
cross-unit forms, including a randomized matrix.

Permanent regression tests:

- [tests/test/cg/tsetopenrange1.pp](../tests/test/cg/tsetopenrange1.pp)
- [tests/test/cg/usetopenrange1.pas](../tests/test/cg/usetopenrange1.pas)

## Retaining the type of a folded 128-bit result

Small explicit UInt128/Int128 expressions folded before the selected wide
definition reached the constant node; arithmetic, div/mod, shifts, and unary
minus collapsed to a type based on the value's magnitude.

The common fold constructor retains signed/unsigned 128-bit definitions; only
128-bit div/mod waits for the existing selection pass, and constant unary minus
receives the same Int128 as the runtime path. Cross-unit RTTI/PPU tests lock
down boundaries and neighbouring untyped/runtime forms.

Permanent regression tests:

- [tests/test/cg/tint128constfold1.pp](../tests/test/cg/tint128constfold1.pp)
- [tests/test/cg/uint128constfold1.pas](../tests/test/cg/uint128constfold1.pas)

## Retaining the code-page destination of Str

During O3 lowering of Str to a RawByteString compilerproc, the original
destination definition was erased before constant folding, so a typed
AnsiString received a CP0 header.

Across call copies and the PPU inline tree, only the destination definition
needed to build a folded AnsiString constant is retained. RawByteString CP_NONE
folds to the neutral CP0 contract of the live helper. The new payload raised the
PPU long version, and stale PPU is rejected.

Permanent regression tests:

- [tests/test/tcpstr29.pp](../tests/test/tcpstr29.pp)
- [tests/test/ucpstr29.pas](../tests/test/ucpstr29.pas)

## Delphi result width for real intrinsics

On Linux x86-64, Delphi-mode Int, Frac, Exp, Ln, Sin, Cos, ArcTan, and Sqrt
exposed x87 Extended. Overload selection and surrounding arithmetic differed
from Delphi Win64, whose computation boundary is an 8-byte Double.

The target Delphi computation type is selected while explicit CExtended is
retained; the type travels through helper lowering and the x87 result is
materialized in the declared scalar location. The checked Frac conversion with
AVX is preserved. Optimizers stay enabled; direct SSE/CExtended paths are not
rewritten.

Permanent regression tests:

- [tests/test/cg/tfracresulttype1avx2.pp](../tests/test/cg/tfracresulttype1avx2.pp)
- [tests/test/cg/tintrinsicresulttype1.pp](../tests/test/cg/tintrinsicresulttype1.pp)
- [tests/test/cg/tintrinsicresulttype1avx2.pp](../tests/test/cg/tintrinsicresulttype1avx2.pp)
- [tests/test/cg/uintrinsicresulttype1.pas](../tests/test/cg/uintrinsicresulttype1.pas)

## Retaining the checked type of a constant real intrinsic

Real-intrinsic folding recreated a result through pbestrealtype, widening the
constant after Delphi-compatible selection. An implicit CExtended to Extended
conversion likewise lost source identity before overload selection.

A folded real node is created with the already checked result definition; only
an implicit sc80 to s80 constant conversion is retained through the consumer.
Tests cover all affected intrinsics, Single/Double/Extended/CExtended, negative
controls, and separately loaded PPU constants.

Permanent regression tests:

- [tests/test/cg/tintrinsicconsttype1.pp](../tests/test/cg/tintrinsicconsttype1.pp)
- [tests/test/cg/uintrinsicconsttype1.pas](../tests/test/cg/uintrinsicconsttype1.pas)

## Retaining inline depth when copying a call

A nested recursive inline call could be copied through an initialization or
argument tree with inlinelevel reset. It repeatedly bypassed the existing growth
heuristic until the compiler exhausted the stack.

The transient inlinelevel is copied with the rest of tcallnode state.
Nonrecursive inlining remains active and machine-code-identical; tests include
#41184, branching recursion, runtime, and PPU paths.

Permanent regression tests:

- [tests/test/tinlinecopy1.pp](../tests/test/tinlinecopy1.pp)
- [tests/test/uinlinecopy1.pas](../tests/test/uinlinecopy1.pas)
- [tests/webtbf/tinlinecopyfail1.pp](../tests/webtbf/tinlinecopyfail1.pp)
- [tests/webtbs/tw41184.pp](../tests/webtbs/tw41184.pp)

## Normalizing a nested inline block before its enclosing scope

In #41456, nested inline control flow was extracted before surrounding
inline-parameter temporaries; temporary references became invalid and the
compiler raised IE 200108231. normalize pre-walked the body only for void
blocks; a value block moved first and lost its enclosing lifetime.

The body of any block is now normalized before deciding whether to extract the
enclosing value block. Runtime, boundary, callback, cross-unit, and isolated-PPU
tests lock down the boundary in O1/O2/O3.

Permanent regression tests:

- [tests/test/tinlineblock1.pp](../tests/test/tinlineblock1.pp)
- [tests/test/uinlineblock1.pas](../tests/test/uinlineblock1.pas)

## Deciding inlining on the body of the specialization

A generic routine that forks on its type argument with `GetTypeKind(T)` or
`IsManagedType(T)` was saved for inlining with every branch.  The inline body
is captured right after type checking, and these two intrinsics became
constants only in pass_1, so the `if`/`case` forking on them was still open
in the saved body of each specialization.  The inline budget counts the nodes
of that body against a limit that falls with the nesting level (100 nodes at
level 3): the flat `TDictionary` comparer of an 8-byte key carried its string
and class branches, 100 nodes, and was called on every lookup hit, while the
4-byte key (43 nodes) was inlined.  `SizeOf(T)` and `TypeInfo(T) =
TypeInfo(X)` forks were not affected: they are constants already at that
point.  The unfolded type argument also misled the managed-temporary guard of
the inliner: the type node of `IsManagedType(T)` counted as a managed
expression, and `TList<T>.SwapOwned` of a managed `T` stayed a call.

`GetTypeKind` and `IsManagedType` of a known type now fold in `simplify`, like
the other constant intrinsics, so the fork folds while the body is type
checked and the saved body holds the branch of its own specialization only
(the dictionary comparer: 20 nodes).  A type parameter or a type still generic
is left to its specializations.  Because such forks now fold while warnings
are issued, an `if` folded inside a specialization is not reported as
unreachable code: the type arguments cut that branch, not the source; the
generic's own body reports what is dead for every type.  The same stage split
exists in upstream FPC `main`.

Permanent regression tests:

- [tests/test/cg/tgenerictypeforkinline1.pp](../tests/test/cg/tgenerictypeforkinline1.pp)

## Delphi semantics of integer expressions

Arithmetic, div/mod identities, and unary signs use measured Delphi promotion
domains; narrow bitwise results remain narrow where Delphi retains them. Only
the syntax/provenance of a constant that affects overload resolution is kept;
it is serialized in PPU and cleared at parentheses, casts, and arithmetic
identities exactly as DCC64 does.

Source constants differ from constants created after inlining: source UInt64
negation follows Delphi compile-time rules, while an inline live expression
retains modular Q- behavior or runtime overflow under Q+. AUTOINLINE is not
disabled.

Permanent regression tests:

- [tests/test/cg/tcheckedneg1.pp](../tests/test/cg/tcheckedneg1.pp)
- [tests/test/cg/tcheckedneg2.pp](../tests/test/cg/tcheckedneg2.pp)
- [tests/test/cg/tcheckedneg3.pp](../tests/test/cg/tcheckedneg3.pp)
- [tests/test/cg/tcheckedneg4.pp](../tests/test/cg/tcheckedneg4.pp)
- [tests/test/cg/tcheckednegauto1.pp](../tests/test/cg/tcheckednegauto1.pp)
- [tests/test/cg/tcheckednegconst1.pp](../tests/test/cg/tcheckednegconst1.pp)
- [tests/test/cg/tcheckednegruntime1.pp](../tests/test/cg/tcheckednegruntime1.pp)
- [tests/test/cg/tdelphiconsttype1.pp](../tests/test/cg/tdelphiconsttype1.pp)
- [tests/test/cg/texplicitconst1.pp](../tests/test/cg/texplicitconst1.pp)
- [tests/test/cg/tintpromotion1.pp](../tests/test/cg/tintpromotion1.pp)
- [tests/test/cg/tmoddividentity1.pp](../tests/test/cg/tmoddividentity1.pp)
- [tests/test/cg/tmoddividentityfpc1.pp](../tests/test/cg/tmoddividentityfpc1.pp)
- [tests/test/cg/tunarysign1.pp](../tests/test/cg/tunarysign1.pp)
- [tests/test/cg/tuncheckedneg1.pp](../tests/test/cg/tuncheckedneg1.pp)
- [tests/test/cg/tuncheckedneg2.pp](../tests/test/cg/tuncheckedneg2.pp)
- [tests/test/cg/tuncheckedneg3.pp](../tests/test/cg/tuncheckedneg3.pp)
- [tests/test/cg/tuncheckedneg4.pp](../tests/test/cg/tuncheckedneg4.pp)
- [tests/test/cg/tuncheckednegauto1.pp](../tests/test/cg/tuncheckednegauto1.pp)
- [tests/test/cg/uexplicitconst1.pp](../tests/test/cg/uexplicitconst1.pp)
- [tests/test/cg/uuncheckedneg1.pas](../tests/test/cg/uuncheckedneg1.pas)
- [tests/webtbs/tw41808.pp](../tests/webtbs/tw41808.pp)

## Retaining required MOVSXD after x86 arithmetic

Sign extension is not removed after arithmetic and multi-step shifts unless the
high 32 bits are proven to be the sign extension of the low result. Existing
removal for direct moves and proven bitwise producers remains; the boundary test
reproduces conversion of a negative LongInt into a positive 64-bit value.

Permanent regression tests:

- [tests/test/cg/tmovsxdarith1.pp](../tests/test/cg/tmovsxdarith1.pp)

## Classifying 64-bit radix literals as UInt64

Delphi hexadecimal/binary patterns with the high bit set are parsed again as
UInt64, rather than negative Int64. This restores DCC overload selection and
removes false R+ diagnostics for
$8000000000000000..$FFFFFFFFFFFFFFFF. Signed literals, the FPC octal
extension, and ObjFPC are unchanged.

Permanent regression tests:

- [tests/test/cg/tu64radixliteral1.pp](../tests/test/cg/tu64radixliteral1.pp)
- [tests/test/cg/tu64radixliteralfpc1.pp](../tests/test/cg/tu64radixliteralfpc1.pp)

## Mathematical comparison of mixed Int64/UInt64

Delphi compares mixed signed/unsigned 64-bit values mathematically. The old
path converted UInt64 to Int64, so identical bit patterns could compare equal
and values above High(Int64) became negative. Only Delphi relational operators
extend both operands to signed 128-bit. FPC mode and arithmetic expressions are
unchanged.

Permanent regression tests:

- [tests/test/cg/tmixedint64compare1.pp](../tests/test/cg/tmixedint64compare1.pp)

## Retaining overflow checks when lowering Inc/Dec

The checked fallback intentionally lowers Inc/Dec to add/sub, but
create_internal marked the arithmetic internal, and codegen disables overflow
checks for it. It now builds ordinary add/sub, and nf_internal is inherited only
from an actually internal source node, as in checked Succ/Pred. Tests cover
signed and signed/unsigned 64-bit overflow.

Permanent regression tests:

- [tests/test/cg/tcheckedincdec1.pp](../tests/test/cg/tcheckedincdec1.pp)

## Normalizing `or` over `ByteBool` in Delphi mode

Delphi materializes a logical expression over ByteBool, WordBool, and LongBool
as an ordinary one-byte Boolean with value 0/1. Assigning that result back to a
C-style Boolean separately produces the ABI true representation
$ff/$ffff/$ffffffff. Previously or could preserve raw operand bits, and a
nested explicit read of storage width (Byte(ByteBool) and equivalents) was
incorrectly fused with later widening, extending every one bit over the wide
destination.

In Delphi mode the logical-expression result is now Boolean; non-Delphi modes
are unchanged. The optimizer no longer fuses an explicitly written intermediate
bool-to-int cast with outer int widening. The runtime test covers and/or/xor,
all three C-style types, expression size, assignment ABI, and explicit storage
casts, without letting constant folding hide the representation.

Permanent regression tests:

- [tests/test/cg/tbyteboolor1.pp](../tests/test/cg/tbyteboolor1.pp)

## Delphi semantics of Hi/Lo

For Word, Integer, Cardinal, Int64, and UInt64, Delphi returns the high/low byte
of the low word. FPC returned half the operand width and warned in Delphi mode.
A constant expression has a byte-sized type, while a runtime expression is
Word; the distinction is visible through SizeOf and overload resolution.
Constant folding, runtime shift, and runtime result type change only under
m_delphi; TP/FPC behavior is unaffected.

Permanent regression tests:

- [tests/test/cg/tdelphihilo1.pp](../tests/test/cg/tdelphihilo1.pp)

## Branch-exact inclusive floating selection

The min/max rewrite used one SSE intrinsic for strict and inclusive comparisons.
With equal float sources, the source branch selects different operands, visible
for +0/-0; one MINSD ordering cannot preserve both tie selection and the NaN
else path. Inclusive float selection remains a branch; the existing min/max
optimization remains for strict float and every integer case.

Permanent regression tests:

- [tests/test/cg/tfloatminselect1.pp](../tests/test/cg/tfloatminselect1.pp)

## Delphi storage and alignment for set

Delphi rounds set storage: 3 bytes to 4, 5..7 to 8, and above 8 returns to the
exact byte count. FPC already knew the 3-byte boundary but kept 5 bytes for
set of 0..32. Separately, an ordinary record/class field aligned to widened
storage, whereas Delphi gives a set field byte alignment and thus shifts all
following fields.

Only the missing Delphi-mode 5..7 rounding and byte field alignment were added.
Set base/max, packed rules, and non-Delphi modes are unchanged. The DCC64 oracle
covers sizes through 17 bytes, nonzero bases, records, arrays, class fields,
parameters, and runtime copy/membership.

Permanent regression tests:

- [tests/test/cg/tdelphisetlayout1.pp](../tests/test/cg/tdelphisetlayout1.pp)

## Reverse finalization order for managed fields

FinalizeRecordFields counted down but moved the pointer forward, so locals,
record, and object fields finalized in declaration order. The pointer now starts
after the table and decrements before each call, as in Delphi. Array-element
finalization is a separate path and remains forward.

Permanent regression tests:

- [tests/test/cg/tfinalizeorder1.pp](../tests/test/cg/tfinalizeorder1.pp)

## Lexical reverse finalization of Delphi managed locals

Classic Delphi procedure locals are destroyed in reverse declaration order. A
managed inline variable instead lives from its declaration to the end of the
enclosing lexical block, including sibling blocks, loop re-entry, Exit, Break,
Continue, exceptions, and the program body. Walking symbol tables only at
procedure exit could not represent that block lifetime.

Classic locals are emitted in reverse symbol order. A managed inline declaration
is transiently marked, initialized in place, and registers finalization through
existing defer lowering. A lexical block turns the markers into one ordinary
LIFO try/finally; procedure-wide init/fini skips that symbol, preventing early
or double cleanup. Tuple, for-in destructuring, and scoped with var use the
same helper. FPC/ObjFPC retain the former path.

An ordinary try/finally was intentional: O3 DFA does not model a parser-only
implicit finally, and that shortcut had already caused an internal error. Cost
occurs only in routines with managed inline variables and uses the supported
exception/early-exit path.

Focused tests cover classic locals, normal/exceptional exits, initializer
failure, sibling blocks, early exits, loop re-entry, custom managed records,
the program body, user defer, scoped-with, tuple declarations, and for-in
destructuring. Shared Delphi-compatible tests also pass under DCC64 12.2.

Permanent regression tests:

- [tests/test/cg/tdelphilocalfinalize1.pp](../tests/test/cg/tdelphilocalfinalize1.pp)

## Static binding of inherited inside a Delphi class helper

Delphi permits inherited inside a class helper to bind to the selected extended
class method even if Self is a descendant with an override in the same VMT slot.
The parser selected the right procdef but retained Self as a method pointer, so
codegen dispatched again through the descendant VMT.

The existing type-based inherited-call path is enabled only in Delphi mode.
ObjFPC retains its documented virtual helper dispatch.

Permanent regression tests:

- [tests/test/cg/tdelphihelperinherited1.pp](../tests/test/cg/tdelphihelperinherited1.pp)

## Delphi dialect and error result of integer Val

Delphi rejects %/& radix prefixes, does not skip a leading TAB, reports an
unsigned negative position after the minus, and retains the parsed value when
Code reports trailing input or integer overflow. FPC accepted the extra
prefixes, skipped TAB, returned another position, and zeroed the result.

The native integer helper already receives negative DestSize; this impossible
ordinary-call value is used as a Delphi-only contract bit. The common
ShortString parser immediately restores positive size and applies measured
rules. Dynamic-string wrappers use that path only for negative DestSize;
FPC/ObjFPC continue calling the prior public Val(ShortString, ...).

Permanent regression tests:

- [tests/test/cg/tdelphival1.pp](../tests/test/cg/tdelphival1.pp)

## NUL terminator in the direct integer parser

Optimized TryStrToInt/TryStrToInt64 reads UnicodeString directly from the wide
buffer instead of copying into ShortString and common Val. Originally it
accepted only digits through Length(S), so '3210'#0'ABFG' was rejected. Delphi
and the former Val treat the first #0 after digits as the end of the number;
a lone #0, sign, or radix prefix before #0 is not a number.

No preliminary pass or per-digit branch was added. Only an already found
non-digit is tested for #0 and accepted if at least one digit preceded it.
Decimal/hex overflow, trailing garbage, and the ordinary hot path are unchanged.

Permanent regression test:

- [RTL-test/semantic/integer_conversion.dpr](../RTL-test/semantic/integer_conversion.dpr)

The same cross-profile run fixed a neighbouring formatting defect: writing a
pair of decimal digits was hard-coded as PCardinal, four bytes. That matched two
Unicode Char values but overwrote two adjacent bytes in the ANSI bootstrap RTL.
The write is now typed TDecimalDigitPair, so its width automatically equals two
current Char values in both RTL profiles.

## Transferring ownership of an interface function result

A managed interface result in a hidden temporary already owns one reference.
Ordinary assignment added another one and the hidden result deliberately was not
finalized, so a wrapped result such as an interface as-cast leaked.

The existing function-result detector now sees through as and only
location-preserving implicit/internal interface conversions. A proven owned
temporary uses the move helper: the old destination is released and the
reference transferred without AddRef. Explicit casts, class-to-interface,
ordinary interface copies, and managed records stay on their old paths.

Permanent regression tests:

- [tests/test/cg/tdelphiinterfacechain1.pp](../tests/test/cg/tdelphiinterfacechain1.pp)
- [tests/test/cg/tdelphiinterfacefuncret1.pp](../tests/test/cg/tdelphiinterfacefuncret1.pp)

## Releasing an exception replaced inside finally

The legacy PSABI runtime retained a displaced exception object when finally
raised a new exception. Simply removing any earlier refcount-zero wrapper would
also be wrong: the new exception may be locally caught inside that finally,
after which the original unwind must continue.

The runtime records the exact pair of the CFA frame and next outer LSDA action
after this finally's catch-all landing pad. A new exception marks the old one
replaced only when its search phase actually reaches that action without first
meeting a local handler. In cleanup on the same CFA, only the marked wrapper is
deleted; same-object protection does not release a live object twice. Normal
finally, local typed/catch-all handlers, nested-procedure calls, and genuine
replacement are locked down independently.

Permanent regression tests:

- [tests/test/tdelphiexceptionreplace1.pp](../tests/test/tdelphiexceptionreplace1.pp)

## Static RTTI catalogue for TRttiContext.GetTypes

FPC could construct RTTI for a known PTypeInfo but not enumerate linked
application types. A project-side manual registry would duplicate Pascal
declarations and could silently miss a new type.

The compiler now marks only top-level named candidates of the current module,
asks the ordinary RTTI writer to materialize supported definitions, and places
only actually created PTypeInfo in a table. The linker combines linked-unit
tables into one executable catalogue; TRttiContext.GetTypes reads it without
runtime registration or initialization hooks. Generic templates, partial
specializations, forward/unique aliases, internal/ObjC types, and VMT-less
classes do not become false identities. Changed PPU metadata raises the PPU
version.

Permanent gates:

- qualification/suite/scripts/run_rtti_gettypes_gate.sh;
- qualification/suite/scripts/run_rtti_ppu_version_gate.sh;
- qualification/suite/scripts/run_rtti_nocall_comparison.sh.

The static x86-64 executable boundary on Linux and Win64 is locked down by the
listed runtime and PPU-version gates.

## Delphi compatibility proven by a full-scale application

These forms emerged in a large multi-module build and were then reduced to
focused tests with the exact first broken invariant.

### One identity for aliases and default namespaces

MoonBot mixes dotted Delphi unit names and legacy FPC names. Treating them as
two modules split identical generic interfaces, while PPU reuse permitted a
qualifier differently from a clean build.

The repair uses the existing unit-alias mechanism: an alias is validated, bound
to the real module, and its source qualifier restored during specialization and
PPU load. Only the lookup key is normalized; target spelling is unchanged, so
-UaFoo=Bar on a case-sensitive filesystem still opens Bar.pas. No second type
identity is created and unaliased lookup is unaffected. The permanent
qualification/suite/scripts/run_namespace_scope_gate.sh gate checks clean/PPU
reuse, shadowing, and generic specialization.

A later product repro found the reciprocal half: uses SysUtils resolved through
-UaSystem.SysUtils=SysUtils left only SysUtils visible, while Delphi also keeps
System.SysUtils. The unit symbol table registers an extra name only for
configured dotted aliases that refer to an imported short name. The physical
module, PPU, and type identity remain singular; ordinary -UaFoo=Bar gains no
new reverse visibility. Focused regression
[tmoonnamespacequalified1.pp](../tests/test/cg/tmoonnamespacequalified1.pp) and
the namespace gate check short/full qualifiers, O2/O3, and clean/PPU reuse.
Because the PPU loader clears tunitsym.module, generic replay reconnects every
source/full alias of one used module, not merely the first short symbol; a
separate generic body makes this boundary red without the repair.

### Implicit function specialization without a mandatory named type

Delphi mode had not enabled the existing FPC implicit-specialization path, so a
generic method could not infer the type of a sibling generic method. Enabling it
exposed an upstream edge: an unnamed TArray<T> from another unit has no typesym,
and inference raised internal error 2021020905 instead of comparing types.

The named-type path is unchanged. Only with typesym=nil is identity proved by
canonical definition and owner.is_generic_param; a distinct alias, different
generic parameter, or foreign definition cannot match. This is the same
definition-plus-owner invariant as adjacent array inference.

Permanent regression tests:

- [tests/test/timpfuncspez38.pp](../tests/test/timpfuncspez38.pp);
- [tests/test/uimpfuncspez38a.pp](../tests/test/uimpfuncspez38a.pp);
- [tests/test/uimpfuncspez38b.pp](../tests/test/uimpfuncspez38b.pp);
- upstream tests/webtbs/tw39677.pp and the existing implicit-specialization family.

### Retaining inherited on a helper property

The parser retained the inherited-call flag for a helper method but lost it
when the selected member was a property accessor. A helper property could
recursively invoke itself or redispatch through the active helper instead of
the base getter/setter extended class.

Only already established inherited flags are passed to the accessor; an ordinary
member-call flag is then added if needed. No other flags are copied, and
ordinary property access remains on its old path.

Permanent regression test:
[tests/test/cg/tdelphihelperinheritedproperty1.pp](../tests/test/cg/tdelphihelperinheritedproperty1.pp).
Omni separately retains the exact product TMyTrackBar.Value form, with a field
read and method write.

### Capturing an exception variable with Delphi semantics

on E: Exception lives in a temporary exception symbol table. The anonymous
routine capturer considered only normal local/parameter/block tables, so E
reached codegen without a location or crashed the O3 inliner.

The exception table is recognized by its owning procedure; every lexical
handler gets a collision-proof capturer field, the raw value is copied at entry,
and explicit reads/writes of E redirect to that field. Hidden exception
ownership is not transferred: Delphi 12.2 also destroys the object on handler
exit even if the closure outlives it. One pre-codegen invariant applies to a
procedure, program body, and unit init/fini; special static routines receive
distinct internal names.

The same form exposed another O3 defect: replacing a function-reference
parameter caused replaceparaload to lose nf_load_procvar, so a callback could
run while method/VMT/hidden-self carriers were built. The existing marker is
now retained on the replacement load. noinline was not added; AUTOINLINE stays
enabled and is checked by O3 assembly.

The permanent qualification/suite/scripts/run_exception_capture_gate.sh gate
checks O-/O2/O3, mutation of E, nested/sibling handlers, re-raise, lifetime,
callbacks, and program/unit init/fini.

### Initializing the fallback monitor manager

Generic thread initialization could leave the monitor manager as a zero record.
A late owner TMonitor after successful shutdown finalized through nil callback
DoFreeMonitorData. For a target with a fallback monitor, the existing
InitMonitor is called. This is init/fini, not a hot path; Win32/Win64 use the
platform thread unit and do not enter the branch.

Permanent regression tests:
[tests/test/tmonitorfinalize.pp](../tests/test/tmonitorfinalize.pp) and
[tests/test/umonitorfinalize.pp](../tests/test/umonitorfinalize.pp).

### Opt-in backslash handling on POSIX

MoonBot stores Delphi-style paths with backslashes. Globally recognizing
backslash as a POSIX separator would silently change every FPC program, so the
RTL offers one process-wide opt-in switch defaulting to False; the service sets
it before application initialization. Disabled state preserves old POSIX
behavior. The product probe checks ForceDirectories, stream/text I/O,
rename/delete while enabled, and literal backslash while disabled.

### Repairing existing Delphi/Unicode paths in paszlib

Real ZIP read/write in Delphi Unicode mode found two package errors: zError
wrote through a name-conflicting fallback result, and tree_ptr was indexed
without pointer math. Result is used and pointer math enabled in the unit where
indexing already occurred. The deflate/inflate algorithm and archive format are
unchanged; the product adapter passes a round trip.

### Aligning conditional identifiers with Delphi expressions and string mode

Two independent conditional-compiler forms diverged from the active ABI. A bare
unknown identifier and its unary not must evaluate False rather than become a
truthy string. Separately, an ordinary non-product source-unit transition from
DelphiUnicode to Delphi changed Char/String ABI but left UNICODE and
FPC_UNICODESTRINGS defined.

Unresolved-identifier markers remain only inside conditional expressions, and
the bare/unary-not path changes only in Delphi mode. Unicode defines are cleared
where the ordinary scanner changes active string mode. Conversely, product
MOONCOMPILER_UNICODE_DEFAULT
intentionally retains Unicode String/Char and both defines even after
{$mode delphi}: a source-mode directive may not silently change the ABI of the
single product RTL. Comparisons, Boolean operators, unit loading, ObjFPC mode,
and explicit AnsiString/AnsiChar retain their old paths.

The permanent oracle is in omni_conditional_* units and
mode-delphi-defines-match-types inside Omni; both program by O2/O3 by seed
paths run through qualification/suite/scripts/run_forms_gate.sh on Linux and
run_forms_gate.ps1 on Win64.

### Narrow extension of the RTL/API compatibility surface

Other service-derived commits add missing Delphi surface by delegating to
existing implementations rather than copying algorithms:

| Surface | Minimal implementation and retained boundary |
|---|---|
| Variant Char/WideChar dispatch | Only these arguments use the existing managed wide-string Variant path; Win64 returns varOleStr, Linux varUString, with identical text. |
| Explicit anonymous callback cast | Const type checking is retained; codegen emits the explicitly requested value ABI and rejects incompatible modifiers. |
| Variant to distinct ordinal | df_unique layers reach the base ordinal only without a user operator, then restore the final distinct type internally. |
| Reserved member after . | A word token is accepted only in qualified-member position; declaration grammar is unchanged. |
| Unicode defines and source mode | The ordinary profile follows actual string mode; the product Unicode profile keeps Unicode ABI and defines after {$mode delphi}. |
| Nested anonymous Self | Compiler dummy Self resolves to the actual enclosing-method instance; ordinary nested routines are unchanged. |
| Inline local initialization | Reuses assignment-expression and typed-constant writers for Variant and comma-separated const arrays; frees the replay buffer on both success paths. |
| TArray.Sort/BinarySearch | Delegates to existing TArrayHelper; no second algorithm, and the upstream Int32 boundary is not hidden by a dead check. |
| Anonymous equality comparer | A Delphi function reference is retained by the delegated comparer; existing overloads are unchanged. |
| Dotted string comparers | Only dotted Delphi aliases explicitly bind to UnicodeString. |
| OleVariant to UTF-8 | Uses the existing VariantManager WideString-to-UTF8 scheme. |
| TCollection.ClearAndResetID | Performs ordinary Clear, then only this API resets the next-ID counter. |
| TStrings.KeyNames | A separate accessor retains the whole entry without a separator; otherwise it returns the key prefix. |
| DivMod(UInt64) | Unsigned division and one-time remainder reconstruction. |
| Delphi overload UIntToStr(Int64) | Signed storage is formatted through the existing QWord bit-pattern path. |

These source forms are locked down by focused tests and versioned MoonBot/Omni
gates. No change replaces a working algorithm or alters an unrelated mode.

### Version and identity macros

The compiler defines these macros for use in `{$IF}` / `{$IFDEF}`:

| Macro | Value | Origin |
|---|---|---|
| `MOONCOMPILER_FULLVERSION` | `major*10000 + minor*100 + patch` (`20000` for `2.0.0`) | `mooncompiler_version` in `version.pas` |
| `MOONCOMPILER_VERSION` | The version string itself (`2.0.0`) | same |
| `MOONCOMPILER_SYSTEM_ZLIB` | Defined on Win64 and Linux x86-64: `System.ZLib` of the RTL is the program's zlib; MoonORMot's `mormot.lib.z` compresses through it (`-u` gives mORMot's own choice back) | `options.pas`, next to `NOPATCHRTL` |
| `MOONCOMPILER_UNICODE_DEFAULT` | Defined by the product `fpc.cfg` | config file |
| `MOONBOT_MM_PROFILE_REQUIRED` | Defined by the product `fpc.cfg` | config file |

Usage in projects compiled by both Delphi and MoonCompiler:

```pascal
{$IFDEF FPC}
  {$IF not defined(MOONCOMPILER_FULLVERSION)}
    {$MESSAGE FATAL 'This project requires MoonCompiler'}
  {$IFEND}
  {$IF MOONCOMPILER_FULLVERSION < 10000}
    {$MESSAGE FATAL 'MoonCompiler 1.0.0 or later is required'}
  {$IFEND}
{$ENDIF}
```

Delphi ignores the `{$IFDEF FPC}` block entirely.

## Repairs across the broad compiler/RTL surface

Every repair below is limited to its first broken invariant and has a permanent
executable regression.

| Defect | Repair boundary | Regression |
|---|---|---|
| Unsigned Word * Word lost zero extension on widening or Cardinal assignment of equal width under {$R+} | Visible Delphi type remains Integer; a separate marker exists only for unsigned narrow multiplication, and UInt32 is applied only when folding/converting to an unsigned target no narrower than the result | [tunsignednarrowarith1.pp](../tests/test/cg/tunsignednarrowarith1.pp) |
| Mixed signed/UInt64 operators selected the wrong domain; positive untyped literals/constants fitting UInt32 stayed signed, so valid MoonBot Max(UsedNonce, StoredNonce + 1) was ambiguous | In Delphi mode measured DCC constant-fit applies first: through High(UInt32) selects UInt64; typed Integer/Int64 and larger natural Int64 retain signed domain; the normal mixed runtime expression then remains visible Int64 | [tdelphimixeduint641.pp](../tests/test/cg/tdelphimixeduint641.pp) |
| Delphi uses expected types of an entire two-parameter signature: Pair(UInt64, UInt64 + Integer) selects UInt64 although isolated Kind(UInt64 + Integer) sees Int64 | Only on a complete ordinary-ranking tie, a Delphi-mode tie-breaker treats UInt64 parameters receiving mixed arithmetic; direct Pair(Int64, UInt64) remains ambiguous and declaration order is irrelevant | [tdelphimixeduint641.pp](../tests/test/cg/tdelphimixeduint641.pp), [delphi_mixed_uint64_pair_ambiguous.pas](../qualification/suite/tests/smoke/delphi_mixed_uint64_pair_ambiguous.pas) |
| x86-64 UInt64 mod 4294967296 attempted to encode $00000000FFFFFFFF as sign-extended 32-bit immediate and failed in the assembler | The power-of-two fast path reuses generic a_op_const_reg: encodable masks remain immediate and others materialize in a register | [tu64modpow2mask1.pp](../tests/test/cg/tu64modpow2mask1.pp) |
| Folded x86 shifts differed from instructions at large counts and lost signed result type at high bit | Only Delphi/x86 folding uses operand width, hardware count mask, and selected result definition | [tdelphix86shiftfold1.pp](../tests/test/cg/tdelphix86shiftfold1.pp) |
| A generic comparer probe dereferenced an argument before a conversion had a result type | Rejects only incomplete inline candidates; fully typed candidates retain lifetime checks | [tinlinegenericcomparer1.pp](../packages/rtl-generics/tests/tinlinegenericcomparer1.pp) |
| A concrete symbol shadowed an implicit generic of the same name before parsing <...> | Selection defers only with a registered generic candidate and specialization token | [tnestedgenericarray1.pp](../packages/rtl-generics/tests/tnestedgenericarray1.pp) |
| Capturing a managed inline variable moved storage into a capturer while lexical init/fini remained at old storage | Generated init/finalizer form a lifetime pair; on ownership transfer both markers are removed and the field is serviced by the capturer | [tcapturedinlineinterface1.pp](../tests/test/cg/tcapturedinlineinterface1.pp), [tcapturedinlineinterface2.pp](../tests/test/cg/tcapturedinlineinterface2.pp) |
| Full RTTI helper referenced a nested-generic record without requesting its RTTI | Dependency is added only in the full helper-RTTI writer that actually writes the reference | [thelpernestedgenericrtti1.pp](../tests/test/cg/thelpernestedgenericrtti1.pp) |
| Win64 pre-simplification loop unroll moved an SEH handler before detecting managed temporaries | Skips only a pre-simplification x86-64 SEH loop with exception frame; unroller and legality checks remain | [tforunrollfinally1.pp](../tests/test/cg/tforunrollfinally1.pp), [tforunrollfinally2.pp](../tests/test/cg/tforunrollfinally2.pp) |
| x86 MOV forwarding changed runtime-bound CMP into cmp reg,reg and liveness removed the bound | Forbids only the exact CMP substitution merging two registers; all other MOV forwarding remains enabled | [tpeepequalregloop1.pp](../tests/test/cg/tpeepequalregloop1.pp) |
| Block-scoped Delphi const after a statement gave Illegal expression or a false compile-time constant | Always creates a declaration-point read-only local; typed aggregate copies from internal static carrier and user write is forbidden | [tdelphiinlineconstruntime1.pp](../tests/test/cg/tdelphiinlineconstruntime1.pp) |
| Win64 Currency * Currency truncated product to 64 bits before dividing by 10000 | Non-reducible integer-backed path uses signed 128-bit intermediate, Delphi ties-to-even, and range check | [tdelphicurrencymul1.pp](../tests/test/cg/tdelphicurrencymul1.pp) |
| RawByteString concat/compare routed mixed code pages through system encoding, and Unicode-default product profile promoted the entire raw operation | RawByteString provenance survives folding; explicit/static raw blocks only default-Unicode promotion of an untyped literal. These concats retain bytes/dynamic CP, explicit Unicode still wins, typed AnsiString retains system-CP path; PPU version rises for the serialized flag | [tdelphirawbyteconcat1.pp](../tests/test/cg/tdelphirawbyteconcat1.pp) |
| In Unicode product RTL, TGUID.FromString(ShortString) addressed one-byte characters through two-byte PChar, so StringToGUID rejected every valid GUID | Preserves ShortString ABI and changes only the physically wrong pointer to PAnsiChar; GUID layout, hex parser, format errors, and reverse conversion remain | [tunicodeguidparse1.pp](../tests/test/cg/tunicodeguidparse1.pp), Devil dvl-0046 |
| Win64 Delphi ABI string/UnicodeString Variants were varOleStr and ASCII literal varString; after one subtype change, comparing two varUString values crashed | Assignment-operator lookup retains source AST kind, Unicode operator creates standard varUString, and common-type/compare/concat paths fully handle it; explicit WideString/AnsiString unchanged | [tdelphivariantstring1.pp](../tests/test/cg/tdelphivariantstring1.pp), Devil dvl-0051 |
| Explicit RawByteString(VariantValue) found no conversion operator and broke Unicode mORMot builds | Exact RawByteString assignment operators for Variant/OleVariant call existing VarToLStr; Delphi oracle matches AnsiString(VariantValue) ANSI-codepage result | [tdelphivariantrawbytestring1.pp](../tests/test/cg/tdelphivariantrawbytestring1.pp) |
| O2/O3 CSE treated IEEE +0.0 and -0.0 as one real constant | Constant-node equality compares the sign bit unless fast math is permitted; folding/emission, Currency, nonzero values, and explicit fast-math contract remain | [tdelphinegativezero1.pp](../tests/test/cg/tdelphinegativezero1.pp), Devil dvl-0053 |
| Non-addressable record with target died before an escaped closure read it | Materializes the rvalue once in a lexical read-only local and passes it to the ordinary capturer | [delphi_with_anonymous.pas](../qualification/suite/tests/smoke/delphi_with_anonymous.pas) |
| Addressable composite with target was copied into closure already typed and did not capture storage | Computes lvalue address once, captures pointer and base outer storage, and re-typechecks copy in nested context | [delphi_with_anonymous.pas](../qualification/suite/tests/smoke/delphi_with_anonymous.pas) |
| Delphi expects TList<T>.arrayofT as exact backing-array type | Adds public nested compile-time alias TArrayOfT; storage/layout/runtime unchanged | [delphi_tlist_arrayoft.pas](../qualification/suite/tests/smoke/delphi_tlist_arrayoft.pas) |
| TList<array of T> stopped compiling after pointer-index Exchange/Reverse optimization: PT[index] meant an inner dynamic-array index | Both reorder paths again use FItems[index]; Release without range checks remains direct addressing but type system preserves the outer generic element and nested-array lifetime | [collections_hotpaths.dpr](../RTL-test/semantic/collections_hotpaths.dpr), trackers QP-31 and SO-04 |
| Generic PPU replay lost source-unit alias and outer-token position | Symbol indexed by source spelling and canonical alias; position restored only at three replay points | [generic_alias_replay.pas](../qualification/suite/tests/smoke/generic_alias_replay.pas) |
| A non-distinct result-alias implementation diverged from generic declaration with equal definitions | After compare_rettype declaration result is reused only for non-distinct aliases; distinct/other arguments rejected | [generic_return_alias.pas](../qualification/suite/tests/smoke/generic_return_alias.pas) |
| New(Value) in assigned/passed anonymous routine parsed as FPC expression New(Type) | Before each nested body only inherited parser flags of outer assignment/call-argument context reset and are restored after; normal New(pointer-lvalue), managed init, and FPC expression form unchanged | [tdelphianonymousnew1.pp](../tests/test/cg/tdelphianonymousnew1.pp), [moonbot_inline_pointer_new.pas](../qualification/suite/fixtures/minimized/moonbot_inline_pointer_new.pas) |
| Constant set of 200..255 changed a padding byte based on unrelated source-neighbour files | Internal set always has 256 meaningful bits; when rebased, only logical 5..7 bytes copy and rounded eight-byte Delphi ABI tail is zeroed; 33rd-byte read removed | [tsetconstbase1.pp](../tests/test/cg/tsetconstbase1.pp), [run_devil_env_gate.py](../qualification/suite/scripts/run_devil_env_gate.py) |
| StaticArray[InvariantField] address was recomputed every iteration although base/index were invariant | Hoists only ordinary unpacked static array with unmanaged element and R/Q disabled; initial delta uses signed pointer domain. Any call/ASM, pointer write/escape, volatile field, or same-symbol write including alias prevents hoist; managed/checked paths remain to preserve lifetime and zero-iteration exceptions | [tloopinvariantaddr1.pp](../tests/test/cg/tloopinvariantaddr1.pp) |
| After inner-loop unroll, optimizer deemed Table[Data[I]] invariant in outer loop and AES diverged from FIPS-197 from round two | Vector expression invariant only if loop neither writes/modifies same base nor takes/releases its address and has no opaque call/ASM/pointer write; preserves actual invariant StaticArray[InvariantField] hoist while forbidding stale address | [tloopinvariantarraywrite1.pp](../tests/test/cg/tloopinvariantarraywrite1.pp), Devil dvl-0055 |
| Two O3 passes trusted direct node-DFA definitions: strength reduction hoisted mutable global/static scalar over call and missed post-inline writes; CONSTPROP moved parent-frame non-registerable local through loop, producing old product, 441 not 651, and 142 not 127 | Local/value parameter must be registerable, uncaptured, non-address-taken, nonvolatile, and without direct write. Static scalar uses one common final-tree opteffect model that sees opaque calls and post-inline writes; old node-kind scan removed. CONSTPROP moves a constant through loop only for temporary or registerable scalar | [tloopopaqueeffects1.pp](../tests/test/cg/tloopopaqueeffects1.pp), Devil optimizer-effects matrix, dvl-0060, dvl-0062 |
| Variant(Cardinal($FFFFFFF0)) to Cardinal raised overflow although varLongWord carrier was correct | Small integer carriers retain allocation-free path; exact varLongWord read directly, other Variant/OleVariant carriers enter unsigned domain immediately; string carriers follow Delphi round/modulo contract under {$Q-}{$R-} | [variant_cardinal_semantic.dpr](../RTL-test/semantic/variant_cardinal_semantic.dpr), Devil dvl-0061 |
| O3 strength reduction used source enum/subrange for initial address; guarded cursor could start outside slice, and @procedure-variable element meant code pointer | Internal address cursor separately marked, calculated in signed pointer-size domain, and requests storage address. Checked loops do not strength-reduce, retaining original range/overflow point | [tstrengthenumguard1.pp](../tests/test/cg/tstrengthenumguard1.pp), [strength_guarded_enum_semantic.dpr](../RTL-test/semantic/strength_guarded_enum_semantic.dpr) |
| O2/O3 moved +1 from fixed-array index outside retaining conversion; after insertion-sort sentinel J=-1, range(J+1) became range(J)+1 and wrote to a huge address | Constant offset moves to machine displacement only when index root itself is add/sub with no outer retaining conversion; safe direct A[I+const] folds, converted expression evaluates J+1 first | [tarrayindexoffsetconv1.pp](../tests/test/cg/tarrayindexoffsetconv1.pp), [array_index_offset_semantic.dpr](../RTL-test/semantic/array_index_offset_semantic.dpr) |
| After AUTOINLINE proven no-throw scalar code stayed inside dead try/except and hidden parameter temporary spilled due to caller handler | Post-inline simplifier uses conservative no-throw proof only for unchecked ordinal tree without calls, managed values, indirect/reference loads, delayed-temp init, division, or FP; it fully parses/checks handler first, removes dead runtime region, synchronizes procedure exception flag, and preserves every genuine access/overflow/range/division/callee handler | [tdelphiinlineexceptreg1.pp](../tests/test/cg/tdelphiinlineexceptreg1.pp), [dead_try_handler_still_checked.pas](../qualification/suite/tests/smoke/dead_try_handler_still_checked.pas) |

Delphi-compatible shift semantics also found one wrong assumption in the
mandatory MM: heap-status formatter wrote 1 shl 50 without explicit 64-bit
operand. PtrUInt(1) shl 50 changes neither allocator nor hot path and removes
only division by zero on finalization. The sole source is runtime/mm; product
and extended mORMot suites compile it through --pinned-unit.

The permanent Win64 repair gate does not rely on source repros: it runs 50
executables and ten compile-fail controls in O2/O3, 120 lines total, and inspects
assembly for SEH unroll, invariant array address, removal only of proven-dead
post-inline exception region, and absence of an extra copy of a read-only
managed function result. A separate runtime regression checks three consecutive
indexed-array mutations and forbids reuse of the address selected by first-pass
data. Provenance also hashes installed system.ppu and sysutils.ppu so an RTL
regression cannot be attributed merely to the compiler executable hash. Runtime
inline constants are checked as scalar/typed values, arrays, strings,
interfaces, records, generic methods, loop declarations, closures, and the
exact MoonBot field-expression form.

## Qualified System.Integer in Object Pascal modes

**Symptom.** Integer(Word(65535)) yielded 65535, while
System.Integer(Word(65535)) yielded -1. A deep Devil consumer showed the
production consequence: ordinary TComparer<Word> flipped the sign for
32768..65535, so TArray.Sort<Word> and binary search silently failed.

**Cause.** System has historical bootstrap alias Integer = SmallInt. In
Delphi/ObjFPC/Unleashed modes implicit ObjPas provides real language
Integer = LongInt on targets wider than 16 bits. Bare name saw ObjPas, while
qualified unit lookup returned System's two-byte symbol. Thus it was a
type-resolution defect, not codegen/comparer failure.

**Repair.** Qualified lookup normalizes exactly System.Integer, only with active
m_objpas, to signed 32-bit; a 16-bit target remains 16-bit. TP/ISO and other
System types and bare lookup remain unchanged, including bootstrap builds.

**Validation.** tdelphiqualifiedinteger1 covers size/range, cast, declaration,
pointer, array, argument, var/out, and Word boundaries. tqualifiedintegercomparer1
checks comparer sign, sort, and binary search while preserving Byte/Cardinal/
UInt64 controls. Both run in O2/O3 in permanent Win64 repair gate; focused
execution passed O-/O2/O3. TP/ObjFPC controls confirm unchanged two-byte TP and
32-bit ObjPas semantics.

## TStringHelper.Split for an empty string

**Symptom.** ''.Split([',']) returned an array with one empty string whereas
Delphi 12.2 returns an empty array; normal for Part in Line.Split(...) therefore
ran one extra iteration only for degenerate input.

**Cause.** Both central helper implementations entered the shared loop with
LastSep = 0, whose LastSep <= Length(Self) condition treated an empty string as
one field. In Delphi, empty source is a distinct early invariant before separator
search.

**Repair.** The two master overloads, for character and string arrays, return
nil before result allocation when Self is empty. Wrappers, quote parsing,
options/count, and nonempty hot path are neither duplicated nor changed.

**Validation.** tdelphisplitempty1 passes with one source under Delphi 12.2 and
MoonCompiler, covering char/string separators, None, ExcludeEmpty,
ExcludeLastEmpty, Count, quotes, empty separator arrays, and nearby nonempty
forms. Current Win64 RTL passed O-/O2/O3; permanent repair gate is 74/74.

## Delphi-default BOM for TStrings

**Symptom.** A new TStringList saved TEncoding.UTF8 without EF BB BF, whereas
Delphi 12.2 writes a BOM by default. The difference also covered empty text:
Delphi saves one preamble while ours saved an empty stream.

**Cause.** SaveToStream(Stream, Encoding) already correctly checked WriteBOM
and wrote Encoding.GetPreamble. The initial option set was wrong: soWriteBOM
was absent and soPreserveBOM implicit. Thus a new object started
WriteBOM=False, and loading a BOM-less file fixed that outcome; Delphi starts
WriteBOM=True and does not change it while reading.

**Repair.** Initial options match Delphi: soWriteBOM, soTrailingLineBreak,
soUseLocale. Serialization and conversion path are unchanged. Explicit
WriteBOM=False still disables preamble; FPC soPreserveBOM remains explicit
opt-in for applications that must reproduce a source file's BOM.

**Validation.** tdelphistringlistbom1 runs from one source under Delphi 12.2
and MoonCompiler. It covers UTF-8/UTF-16, empty/nonempty list, explicit disable,
files with/without BOM, and FPC-control soPreserveBOM. Pre-fix exact binary
exited 1; after repair O-/O2/O3 and shared Win64 repair gate 74/74 are green.
The full self-host compiler, RTL, and package build completed with the new
toolchain.

## Unicode strings in Variant

Delphi 12.2 assigns string, UnicodeString, and ASCII/non-ASCII literals to an
ordinary Variant as varUString. MoonCompiler produced varOleStr and varString
for ASCII; changing only the tag made two varUString values fail comparison with
EVariantInvalidOpError, and VarArrayOf then failed writing varUString to Variant
SAFEARRAY with EVariantTypeCastError.

The three causes were VarFromWStr producing BSTR, overload lookup passing
nothingn and losing the rule that an untyped string literal in Delphi Unicode
mode is Unicode, and MapToCommonType not classifying supported varUString.
Actual tnodetype now reaches normal overload ranking; Unicode assignment clears
the old Variant and creates standard varUString without extending TVariantManager.
Common-type/compare/concat support it; concat preserves left subtype
varUString/varOleStr/varString. SAFEARRAY converts Pascal-managed varString and
varUString to BSTR because it cannot own Pascal strings, and Delphi returns
varOleStr from its element. On Linux WideString and UnicodeString are one RTL
type, so normal Unicode Variant remains physically varOleStr: this explicit ABI
boundary changes neither text semantics nor SAFEARRAY BSTR contract.

tdelphivariantstring1 covers variables/literals/casts, ASCII/Unicode, empty,
NUL, surrogate pair, procedure/function/property/concat, copy/overwrite/clear,
complete Unicode/Wide/Ansi concat matrix, comparison, VarArrayOf and Variant
array element write; a tiny Delphi oracle confirms SAFEARRAY subtype. RTL passes
O-/O2/O3 and full Devil proceeds past language layer without runtime crash.

## Explicit Variant to RawByteString

Legacy and supplementary mORMot use RawByteString(Value) for Variant-to-UTF-8.
MoonCompiler had AnsiString/UTF8String operators but rejected the explicit
RawByteString cast. RawByteString has distinct dynamic-codepage definition, so
the AnsiString result overload was not exact. Separate Variant/OleVariant result
operators in System RTL call existing VarToLStr; no compiler rule/path was
added. Delphi 12.2 confirms RawByteString(Variant) equals AnsiString(Variant)
in ANSI code page while UTF8String remains UTF-8.

tdelphivariantrawbytestring1 tests both Variant kinds and Ansi/UTF-8 controls
in O-/O2/O3 on Win64/Linux. It originally fixed only the Delphi cast, not whole
mORMot Unicode-default POSIX compatibility; product mORMot was later adapted:
application String/TFileName remain Unicode and raw UTF-8 appears only at POSIX
boundaries, without removing the old guard or introducing mixed ABI.

## Real-zero sign in CSE

Devil dvl-0053 was initially misdiagnosed as constant folding: -0.0 and
0.0 * -1.0 seemed to lose sign under O2/O3. O- and assembly showed correct
fold/emission; CSE replaced it with adjacent +0.0. trealconstnode equality used
mathematical equality (+0.0 = -0.0) despite noninterchangeable bits. Without
fast math, equal real zero constants now require equal signs. Arithmetic folding,
Currency, NaN/infinity, ordinary nonzero constants, and explicit fast-math
freedom remain.

Focused regression covers both neighbouring +0/-0 orders, seven folded
arithmetic forms, and runtime controls; Delphi 12.2 and MoonCompiler agree in
O-/O2/O3. Original Devil probe is fail-closed. Expanded Omni and integrated
Mega run native Win64 O2/O3 over six deterministic seeds with exact failure
sets/target oracles: 15 236 checks; 1 280 forms cross 20 integer-value sources,
eight operators, eight consumers, and eight contexts, including UInt64 +
inside overload, assignment, case, loop bound, index, nested routine, with,
try/finally, and re-entry.

## Win64 COFF bigobj 32-bit section number

Full Devil created one object with over 65 535 sections and link failed on
undefined $unwind$.... Microsoft bigobj already uses 32-bit SectionNumber, but
TCoffObjOutput.create_symbols stored objsym.objsection.index in local Word:
65536 became zero and emitted unwind section appeared missing. Only temporary
type changes to LongInt, matching existing writer. Ordinary COFF, unwind
generation, and optimization remain. run_win64_bigobj_unwind_gate.py generates
12000 actually invoked try/finally, checks header >65535 sections, and runs the
binary: pre-fix reliably undefined unwind symbol; repaired 72017 sections.

## Narrow extension after long-distance peephole

Three Devil families—narrow cast, generic-method return, and assignment in
with—could produce UInt64(Word(SmallIntValue)) =
$00000000FFFF8001 instead of $0000000000008001 in O3. with/generic only changed
AUTOINLINE/register-allocation decisions and reached one x86 peephole. The rule
removed movzx/movsx after mov narrow-constant,reg but widened early mov without
normalizing immediate. One helper masks by original 8/16/32-bit width then
performs signed/unsigned extension; no runtime instruction added. Permanent
run_devil_zeroext_gate.py reproduces seeds 1/24, 200 cases, five layers,
Debug/O1/O2/O3; 1268 checks agree and old dvl-0001/dvl-0026/dvl-0043 records
were removed from known-findings registry.

## Delphi-default stack for Win32/Win64 and Linux x86-64 TThread

Win32 and x86-64 Win64 target records inherited 16 MiB reserve while PE writers
committed 4 KiB; measured Delphi 12.2 PE32/PE32+ contract is 1 MiB reserve and
16 KiB commit, also used for StackSize=0 threads. One constants pair applies
only to system_i386_win32/system_x86_64_win64; target supplies reserve and
internal/external PE writers write commit. -Cs, {$M}, {$MAXSTACKSIZE}, and
{$MINSTACKSIZE} retain precedence; WinCE/AArch64 unchanged. 1 MiB is virtual
reserve, not physical use. qualification/win-stack-default/run.ps1 verifies PE
fields for internal/external linker and default/command-line/{$M}/explicit
min-max, runs four product binaries, and DCC32/DCC64 36.0 oracle is
1048576/16384.

Linux has no PE header: ordinary TThread.Create and size-less BeginThread use
DefaultStackSize passed by cthreads to pthread_attr_setstacksize. Product
Linux x86-64 changes it 4 MiB to 1 MiB; explicit constructor StackSize and
FPC_USE_SMALL_DEFAULTSTACKSIZE retain precedence. Main thread and third-party
raw pthread with no size retain inherited RLIMIT_STACK/pthread defaults; deeper
stack/guard stress is qualification research rather than a known runtime gap.

## Mandatory Linux x86-64 table-driven exception unwinding

Upstream enabled PSABI EH only with compiler define psabieh, producing two
normal-path cost variants and making product correctness depend on hidden driver
key. tf_use_psabieh is now unconditional Linux x86-64 ABI; build removes
-dpsabieh. Normal self-host build must define FPC_USE_PSABIEH, emit
.gcc_except_table, and use _FPC_psabieh_personality_v0; other architectures and
Win64 unchanged.

Frame-pointer CFI follows the actual local-frame layout: saved nonvolatiles live
in the local frame, so CFI emits after locals allocation from save_regs_ref,
not as pushes before prologue; otherwise unwind corrupts caller RBX. PSABI
runtime distinguishes an exception locally caught in finally from true replacement using LSDA action
chain/CFA, marking/deleting old refcount-zero wrapper only in latter cleanup and
never destroying same object. run_linux_psabieh_gate.sh, without PSABIEH keys,
compiles/runs O-/O1/O2/O3 normal try/except/finally, typed/catch-all, bare
reraise, managed-record/interface unwind, Exit/Break/Continue through finally,
replacement, nonvolatile restoration and thread; it separately checks ordinary
compiler error, unwind metadata, and no legacy exception-frame call on normal
path.

## Exact pin unit and cross-platform MM profile

--pinned-unit=<name>=<source> resolves exact source before PPU/package/search
lookup, so a product project containing another mORMot tree cannot rely on -Fu
order to prove which mormot.core.fpcx64mm compiled. Conflicting uses ... in is
rejected; permanent gate covers foreign source, stale PPU, ordinary unpinned
lookup, missing source, and explicit override. Under MOONBOT_MM_PROFILE_REQUIRED
bundled MM requires FPCMM_BOOSTER and FPCMM_MOONSHARD and forbids
FPCMM_DISABLE/FPCMM_STANDALONE, replacing the old unreliable GNU-ld symbol
contract on PE. Medium-arena ownership is target-independent: Linux mmap,
Win64 VirtualAlloc/VirtualQuery, one 2 MiB aligned-pool/owner lookup/
alloc-free-realloc invariant; both OS gates cover O2/O3, multiple owners,
cross-thread transfer, diagnostics.

### Safe Linux entrypoint start

Two independent errors affected Linux public builds. A pinned dependency
inside the build directory was excluded by service-directory filter; driver now adds passed
source root explicitly and filters only children. Separately, a program without
cthreads crashed initializing Unix because threaded RTL used allocator
per-thread path before setup. The full product prefix now inserts at FPC's early
heaptrc point: pinned MM, cthreads, cwstring, monitor manager, leaving dpr only
application units. Explicit late cmem, which previously replaced installed MM
and made diagnostic leak report live=0, now gets compile-time fatal; vanilla
opt-out and compiler-selected Valgrind/ASan retain deliberate cmem.
At the time qualification/build-driver/project_profile_gate.py ran
Debug/Release on both OS without manual runtime units, created actual TTask,
executed TMonitor, and required exact cmem diagnostic in normal/diagnostic-MM;
since the build driver's project part was retired (22.09.2026) the same
prefix is proven by the product smoke and product_config_gate.py over the
toolchain's fpc.cfg, and pinned-unit run.sh and run.ps1 still lock the ordered
prefix and the vanilla/Valgrind exceptions.

## Further Devil-derived repairs

Delphi Unicode literal/source-byte/byte-string fixes retain Unicode Char/
UnicodeString for ASCII literal, folded Chr, and ASCII addition, while explicit
set of AnsiChar, typed array of AnsiChar, and RawByteString can be byte contexts;
variables/value >255 do not narrow. tdelphiunicodeliteral1 covers literal, Chr,
#$, concat, constant, vtWideChar, byte set/array, ANSI controls; case AnsiChar
is explicit byte context; tobjfpcliteralcastoverload1 locks ObjFPC. Overload
ranking now selects AnsiChar over RawByteString for any ordinal character
constant (#0, boundary/named/folded Chr); a nonconstant WideChar prefers string
against AnsiChar but exact WideChar still wins. This is common comparator repair,
covered by exact mormot_unicode_char_overload.pas and Omni litov-*.

Unicode literal now retains both codepage-decoded Unicode value and exact source
bytes: under cp1251 #$85 is U+2026/UTF-8 E2 80 A6 in Unicode but byte 85 in
RawByteString/AnsiChar array. Metadata survives concat, named constant, PPU
replay; typed AnsiChar-array creates byte context only while parsing; PPU long
version 38 to 39 rejects stale PPU. tdelphibyteconstppu1 covers #$85, concat,
RawByteString, CP1251/UTF-8/typed array before/after PPU; external-name test
tdelphiunicodeexternalname1 confirms source encoding. Unix conversion tests use
cwstring since absent Unicode manager is not frontend semantics.

Byte concat distinguishes A + #$85 (raw byte) from A + Chr($85) (Unicode
U+0085 transcodes to CP of A, ? in CP1251). Byte domain now transfers only from
typed AnsiString to literalbyte-provenance node or ASCII; PPU/named #$ constants
retain bytes, folded Chr/WideChar do ordinary transcode; tdelphibytestringconcatdomain1
and Omni cover pair, wide cast, expected codepage. ASCII AnsiString('a') +
AnsiString(RuntimeValue) no longer calls host reverse Unicode map and cannot
EAccessViolation on headless Linux.

Explicit Delphi cast between AnsiString subtypes is an equal-conversion storage
view retaining pointer/bytes/codepage header; assignment transcodes. Only that
cast path changes, not implicit conversion/ObjFPC helper; tdelphibytestringcast1
covers CP1251 to UTF8/CP866/Raw view and actual transcode. Integer/Cardinal and
Int64/UInt64 overload pairs compare complete static source range after basic
ordinal-distance tie: fitting signed selects signed otherwise unsigned, solving
dvl-0028/dvl-0039; only these pairs, not var/out/Variant/ObjFPC/other sets;
opposed parameter requirements stay ambiguous. tdelphiintpair1 covers order,
subrange, widths/boundaries and ObjFPC control.

Parser maps both Delphi const [ref] and [ref] const to existing vs_constref,
adding no parameter kind/copy/lifecycle; tdelphiconstref1 checks real managed
record address, native constref, readonly/ObjFPC fail controls. Devil runner is
fail-closed: each build stores exit code; nonzero or missing terminal digest is
runtime-failed with output tail; unit test reproduces EVariantTypeCastError
false-green. Odd(UInt64 constant) now folds uvalue and 1 rather than reading
through Int64; tmoonoddconstu641 covers high-bit, High(UInt64), signed negative,
runtime. Under {$R-}, a source ordinal-constant fixed-array index is checked in
its source signed/unsigned domain before range adaptation; late optimizer
constants are not relabelled. PPU long version 37 to 38 serializes marker;
tmoonarrayconstindex1 and array_const_index_out_of_range.pas demand exact
failure, while tarrayconstafterinline1 O3 probes -1100..1100 against independent
case oracle. Global/static storage is excluded from local CONSTPROP; locals,
parameters, compiler temps remain; tmoonconstpropglobalcalls1 checks two calls,
count/result.

## Remaining public/runtime fixes

An inline void procedure can create first managed temporary after caller entry/
exit frame is fixed, causing IE 200405231. Before substitution this exact risk
keeps ordinary call only when caller lacks implicit cleanup frame; function
result with result slot/protected caller remains inline:
tmooninlinemanagedexprfinally1.pp. TCustomAttribute.Create is public so an
empty descendant inherits parameterless constructor; tmoonattributemarker1
compiles markers on type/field/property/method. Product SysUtils exports
TProc/TFunc/TPredicate through four arguments under product define only;
scoped macros retain normal FPC generic declarations; tmoondelphicallbacktypes1
creates/calls every arity.

Product RTL inherited Delphi RTTI defaults expose public fields/attributes
without RTTI EXPLICIT. Product Rtti facade presents Boolean as
TRttiEnumerationType, tkEnumeration for TRttiType.TypeKind/TValue.Kind, while
raw PTypeInfo.Kind=tkBool/storage remain since replacing kind byte would make
TypInfo read wrong enumeration data; exact dvl-0049 boundary. rtti_gettypes.dpr
checks fields/attributes/facade/name/TValue text/Variant/array on both x86-64.
Full record RTTI now requests every type reference actually serialized for
public method result/argument and property/indexed-property (same writer
filters), not only fields; rtti_generic_dependency_types.pas and mormot
IKeyValue<Integer,Int64> repro lock it. FPC TRttiInfo.RecordAllFields now fills
out RecSize, rejects nil field RTTI and accepts set only rkEnumeration rather
than numeric rkInteger, returning nil for whole unsafe record; mormot probe and
Delphi oracle JSON cover numeric/enum set/offset/RecSize. AnsiChar constant
preserves byte provenance in Delphi Unicode mode uchar only, fixing mORMot
EF+BB+BF BOM from becoming four bytes; tdelphirawbyteconst1, exact product repro,
Omni and Linux O2/O3 mORMot cover it.

ADD/LEA folding cannot remove 32-bit ADD before 64-bit LEA because eax/rax share
super-register but constant transfer required exact subregister: correct mORMot
@PByteArray(P)[PByte(P+1)^+2] was two bytes early. Disallow when ADD is narrower
than LEA; equal/narrow transfer compares super-register. tarraypointerindexoffset1,
semantic gate and 1007 Omni lea-index-* checks cover operands, subtraction,
base, scale, High(Cardinal)+2. Function Result loop counter hidden by retaining
enum conversion let O3 hoist Table[Result] before initialization; compare actual
target storage under conversion, preserving true strength reduction/cursor;
tstrengthresultcounter1 plus semantic gate/traces including -gt and FPC #39915.

x86-64 default FPU mask is Delphi $133F x87/$1F80 SSE; SetExceptionMask still
changes process default for threads/SysResetFPU and libraries retain host mask
through IsLibrary; mORMot ffLibrary/ffPascal explicit. fpu_default_mask_semantic
checks masks, reset, thread, Inf/NaN/unordered/overflow/invalid Int64 O-/O2/O3.
Default(StaticArray) with custom Assign now recognizes exact hidden default of
matching static record array and uses aligned zero heap buffer, phased init,
finalize/ownership move and try/finally guards, preserving valid destination on
Finalize throw, unwinding partial init, overflow and zero allocation semantics;
only Win64/Linux x86-64, other assignment lowering unchanged. Pins:
tdelphidefaultarray1, default_assign_safety_semantic, Omni mem-defaultop-*,
Devil dvl-0058: value 100, direct/field/index/generic PPU, single eval,
both exception phases, 32-byte alignment, 2MiB array on 1MiB stack.

resourcestring in typed string const materializes compile-time default text then
common destination conversion. SetResourceStrings retranslation updates only
native ABI slots (Ansi classic, Unicode Unicode RTL; Linux Wide=Unicode);
cross-ABI Ansi/Win64 BSTR Wide get default but no reference slot. RTL uses
RTLString. resourcestring_typed_const_semantic covers enum arrays, standalone,
Ansi/Unicode/Wide, Format, cross-unit PPU/retranslation/Omni. nil is not an
addressable var/out overload candidate even though pointer-compatible; pointer
lvalues remain. tdelphinilvaroverload1/full MoonBot repro/Omni cover nil, typed
nil, readonly/writable constants, const, lvalue forms/out write. Ranking now
uses pure valid_for_assign(apply_effects=false) after var_para_allowed type
compatibility, avoiding AST effects from losing candidate; closes function
result/property rvalues, set literal, foreign-codepage AnsiString/untyped
formal; winner gets existing mutating ncal, open array/inline out separate.
tdelphivarrankpure1 matches DCC64 declaration orders/lvalues.

TThread gains missing parameterless Create delegating Create(False), preserving
SysCreate/platform/default-stack/AfterConstruction/lifecycle; focused tests and
Omni/Mega verify immediate/suspended/run/WaitFor. TArray adds exactly Delphi
Copy<T> Count and SourceIndex/DestIndex/Count overloads delegating helper:
ranges then same backing array, System.Move unmanaged/assignment managed, no
destination create/expand; tdelphitarraycopy1/rtl_api_array_copy DCC/Moon test.
TFile.GetSize returns GetFileAttributesEx/stat size or -1 no exception;
tdelphifilegetsize1 covers missing/empty/seven-byte/Unicode/deleted/executable
on both platform Debug/Release. for var Item: PVariant in Values now terminates
type-only parsing at in and sets bt_var_type before colon; generic named pointer,
managed string/counting route common; tdelphiforvarexplicit1/Omni/MoonBot repro.

TMemoryStream SetCapacity is protected virtual and NativeInt in product Unicode
RTL (PtrInt bootstrap), no allocation/ABI change; capacity dispatch/API tests.
SetSize restores LongInt virtual wrapper plus Int64 implementation; narrow FPC
QWord bridge permits Int64 else range error, without global ranking change;
tdelphimemorystreamsetsize1 DCC source covers overloads, virtual slots, size,
shrink/position/QWord. SysUtils TextPos PAnsiChar/PWideChar clone/lower/StrPos/
translate pointer/free in finally; nil intentionally crashes like Delphi;
tdelphitextpos1/API cover. TDictionary.IsEmpty is inline FItemsLength=0 in
TCustomDictionary, no state/counter/hot branch; test and API gate.

## By-ref custom Variant and subsequent runtime repairs

TDocVariant late-bound property is varVariant or varByRef, so
ContainsText(Doc.data.response.payload.data,'}') failed UnicodeString conversion
with EVariantError and left response time stale. Strip carrier tags before
TCustomVariantType lookup for all scalar conversion/cast/compare/binary op;
normal Variant hot path retains inline tag checks, same-custom VarAsType is copy,
nil carrier error. VarCopyNoInd now ordinary assignment; its byref source stays
forbidden/unindirected. tdelphicustomvariantbyref1 covers carriers,
ANSI/Wide/Unicode, numeric/float/currency/date/Boolean, cast/compare/binary/nil,
VarCopyNoInd; mormot probe/Omni cover JSON chain. sysvartowstr also now finally
clears temporary TVarData returned from custom CastTo, avoiding one string ref
per conversion even on partial-init exception; regression requires heap return
to baseline.

TTask.WaitForAll/Any now tracks filled count not capacity, starts WaitForAny
sentinel -1, uses one finite-timeout deadline, and protects callback registration/
unregistration/signalling with one ownership protocol; infinite/main-thread
wait no polling. task_wait_semantic covers empty/nil/already-complete/mixed,
finite/infinite, winner, exception/cancel/races Debug/O2/O3. CheckSynchronize
need is decided over entire unfinished set, not first/current task, avoiding
interactive/noninteractive callback deadlock; both orders/waits regression.
TBaseWorkerThread creates suspended, initializes FRunningEvent/pool/ID then
starts; TerminatedSet signals same startup barrier if cancelled before Execute,
without sleep/polling/repeated SetEvent; thread_pool_lifecycle_semantic covers
immediate shutdown, repeated lifecycle, clean process exit. Shared IOUtils
restores GetDirectoryRoot, timestamp accessors, directory enumerator overloads
through platform primitives but does not claim Windows Encrypt/Decrypt portable;
ioutils_api_semantic covers roots/times/missing/enumeration/errors.

URL decoder now decodes %XX into raw buffer then materializes UTF-8 once,
avoiding process-codepage corruption of %D0%96; encoder aligns Delphi
space/plus/percent/query-unsafe/invalid escapes; url_encoding_utf8_codepage_semantic
covers Unicode/high bytes/NUL/CP_UTF8 boundary. Linux JSON serializer explicitly
depends on Api.Ffi.manager/libffi for RTTI Invoke; direct nonserializer Invoke
users still name manager; rtti_invoke_product_semantic imports only serializer
and tests class/record ctor/method, managed Unicode, exception. SHA512_224/
SHA512_256 reuse SHA-512 compression/finalization with FIPS IV and truncate 28/32
bytes; rtl_api_product_semantic covers abc/HMAC key/data plus SHA-256/SHA-512,
Base64, URL, threading.

## for step, managed construction, containers, streams, and final optimizer fixes

for ... step now measures physical distance. It evaluates step once in wide
unsigned domain (64-bit, 128-bit for 128-bit counter/step), raises range error
for runtime step<=0 before bound/counter/body, then uses rotated body/latch:
dist := bits(bound)-bits(i), modular increment, one step<=dist continuation
compare. No first flag/wrap detection/checked arithmetic; Q/R disabled only for
step nodes, continue through finally reaches latch. Natural exit leaves modular
first-past, empty leaves from. loopstep serializes PPU, strength reduction and
foreach/DFA preserve it. tforstep1..15, C-002 gate, latch ASM tforsteplatchasm1
and physical semantic test cover byte 256/257/512, Word 65536, Int64/QWord/
Int128/UInt128, enum R-, downto, error order, finally continue/break, Q/R,
O3, PPU and step 0/-N diagnostics.

C-003 gives every constructed managed value/storage one finalizer on every path,
none for failed Initialize. InitializeRecord becomes phased table try/except:
field throw reverses ready prefix; custom Initialize throw finalizes auto fields
but never record Finalize. InlinedInitialize replaces array helper. Openarray
copy owns alloc+init+assign, cleans content/buffer on failure. Scalar copy uses
flag + hidden caller managed TDelphiCopyGuard, fpc_delphi_finalize_copy and
disarm protocol across callee/funclet/unwind/normal done. Inline frame puts temp
creation/zero flags outside implicit try/finally, Init/arm/Assign/body inside,
and flag-gated finalizers. Inventory says 15 product Initialize+Copy/AddRef
families nonthrowing or no destination mutation; none in mORMot-product/MoonBot.
Pins record_init_unwind_paths_semantic, aggregate_init_unwind_semantic
(custom-record-op I1;OI;F1), record_management_operators_semantic and exact
declaration/reverse/array-forward order.

C-001 CheckArraySlice(Index,Count,Total) is one nonvirtual inline primitive:
SizeUInt(Index)>SizeUInt(Total) or SizeUInt(Count)>SizeUInt(Total-Index) raises
EArgumentOutOfRangeException before trivial exits/pointer formation; no
Index+Count. It fixes Copy/Sort/BinarySearch/TList.Exchange/Move, zero-count
BinarySearch insertion Index and same-index Move shortcut. O3 four instructions
lea/cmp,jb/sub/cmp,jnb; facades delegate. ListIndexErrorMsg now retains max/name
and message List index (5) out of bounds: TList<…> object range is 0..2.
TSortedList.Add handles zero-count SearchResult correctly. array_list_span_semantic
locks DCC matrix/state/messages/comparer/insertion/first Add; intentional DCC
deviations are safe Exchange both-index checking and Copy negative-source reject.

MemoryStream/TBytesStream state machine now validates capacity/seek/write/read/
SetSize before state publication: shared overflow-safe quarter growth/block
rounding; seek candidate before FPosition; DCC full-overflow Write behavior;
negative/sign/width validation; JSONByteReader 0->16->x2, wide SetString
flush/reset, DCC interning cache/input >1MiB, zero-allocation ctor. DCC
differences are zero-count Write no-op and protected SetCapacity below Size.
memory_stream_state_semantic/json_byte_reader_semantic cover rejected transitions,
state, round trip, 16/surrogate/double flush/cache; ParseJSONValue UTF8-option
loss in CreateParser remains codec-block finding. Empty-literal equality now uses
other operand domain only for =/<>, avoiding RawUtf8 64KiB Unicode conversion;
ordering unchanged. string_empty_compare_semantic plus O3 call ban preserve
behavior/JSON 1.047x->0.659x.

AUTOINLINE unit cycle B interface->A/A implementation->B with private static
class var SymId=-2 now registers symbol in declaring module symlist before
cross-module reference; later registration does not duplicate. Repro
o3-indysecopenssl-provider runs -O2/-O2 AUTOINLINE/-O3 and prints
O3_AUTOINLINE_CYCLE_OK; old compiler EListError in AUTOINLINE modes. CONSTS now
runs only with REGVAR so -OoNOREGVAR cannot reuse persistent FP 0.5 temporary;
tconstsnoregvar1 two-dimensional Advect. Cardinal fast path matches exact VType,
so varLongWord or varByRef/array cannot read pointer bits; test covers Variant/
OleVariant changes. OleVariant QWord/Int64 now call VarToWord64/VarToInt64 in
right order; tdelphiolevariantint641 DCC boundary controls. Direct inherited
binding stays only Object Pascal helper; ordinary class property retains virtual
dispatch, tinheritedabstractproperty1 plus helper test. After inline condition
fold, constant propagation firstpasses only reachable if branch; tinlineenumguard1
checks O3 Cr false/boundary true; tmoonarrayconstindex1 remains compile-fail.

## FMTBcd Variant conversion

`TFMTBcdFactory.Cast` was an unconditional `not_implemented` stub, so ordinary
`VarAsType(Value, VarFmtBCD)` raised `EBCDNotImplementedException`. The factory
now follows the Delphi 12.2 custom-Variant dispatch contract: it first owns or
resolves the source carrier, parses text directly, converts other scalar values
through `varDouble`, and only then publishes the owned BCD payload. In-place
casts and by-reference Variant carriers use the same path. The Delphi oracle
and MoonCompiler Debug/O2/O3 checks are in
[`fmtbcd_variant_cast.pas`](../qualification/suite/tests/smoke/fmtbcd_variant_cast.pas).

## Mutation-safe messaging clear

`TMessageClientList.Clear` freed its storage without resetting `FCount`, so the
next `Add` indexed a zero-length array using the stale count. Clear now resets
all list state. During notification it uses the list's existing delayed-disable
protocol instead of mutating indexes: current listeners are disabled, newly
added listeners remain live, and compaction occurs when the outermost update
ends. [`message_client_list_clear.pas`](../qualification/suite/tests/smoke/message_client_list_clear.pas)
checks ordinary reuse, clear from a callback, skipped old listeners, and a new
listener becoming visible only to the next notification on both targets at
Debug/O2/O3.

## Ownership of inlined managed results

O3 AUTOINLINE could remove the assignment that made a managed function result
own its value. Returning a dynamic array or string from a global, field, or
parameter then passed a borrowed pointer to a `const` consumer; invalidating the
source inside that consumer exposed freed or reused storage. A borrowed source
now keeps the acquiring result temporary wherever its value goes to a routine,
while a code-generation gate keeps fresh dynamic-array forwarding zero-copy.

The temporary is dropped when the source already owns the value (a function
result, a string literal) or when the consumer finishes reading the value
before any code can run that could change the source (`mark_funcret_borrow` in
`compiler/optcall.pas`): an operator, `Length`/`High`, the step of
`Inc`/`Dec`, a store without a helper, the string helpers (compare, assign,
concatenate, convert, `Copy`) and the dynamic-array assignment, reached through
an element or character selected by an index without calls, a field or a
compiler conversion, while the other operands run no code either. The consumer
is asked again where it appears only as an enclosing inline routine is
expanded. The first form of the guard kept the temporary for every consumer
but `Length`/`High`: `List[I] = Key` over a `TList<string>`, `B.Name[I]` or
`B.Data[I]` in a loop took an atomic reference, a release and an implicit
cleanup frame for each read that the release read directly. A call argument,
a pointer to the value, an index or operand that calls a routine keep the
reference; Delphi 12.2 drops it there as well and lets RR-06 read freed storage.

A managed temporary asks for the implicit `try..finally` of its routine in its
first pass, and the request outlived a temporary that inlining removed again:
an empty cleanup frame and a call of an empty finalizer stayed behind.
`TransformNodeTree` now asks the final tree again - managed locals and
parameters, managed temporaries, outlined `finally` bodies.

The consumer's permission was not enough where the inlined getter's block held
temporaries of its own around the result: `Self` of a getter whose object
another call returned (`L[I].Name`, `B.Child.Name`: the call is loaded into a
temporary of the call's init block before the result temporary exists), and
`Self` or an index that the inliner copies into a parameter temporary (a list
or a record held in a field or a unit global: `FNames[I] = Key`,
`FRecs[I].Name`). Their deletion stood between the result assignment and the
result's release, and `optimize_funcret_assignment` kept the result
temporary, its reference and the cleanup frame - in the release as well.
Such a temporary that the source reads is now released to normal like the
result temporary itself, and the value carries it to the consumer. Only a
managed result is rebuilt this way: the result temporary of a value without
finalization is a register freed where the source's temporaries die, and
reading the source later only lengthens their lives. A temporary read twice,
one with finalization, or one read inside a call keeps the result temporary:
the inliner puts a temporary argument into the body as it stands, so
`OwnerOf(Self).FName` with an `OwnerOf` that reads its parameter three times
would read the released temporary three times (the compiler stops with an
internal error; the chain test holds this form).

A record or static array with managed fields that an inlined getter returns by
value (`L[I].Price` of a `TList<TQuote>` whose `TQuote` holds a string) was
copied whole for every read: `fpc_initialize` of the result temporary,
`FPC_COPY` through the RTTI of each field and `fpc_finalize` in an outlined
finalizer - three RTL calls and a cleanup frame to read a `Double`. The lowered
copy `fpc_copy_proc(@source, @result, rtti)` is now recognized like the string
and dynamic-array assignments, under the same permission of the consumer, as
long as the copy runs no code of the program: no management operator in the
type or in a nested record, no interface (`_AddRef`/`_Release`) and no variant
field. A call argument (`Sink(L[I].Symbol)`), `with L[I] do` and two getters in
one expression (`L[I].Price * L[I].Qty`: the other operand is still a call when
the consumer is asked) keep the copy.

The semantic matrix
[`inline_managed_getter_borrow_semantic.dpr`](../RTL-test/semantic/inline_managed_getter_borrow_semantic.dpr)
changes each source right before and after the expression and replaces it
inside each escaping consumer, and
[`inline_managed_getter_chain_semantic.dpr`](../RTL-test/semantic/inline_managed_getter_chain_semantic.dpr)
does the same for the chains, the lists in fields, a computed index and a
record getter;
[`inline_managed_record_getter_semantic.dpr`](../RTL-test/semantic/inline_managed_record_getter_semantic.dpr)
for the fields of records in a list and a static array of strings, with the
records whose copy runs code of the program counted per read;
`qualification/optimizer-core/getter-borrow` counts the instructions and calls
of these forms against a recorded reference.

## Unicode equality at the call site

On x86-64, ordinary `UnicodeString` equality now checks pointer identity and
length in the caller. Only equal-length distinct buffers call the compact content
helper, which tail-calls `CompareWord`; complex or side-effecting operands retain
the single-call path. The semantic matrix covers 2049 pairs, embedded NULs and
single evaluation of each operand. The focused Win64 median improved by 1.35x
for identical pointers, 1.49x for different lengths, 1.11x for unequal
equal-length payloads, and 1.07x for equal distinct buffers.

## Reciprocal-overflow boundary of ArcCscH

`ArcCscH` includes the exact rounded reciprocal-overflow boundary in its
logarithmic fallback for Single, Double and Extended. The tests exercise
masked and unmasked overflow, both signs, the exact boundary and nearby values.

## The final exponent bit of IntPower

`IntPower` no longer squares the base after consuming the final exponent bit
and represents the magnitude separately, including `Low(LongInt)`. Tests cover
masked and unmasked overflow and a dense power matrix.

## Per-worker state of parallel loops

`TParallel.For` now reserves each adaptive-stride range from one stride snapshot,
creates loop state per worker, and checks `Break` against the current iteration.
Debug/O2/O3 tests cover Integer/Int64 reservations, explicit stride and state.

## Logical entries of aggregate exceptions

`EAggregateException` enumerates logical entries rather than backing capacity;
Debug/O2/O3 tests exercise capacity larger than the number of exceptions.

## Task cancellation waits for callback completion

Task cancellation uses `Canceled` as a request and `Complete` as confirmed exit:
queued callbacks become terminal without running, a running callback is joined
before cancellation is reported, and dequeue/cancel races are resolved under the
task state lock. Debug/O2/O3 tests cover created/queued/running cancellation
and all three wait APIs.

## Runtime Format dispatch without a literal pre-scan

The Unicode entry point and general Format parser no longer scan the template
for a percent sign before their normal dispatch. Exact `%s`, `%d`, `%u`, and
`%f` specializations remain; other forms enter the existing parser. Ordinary
calls such as `Format('order %d: %.3f', [Id, Price])` avoid redundant scanning.
No compiler rewrite or expanded caller code is involved.

The explicit trade-off is a runtime template containing no percent sign. In
the measured four-placement families, a 47-character literal was about 2.45x
slower on Win64 and 1.85x slower on Linux. The Unicode simple parser still
returns the original string without copying it. Exact integer formatting
improved by about 9–10% on Win64 and 5–6% on Linux. Tiny changes in unaffected
cases are not attributed to an algorithmic improvement: fresh-process A/A
controls retain their placement and scheduling variation.

`RTL-test/semantic/format_runtime_semantic.dpr` checks 4970 outcomes through
Unicode, Ansi, Wide, FmtStr and bounded FormatBuf calls, including runtime
templates, explicit settings, width/precision/indexing, COW, embedded NULs,
surrogates, errors and literal inputs. The dispatch change passed baseline
and candidate O-/O2/O3 on Win64 and Linux.

## Re-resolving loaded units after a used unit is recompiled

An incremental rebuild of the compiler sources after an interface change in
`aasmtai.pas` crashed the compiler with an access violation in `tdef.typename`
(the product IDE compiler twice at the same note, a stand compiler once);
under heaptrc with released memory kept the crash is deterministic. The task
scheduler recompiles a unit from source in a second round after modules that
use it were already loaded from their PPUs or compiled from source, and marks
them for a re-resolve (`tppumodule.re_resolve`). The re-resolve skipped every
module loaded from a PPU: it asks `is_deref_built`, and that flag was set only
by `buildderef`, which runs when a PPU is written, never when one is read. Such
a module kept its pointers into the freed symtables of the recompiled unit
until the first typecheck touched one. `tstoredsymtable.deref` and
`derefimpl` now record that the deref data is present after any pass, so a
loaded module is re-resolved like a written one; `create_class_helper_for_procdef`
adds a procdef to the helper procsym once, since `derefimpl` may run again.
The same code is in FPC main (ctask rework of 2026). A second finding of the
same investigation: the compiler sources built against the product Unicode
system unit (`Char = WideChar`) produce a compiler that corrupts its heap while
parsing its options; `globtype.pas` refuses that ABI at compile time.
[compiler_selfbuild_gate.py](../qualification/build-driver/compiler_selfbuild_gate.py)
proves both (the refusal, and an incremental rebuild of the compiler under
heaptrc after the interface change, with an identical self-host of the
result) and runs in the stand chains.

## A unit compiled from its sources is compiled again, not reloaded

`math.pp` compiled by name next to an existing `types.ppu`, after a change in
the body of a Math routine, crashed the compiler: an access violation at `-O3`
in a release build, internal error 200306031 in a debug build, and with some
verbosity settings nothing at all - the program linked afterwards ran with the
old routine body. Types uses Math in its implementation and Math uses Types in
its interface. `types.ppu` recorded the implementation crc of Math, so Types
was compiled again from its sources and its old definitions were freed. By
then Math had parsed its implementation and waited for the crcs of the units
it uses (`ms_compiled_waitcrc`); the scheduler flagged it for a reload. A
reload re-resolves what has deref data, and a unit compiled from its sources
in the same run has that for its interface only - the definitions of its
implementation and the node trees it keeps for inlining get theirs when the
ppu is written. The tree of `Math.CompareValue` went on naming the freed
`TValueRelationship`, Types inlined it into `TRectF.IsEmpty`, and the first
typecheck of that node read a dead tdef.

Such a module - compiled from its sources, implementation parsed, waiting in
`ms_compiling_waitfinish` or `ms_compiled_waitcrc` - is now compiled again
where the scheduler would reload it (`tppumodule.reload_needs_recompile`, used
by `continue_module`, `reload_module` and `check_do_reload_cycle` of
`ctask.pas`). In a reload cycle the recompiles come first and end the round: a
recompile resets the module's interface and uses, so what the cycle check had
established for the other flagged modules no longer holds (the first version
of the fix reloaded them in the same round, and the incremental rebuild of
the compiler stopped with internal error 2026022413 on `aasmsym` behind the
recompiled `aasmtai`); they keep their flag and are reloaded, or compiled
again, when the scheduler reaches them. The price in the incremental rebuild
of the compiler after the `aasmtai.pas` interface change is in the journal of
the code placement work; the self-build gate (heaptrc, identical self-host)
passes.
[cyclic-unit-impl-change](../qualification/suite/tests/compiler-crash/cyclic-unit-impl-change/README.md)
is the minimal pair of units; `run_service_regressions_gate` builds it, changes
the body, compiles the unit by name, builds again and expects the new body's
result at `-O-`, `-O2` and `-O3`.

## Independent PPU header and payload versions

The code-placement work added `fixedfill`, `padbytes` and `purpose` to the
serialized `tai_align_abstract` payload. Its first two commits incorrectly
incremented the byte-sized `CurrentPPUVersion`, which is reserved for
`tppuheader`, while leaving `CurrentPPULongVersion` unchanged. An unrelated
future header version could therefore collide with a different TAI payload.

The header version remains 208. The two already-used alignment payload formats
occupy long versions 44 and 45; the current format is 45.
[`ppu_format_contract.py`](../qualification/build-driver/ppu_format_contract.py)
pins the two domains and verifies symmetric alignment-field serialization.
A compiler with the corrected format rejects a version-43 product PPU as
`Invalid Long Version` and accepts the rebuilt version-45 units.

## Prefix padding respects the x86 instruction-length limit

The internal assembler can move branch padding onto legacy instructions as
ignored DS prefixes. It previously gave every eligible instruction up to
three bytes without considering the instruction's unprefixed size. A legal
13-byte instruction could become 16 bytes, beyond x86's architectural
15-byte limit.

Each target TAI now publishes its actual safe prefix capacity:
`min(3, 15 - unprefixed size)`. Branch windows, target-block simulation,
capacity checks and final pad realization consume the same value, and
`pad_prefix_set` rejects an oversized assignment. The branch-pad gate
disassembles the placed fixture and rejects every instruction longer than
15 bytes in addition to its existing semantic and placement contracts.

## TEncoding.UTF8 decodes UTF-8 on every target

**Symptom.** `TEncoding.UTF8.GetString`, `GetChars` and `GetCharCount` gave
Latin-1 text for UTF-8 input in a program without a code page manager (a plain
Unix program that does not use `cwstring`): every byte of a Cyrillic letter
became a character of its own. Where a manager was installed the text was
right, but each decode was an OS or iconv call on a temporary `UnicodeString`
(1248 ticks for 20 Cyrillic letters on the Ryzen).

**Cause.** `TUTF8Encoding` overrode only the encoding direction. Decoding fell
back to `TMBCSEncoding`, which hands the buffer to `widestringmanager`: on
Windows `MultiByteToWideChar`, under `cwstring` iconv, and without a manager
`DefaultAnsi2UnicodeMove`, which widens byte for byte.

**Repair.** `TUTF8Encoding.GetCharCount`/`GetChars` decode with the RTL's
`Utf8ToUnicode` after a run of bytes below $80 taken eight at a time;
`TEncoding.GetString` decodes straight into the result string, and
`GetChars` into a caller's array is given the exact character count so the
decoder's terminator cannot land behind the text. The replacement of invalid
input by U+FFFD is the one Windows gave: all sixteen shapes checked match.

**Validation.** [encoding_utf8_semantic.dpr](../RTL-test/semantic/encoding_utf8_semantic.dpr)
pins round trips, the sixteen invalid shapes, count against decode, spans,
the caller's array and the encoder's ASCII run; it passes on the RTL before
and after the repair (the Windows answers were already these).

## Integer min/max through an operand that can raise

**Symptom.** `If Candidate < Distance[J] then Distance[J] := Candidate` and the
same update through a pointer or a class field compiled to a compare, a jump, a
store and a second load instead of `cmp`/`cmov`/`mov` (Pulse
`kernels/dijkstra-64` 11.1 -> 12.1 cycles per operation on Zen 3).

**Cause.** The range-check repair of `Min(A[I], Low(Integer))` asked the
rewrite `if a<b then x:=a else x:=b -> x:=min(a,b)` to refuse every operand
that can raise an exception. The rewrite itself drops nothing: the comparison
of the source statement evaluates both operands unconditionally before anything
else, and so does the intrinsic, so a range check or a nil dereference raises
in both forms. The place that drops an operand is the fold of the intrinsic
with a constant that decides the result (`min(x, Low)` -> `Low`), in
`tinlinenode.simplify`.

**Repair.** The exception check moved to that fold: a min/max folds to its
constant operand only if the other operand has no observable effect, a
mandatory exception included (eight integer sites, six floating-point sites).
The rewrite accepts integer operands that can raise again; real side effects
(calls, assignments, volatile reads) still forbid it; the floating-point
operands followed (next entries).

**Validation.** [trangefoldobservable1.pp](../tests/test/cg/trangefoldobservable1.pp)
keeps `ERangeError` for `Integer`, `Cardinal`, `Int64` and `QWord` operands of
the deciding-constant fold and for the update form; with the rewrite enabled
and the fold unguarded it fails at -O2. [tobservableintrinsics1.pp](../tests/test/cg/tobservableintrinsics1.pp)
checks element, pointer-target and class-field updates: values, `ERangeError`,
`EAccessViolation` on nil, two calls of an effectful operand; the focused gate
requires `cmov`, the range-check call and no jump in the unchecked forms.

## Real constants met after inlining

**Symptom.** A real operation whose operands became constants only after
inlining or constant propagation stayed an instruction: `Scale(X, 4.0)` with the
body `X * (K * 0.5)` loaded 4.0 and multiplied twice, `PickBig(X, 50.0)` with
`if Limit > 100.0` compared two constants and kept both arms, `Lerp(1.0, 3.0,
0.5)` and `Clamp01(0.75)` computed a known value (-O3, Win64 and Linux; the
release and Delphi 12.2 fold all four).

**Cause.** The repair of the checked folds (`23424ec1d`) let the compiler
compute two real constants only in a constant expression of the source: an
operation after inlining could raise, set a status flag or depend on the
rounding mode. The same ban covered the real intrinsics except an exact square
root and the real conversions except exact ones. Every run of the product
starts in one FP state - round to nearest, all exceptions masked, neither DAZ
nor FTZ, the x87 at full precision (`DefaultMXCSR`, `Default8087CW`) - and there
an operation on ordinary numbers has one value and raises nothing but inexact;
a program that changes the rounding or the precision mode already gets the
constants of its source computed in that state.

**Repair.** One rule for a constant operation the program performs at run time
(`ncon.pas`, `is_ordinary_real` and `fold_ordinary_real`): it is folded when its
operands and its result are zero or normal numbers of their formats above the
smallest one, and it is computed in the format of the operation as the
instruction computes it - Single and Double by the SSE of the compiler, the x87
formats only by a compiler that has an x87. A NaN, infinite or subnormal operand
or result - a division by zero, an overflow, an underflow, the root of a
negative, `Trunc` outside Int64 - leaves the operation to run time, where a
program that unmasked the exception gets it; so does the smallest normal number:
x86 detects tininess after rounding with unbounded exponent, and a product that
rounds up to it (`4.4501477170144023e-308 * 0.5`, a Double that rounds to the
smallest normal Single) underflows. The rule serves `+ - * /` and the comparisons
of two constants, an integer division with a real result, `Sqr`, `Sqrt`, `Trunc`,
`Min`, `Max` and the real conversions; `Exp`, `Ln`, `Sin`, `Cos`, `ArcTan`, `Frac`
and `Int` are computed by the RTL routines of the compiler - the ones the program
calls when the compiler runs on its target; a cross compiler uses its host RTL,
as for the constants of the source - and folded for a normal non-zero result (an
underflow inside a routine whose result is ordinary is the routine's: genmath's
`Sin` on Win64 squares a tiny argument, the x87 `fsin` on Linux does not);
`Round` stays at run time. A folded constant keeps the run-time
provenance, so a later typecheck of its parent does not treat it as source.
The release computed the same folds in `bestreal`, which the Linux compiler
holds in the 80-bit x87 format: a Double operation was rounded twice and came
out one unit below the SSE result for halfway cases such as
`1 + 1.1102230328969627e-16` and `1.0977456781970063 * 1.4521756245746542`.
Delphi 12.2 folds the same way and is one unit off in the same cases.

**Validation.** [tfoldruntimereal1.pp](../tests/test/cg/tfoldruntimereal1.pp)
calls every inline helper with a grid of constants (zeros of both signs, normal,
inexact, the largest and the smallest normal, a subnormal, infinities, NaN, the
halfway operands; Single and Double) and with the same values at run time and
compares 5073 results bit for bit, then unmasks the exceptions and requires the
trap of fourteen exceptional constant operations (four of them round up to the
smallest normal number); it passes at -O-, -O2 and -O3 on both targets. Under
Delphi 12.2 the same program reports 20 values one unit off, `Abs(-0.0)` folded
to -0.0 and thirteen traps not raised; the release does not compile it (`Trunc`
of 1e30 after inlining is a range error) and without that line reports 21
values one unit off, three min/max of NaN and five NaN results that differ from
the run-time ones, and thirteen traps not raised.
[tobservableintrinsics1.pp](../tests/test/cg/tobservableintrinsics1.pp) now
requires the folded root and conversion to equal the run-time ones in the
product state instead of following a changed rounding or precision mode, keeps
`Round`, the subnormal operand (with its status flags, DAZ on and off) and the
root of -1 at run time; the focused gate requires the folded root and
conversion and a `sqrtsd` for the root of -1.
[real-folds](../qualification/optimizer-core/real-folds) requires the folded
forms in the -O3 object and keeps their instruction counts.

## Real min/max through an element or a field

**Symptom.** The best price of an array, `If A[I] < M then M := A[I]`, compared
and jumped on every element instead of `minsd`, and the range of a candle,
`If V < P^.Lo then P^.Lo := V; If V > P^.Hi then P^.Hi := V`, compared twice
with jumps instead of `minsd` and `maxsd` (the release gives both forms without
a jump).

**Cause.** The repair of `Min(A[I], Low(Integer))` let a real operand into the
rewrite `if a<b then x:=a else x:=b -> x:=min(a,b)` only as a constant, a
variable, a temporary or a field of a record variable: an element or a
dereference was refused. The rewrite evaluates a real operand exactly as the
comparison of the source does, once, and `minsd` gives the source's choice for
a NaN and for zeros of both signs; the integer operands were let back for the
same reason (the entry above).

**Repair.** A real operand takes the rule of an integer one: only a call, an
assignment or a volatile access forbids the rewrite. The inclusive comparisons
`<=` and `>=` of reals stay a branch (see "Branch-exact inclusive floating
selection").

**Validation.** [tfoldruntimereal1.pp](../tests/test/cg/tfoldruntimereal1.pp)
scans three-element arrays of zeros of both signs, NaN and +-1 in every order,
widens a range through a pointer and lowers an element, and compares every
result with the same choice made through a Boolean the rewrite does not see;
[tobservableintrinsics1.pp](../tests/test/cg/tobservableintrinsics1.pp) keeps
`EAccessViolation` for a nil holder; the real-folds gate requires `minsd` in
the scan and `minsd`/`maxsd` without a jump in the range update.

## Real identities with zero

**Symptom.** `X * 0.0` and `0.0 * X` gave +0.0 for a negative `X` and for a NaN
or an infinite one, `0.0 / X` gave +0.0 for a negative, zero or NaN `X`,
`0.0 - X` turned the sign of a NaN, and `X + 0.0` and `0.0 + X` gave -0.0 for
`X = -0.0` - where the same operation at run time gives -0.0, NaN or +0.0. The
release and upstream FPC do the same; Delphi 12.2 folds the multiplications and
additions too and differs from its own run-time result the same way.

**Cause.** The block of `taddnode.simplify` that its comment reserves for fast
math has no fast-math condition, and for `0.0 + X` the condition is inverted.

**Repair.** The identities that hold for every operand, a NaN, an infinity and
the sign of zero included, in round to nearest - the rounding every run of the
product starts with; rounding down makes `+0.0 - (+0.0)` a -0.0 - stay:
`-0.0 + X = X`, `X - (+0.0) = X`,
`X + (-0.0) = X`, `1 * X = X`, `X / 1 = X`, `2 * X = X + X`, and `X + (+0.0) = X`
for an `X` that is never -0.0 - a sum or a difference with a non-zero constant,
whose exact zero rounds to +0.0. The others are fast math rules and are applied
only with fast math. The price is an operation that stays where a program
computes with a constant zero: `X * 0.0` keeps its multiplication.

**Validation.** [tfoldruntimereal1.pp](../tests/test/cg/tfoldruntimereal1.pp):
the products and quotients of zeros with infinities and NaN in its Single grid
(12 results differed before); the real-folds gate runs `X * 0.0` for -1 and NaN
and requires the multiplication.

## The square of an operand that can raise

**Symptom.** `Sum := Sum + A[I] * A[I]` loaded the element once and multiplied
a copy of it: `movsd x1; movapd x2,x1; mulsd x2,x1` instead of `movsd x1;
mulsd x1,x1` - one more uop per iteration of the variance loop of
`heartbeat/correlation-32x256`, and four more bytes that moved the loops behind it.

**Cause.** The repair of the folds that drop an operand (above) also made
`x*x -> sqr(x)` refuse every operand that can raise. The element access then
stayed twice in the tree, common subexpression elimination loaded it into a
temporary that must not be overwritten, and the multiply copied it first. The
fold drops nothing observable: `sqr(x)` evaluates `x` once where `x*x`
evaluates it twice, and an exception of `x` is raised by the first evaluation in
both forms.

**Repair.** The fold refuses only operands with real effects (calls,
assignments, volatile reads) again, as before that repair.

**Validation.** [sqr-fold](../qualification/optimizer-core/sqr-fold/README.md) runs
the square at -O2 and -O3 (value, `ERangeError` of a checked operand, two calls
of an effectful operand, a `Volatile` operand) and requires `mulsd xmmN,xmmN`
without a copy in the loop and two reads of the volatile operand. The repair of
the folds that drop an operand keeps its tests: the fold of `x*x` drops none.

## A deciding constant on the left removes the arm it guards

**Symptom.** A generic routine that tests the kind of `T` and a run-time flag in
one condition kept the arms of the other kinds in every specialization:
`TList<Integer>.IndexOf` carried the whole `UnicodeString` search loop as
unreachable code, with seven saved registers and a larger frame instead of four
(Pulse `rtl/generic-list-indexof` 135.8 -> 143.5 cycles per operation).

**Cause.** `False and X` was pruned at tree level only if `X` had no observable
effect, a possible exception included, and a read of `Self.Field` counts as one
(nil `Self`). Under short boolean evaluation `X` is never evaluated once the
left operand decides the result, so nothing observable is dropped with it. With
the tree left alone the constant was found only by the code generator, which
jumps over the arm but keeps its code, registers and frame.

**Repair.** With short boolean evaluation `False and X` and `True or X` are
pruned whatever `X` contains; with complete evaluation (`{$B+}`) the effects of
`X` still decide. The constant has to stand on the left: `X and False` evaluates
`X` first, and that read stays (it goes as well since the repair below, unless
`X` carries an exception the program asked for). The generic containers now
test the kind of `T` before the comparer flag.

**Validation.** [tshortboolprune1.pp](../tests/test/cg/tshortboolprune1.pp):
a never evaluated call is not made and a nil object is not read under `{$B-}`,
the call is made exactly once under `{$B+}`, and the focused gate requires that
every specialization of the generic keeps only the arms of its own kind (the
compiler before the repair keeps all three).

## A fold asks what it does with the evaluation

**Symptom.** With range and overflow checks off - the product profile - folds
that drop no exception of the program still refused every operand read through
memory. A digit test of an element, `(S[I] >= '0') and (S[I] <= '9')`, kept two
compares and two branches instead of one unsigned compare; a rotate of record
fields stayed `shl`/`shr`/`or`; `P^.X - P^.X mod 8` read the field twice;
`InternalItems[0]` of `TFPSList` loaded the item size to multiply it by zero; a
generic routine that tested a field before the kind of `T` kept the arms of
the other kinds; `x*x` squared a copy (the square, above). Against main the
repair shortens 84 functions of the RTL and packages by 249 instructions on
Win64 (85 and 247 on Linux) - range tests in 39 of them, the square in 20,
`ror` in SHA-256, the `fgl` lists, UCS-4 conversion - and 14 functions of the
Pulse programs (heartbeat `ScanInt64`, `ScanAmountE8`, `CorrelationDigest`,
the JSON scanners of mORMot). Two functions got one more register move: a
constant reaches `min` again, as in the release, and the `min` code computes
into a temporary.

**Cause.** One flag, `mhs_exceptions`, answered three questions, and
`check_for_sideeffect` counted every element access, dereference and class
field under it, checks on or off: upstream it means "exceptions (overflow,
sigfault etc.)". Twelve folds of the release asked it, three of them to
evaluate a short-circuit operand where the source did not - there a read can
fault where the program never read. The repair of the folds that drop an
operand (`Integer min/max`, above) and four repairs of the same days asked the
same flag in 38 more places (50 calls in main): folds that drop nothing (one
evaluation where the source has two) and folds whose dropped operand is a
plain read, whose fault no program can rely on.

**Repair.** The classifier separates two kinds: `mhs_exceptions`, the
exceptions the program asked for - an enabled range or overflow check, through
the predicates the code generator itself uses, a checked cast, heaptrc pointer
checking, an integer division, a floating-point operation - and
`mhs_memory_reads`, a read through a pointer, an element or a class field. A
fold asks by what it does: one evaluation for two, or two for one - effects
only; none for one - `mhs_exceptions`; one where the source has none - both.
Kept as they were, with the reason at the site: the inline `UnicodeString`
equality (it reads each operand up to three times), `Dispose` and the tuple
temps (a call between the repeats can change the read), the copy of a dividend
`x mod C` and the temp of a `for` lower bound (the shorter code for an operand
read through memory), and the silence of a pruned short-circuit operand.
`0*x`, `0/x` and `x*0` of a real are fast math rules ("Real identities with
zero"); with fast math they drop `x` as the integer `x*0` does. An integer
division by zero and a floating-point exception still count as asked for.

**Validation.** [fold-guards](../qualification/optimizer-core/fold-guards/README.md)
runs at -O2 and -O3: values, no fault where a short-circuit guards a read
through nil, `ERangeError` of checked operands whose evaluation is merged or
dropped, `0*x` of a NaN element; in the -O3 object it requires the folds on
reads through memory, and the compiler before the repair fails each of the
seven, on Win64 and on Linux. The tests of the three audit defects and of the
repairs of the same commit - `tobservablesimplify1`, `trangefoldobservable1`,
`trotatefold1`, `tobservableintrinsics1`, `tshortboolprune1`,
`tinlinecheckedruntime1` - pass unchanged at -O2 and -O3 on both.

## SetLength of a dynamic array names its RTL routine by the element type

**Symptom.** After dynamic-array copy construction became transactional
(`c7c1ebced`) every `SetLength` of a dynamic array paid for it: a fresh array of
16 strings 95.3 -> 105.5 cycles, of 64 `Double` 71.0 -> 73.2 (Pulse `hot-rtl`,
Ryzen 5800X, families of four RTL placements, the transactional change reverted
for the first figure). Only an element type with a custom `Initialize` or
`Assign` operator needs the transaction, and only records, objects and static
arrays can have one.

**Cause.** One routine served every element type. With the transactional steps
in it - two guarded constructions, the bookkeeping of a fresh carrier, flags
for the operators - its common path keeps its locals in memory and executes
more. A first attempt that looked the operators up at the top of the straight
code and only then chose was slower still for strings (112.4): the lookup
calls and flags alone spoil the straight code.

**Repair.** The RTL has two routines. `fpc_dynarray_setlength_record` is the
transactional routine, unchanged. `fpc_dynarray_setlength` is the straight
routine from before the change; one test of the element's type kind at its top
sends records, objects and static arrays to the transactional routine, for the
callers that only have RTTI (`DynArraySetLength`, the inner dimensions of
`SetLength(a, n, m)`). The compiler knows the element type, so
`dynarray_setlength_procname` (ninl.pas; used by `SetLength` and by the two
array-constructor conversions in ncnv.pas) calls the transactional routine
directly for a managed record, object or static array and the straight one
otherwise: a record array pays nothing for the choice, every other array gets
the straight code back. The choice is about speed only - the transactional
routine is correct for every element type and the straight one hands over by
RTTI what it must not serve.

**What it does not settle.** The operators are not the only user code inside
`SetLength`: `_AddRef` when a shared array of interfaces is copied, `_Release`
when an array shrinks and the copy of a custom Variant can raise as well. The
straight routine has no rollback. If shared-array copy raises, the caller
still points at its old carrier while the new carrier and references taken so
far are stranded. If `_Release` raises during shrink, some old elements may
already be finalized; the array is not necessarily unchanged. The
transactional routine does not roll these cases back either (its guarded
steps are the custom operators). Delphi 12.2 also has no `try` around
`CopyArray`, although its `FinalizeArray` continues finalizing other elements
after a failed interface release. So the split gives nothing up, but exception
safety of interface and Variant elements is an open question, not a closed
one. `dynarray_setlength_paths_semantic.dpr` pins what does hold: after an
`_AddRef` that raises in the middle of shared copy both arrays are as they were.

Pulse after the repair: 16 strings 105.5 -> 95.4 (family), 64 `Double`
73.2 -> 70.8; `dynarray-copy-64`, `dynarray-assign-share`,
`ustr-setlength-64` unchanged.

**Validation.** [tdynarraysetlengthroute1.pp](../tests/test/cg/tdynarraysetlengthroute1.pp)
in the focused gate: the ASM verifier requires the transactional call exactly in
the routines with a managed record, a static array of strings and the array
constructor of managed records, and the straight call for `Double`, strings,
plain records and the outer dimension of a nested array (a compiler without
the repair fails it; the program still passes through the RTTI hand-over).
[dynarray_setlength_paths_semantic.dpr](../RTL-test/semantic/dynarray_setlength_paths_semantic.dpr)
takes every element kind through fresh, growing, shrinking and shared arrays
and checks contents, reference counts and operator calls; it passes on the RTL
before the repair as well, so it states the language rules and not this
implementation. `rtl_api_dynarray_managed_contracts` (the transactional
contract itself) is unchanged and green.

## `inline; forward;`

Delphi accepts `function F: Boolean; inline; forward;`: a forward declaration
that carries `inline`, its body later in the same unit. The parser's directive
table excluded `inline` from `forward` (`pdecsub.pas`, `proc_direcdata`), so
Arbitrage's MarketsU had to drop `inline` from such declarations. The other
order, `forward; inline;`, and an interface declaration with `inline` (an
implicit forward) were already accepted, so the exclusion was the only
inconsistent spelling. The entry now excludes `external` alone. Nothing else
changes: a call compiled before the body remains an ordinary call (the note
"marked as inline is not inlined" still names it), a call compiled after the
body is expanded as for any inline routine.

[`inline_forward.pas`](../qualification/suite/tests/smoke/inline_forward.pas)
runs both call orders at O-/O2/O3; the service regression gate also checks the
O3 assembly of the caller placed after the bodies for the absence of a `call`.

## `$MODE Delphi` repeated inside a unit

The product profile compiles every unit in Delphi mode with the Unicode
`String` ABI: the build drivers pass `-Mdelphi -Municodestrings` and the further
Delphi mode switches (`-Minlinevars`, ...). A unit that repeats `{$MODE Delphi}`
or `{$MODE DelphiUnicode}` — Indy's `IdCompilerDefines.inc`, mORMot's
`mormot.defines.inc` — reset the switch set to the bare `delphimodeswitches`:
`String` stayed Unicode (kept by an earlier repair in `SetCompileMode`), but
every driver switch outside that set was silently dropped for the unit, inline
variables among them. Under `MOONCOMPILER_UNICODE_DEFAULT`/`UNICODERTL` the two
directives are now a no-op while the current mode already is Delphi with
Unicode strings (`scanner.pas`, `SetCompileMode`): there is one Delphi dialect
in this profile, and a unit with the directive compiles exactly as without it.
The one thing `{$MODE DelphiUnicode}` adds on top of that dialect is the
system code page for the source text (`m_systemcodepage`: Delphi 2009+ reads
a file without a BOM in the ANSI code page), and that part still applies -
`delphi_char_cast_semantic.dpr` folds `WideChar(AnsiChar(#233))` through the
system code page under the directive, on a Windows-1251 machine to U+0439.
From another start mode — the compiler's own bootstrap, host tools, a program
compiled without `-Mdelphi` — the directive still switches the mode.

[`mode_delphi_noop.pas`](../qualification/suite/tests/smoke/mode_delphi_noop.pas)
builds a unit with the directive under the driver's switches (Unicode `String`,
`PChar` = `PWideChar`, an inline variable, `FPC_UNICODESTRINGS` defined) and, as
the negative control, without them: the same unit then switches mode and its
inline variable is rejected. Known issue `dvl-0023` is narrowed accordingly.

## `bufstream.TBufferedFileStream` and the seek-back write pattern

The fcl-base page cache (`TBufferedFileStream` in `bufstream.pp`) looked a
position up in its pages by `PageRealSize`, the number of bytes a page held,
although pages are aligned slots of the page size. A write that landed inside
a slot but behind its data - write a frame, seek back to patch its header,
seek to the frame end, write the next frame - found no page and created a
second one for the same slot; on flush the two overwrote each other, and
the uninitialised bytes between a page's data and a later write went to
the file as they were. Of 2001 frames written that way 996 came back with
foreign content (`doc-int` repro; Arbitrage's persistence saw 12025 CRC
mismatches).

Pages are now found by their slot; the bytes between a page's data and a
write, or a read, inside the slot are the file's zeros up to the logical
size (and nothing past it); a read that reaches the end of a page's data
continues with the rest of the request instead of stopping at a partially
filled page. `Classes.TBufferedFileStream` (Delphi `System.Classes` surface)
is a separate, window-based implementation added by the same series.

[`buffered_file_stream_semantic.dpr`](../RTL-test/semantic/buffered_file_stream_semantic.dpr)
drives both classes and a `TFileStream` oracle with identical calls - the
frame pattern, random seeks and read sizes, writes and reads at one point,
blocks larger than the window, holes, `SetSize` down over pending writes and
up, `FlushBuffer` with a raw read on the handle, reopening - and requires
identical files and identical `Position`/`Size` after every call.

## Exact regression and oracle reference index

The following source references remain part of the permanent evidence:

- [tdelphidictionaryisempty1.pp](../packages/rtl-generics/tests/tdelphidictionaryisempty1.pp), [tdelphitarraycopy1.pp](../packages/rtl-generics/tests/tdelphitarraycopy1.pp), [moonbot_for_var_explicit_pointer.pas](../qualification/suite/fixtures/minimized/moonbot_for_var_explicit_pointer.pas), [moonbot_nil_var_overload.pas](../qualification/suite/fixtures/minimized/moonbot_nil_var_overload.pas).
- [mormot_docvariant_unicode_probe.pas](../qualification/suite/fixtures/minimized/mormot_docvariant_unicode_probe.pas), [mormot_ikeyvalue_rtti_link.pas](../qualification/suite/fixtures/minimized/mormot_ikeyvalue_rtti_link.pas), [mormot_rawbytestring_bom_const.pas](../qualification/suite/fixtures/minimized/mormot_rawbytestring_bom_const.pas), [mormot_record_fields_rtti_probe.pas](../qualification/suite/fixtures/minimized/mormot_record_fields_rtti_probe.pas), [delphi_mormot_record_fields_oracle.json](../qualification/suite/research/delphi_mormot_record_fields_oracle.json).
- [o3-indysecopenssl-provider README](../qualification/suite/tests/compiler-crash/o3-indysecopenssl-provider/README.md), [rtl_api_array_copy.dpr](../qualification/suite/tests/rtl-api/rtl_api_array_copy.dpr), [rtti_generic_dependency_types.pas](../qualification/suite/tests/rtti/rtti_generic_dependency_types.pas), [rtti_gettypes.dpr](../qualification/suite/tests/rtti/rtti_gettypes.dpr), [array_const_index_out_of_range.pas](../qualification/suite/tests/smoke/array_const_index_out_of_range.pas), [win-stack-default run.ps1](../qualification/win-stack-default/run.ps1).
- [aggregate_exception_enumerator_semantic.dpr](../RTL-test/semantic/aggregate_exception_enumerator_semantic.dpr), [inline_fresh_managed_result_codegen.dpr](../RTL-test/semantic/inline_fresh_managed_result_codegen.dpr), [inline_managed_getter_borrow_semantic.dpr](../RTL-test/semantic/inline_managed_getter_borrow_semantic.dpr), [inline_managed_result_ownership_semantic.dpr](../RTL-test/semantic/inline_managed_result_ownership_semantic.dpr), [math_extreme_contracts_semantic.dpr](../RTL-test/semantic/math_extreme_contracts_semantic.dpr), [parallel_contracts_semantic.dpr](../RTL-test/semantic/parallel_contracts_semantic.dpr), [task_running_cancel_semantic.dpr](../RTL-test/semantic/task_running_cancel_semantic.dpr), [unicode_equality_codegen.dpr](../RTL-test/semantic/unicode_equality_codegen.dpr), [unicode_equality_semantic.dpr](../RTL-test/semantic/unicode_equality_semantic.dpr).
- [aggregate_init_unwind_semantic.dpr](../RTL-test/semantic/aggregate_init_unwind_semantic.dpr), [array_list_span_semantic.dpr](../RTL-test/semantic/array_list_span_semantic.dpr), [array_pointer_index_offset_semantic.dpr](../RTL-test/semantic/array_pointer_index_offset_semantic.dpr), [default_assign_safety_semantic.dpr](../RTL-test/semantic/default_assign_safety_semantic.dpr), [encoding_utf8_semantic.dpr](../RTL-test/semantic/encoding_utf8_semantic.dpr), [for_counter_physical_bounds_semantic.dpr](../RTL-test/semantic/for_counter_physical_bounds_semantic.dpr), [fpu_default_mask_semantic.dpr](../RTL-test/semantic/fpu_default_mask_semantic.dpr), [ioutils_api_semantic.dpr](../RTL-test/semantic/ioutils_api_semantic.dpr), [json_byte_reader_semantic.dpr](../RTL-test/semantic/json_byte_reader_semantic.dpr), [memory_stream_state_semantic.dpr](../RTL-test/semantic/memory_stream_state_semantic.dpr), [record_init_unwind_paths_semantic.dpr](../RTL-test/semantic/record_init_unwind_paths_semantic.dpr), [record_management_operators_semantic.dpr](../RTL-test/semantic/record_management_operators_semantic.dpr), [resourcestring_typed_const_semantic.dpr](../RTL-test/semantic/resourcestring_typed_const_semantic.dpr), [rtl_api_product_semantic.dpr](../RTL-test/semantic/rtl_api_product_semantic.dpr), [rtti_invoke_product_semantic.dpr](../RTL-test/semantic/rtti_invoke_product_semantic.dpr), [strength_result_counter_semantic.dpr](../RTL-test/semantic/strength_result_counter_semantic.dpr), [string_empty_compare_semantic.dpr](../RTL-test/semantic/string_empty_compare_semantic.dpr), [task_wait_semantic.dpr](../RTL-test/semantic/task_wait_semantic.dpr), [thread_pool_lifecycle_semantic.dpr](../RTL-test/semantic/thread_pool_lifecycle_semantic.dpr), [url_encoding_utf8_codepage_semantic.dpr](../RTL-test/semantic/url_encoding_utf8_codepage_semantic.dpr).
- [tarrayconstafterinline1.pp](../tests/test/cg/tarrayconstafterinline1.pp), [tarraypointerindexoffset1.pp](../tests/test/cg/tarraypointerindexoffset1.pp), [tdelphicustomvariantbyref1.pp](../tests/test/cg/tdelphicustomvariantbyref1.pp), [tdelphidefaultarray1.pp](../tests/test/cg/tdelphidefaultarray1.pp), [tdelphifilegetsize1.pp](../tests/test/cg/tdelphifilegetsize1.pp), [tdelphiforvarexplicit1.pp](../tests/test/cg/tdelphiforvarexplicit1.pp), [tdelphimemorystreamcapacity1.pp](../tests/test/cg/tdelphimemorystreamcapacity1.pp), [tdelphimemorystreamsetsize1.pp](../tests/test/cg/tdelphimemorystreamsetsize1.pp), [tdelphinilvaroverload1.pp](../tests/test/cg/tdelphinilvaroverload1.pp), [tdelphiolevariantint641.pp](../tests/test/cg/tdelphiolevariantint641.pp), [tdelphirawbyteconst1.pp](../tests/test/cg/tdelphirawbyteconst1.pp), [tdelphitextpos1.pp](../tests/test/cg/tdelphitextpos1.pp), [tdelphivariantcardinalbyref1.pp](../tests/test/cg/tdelphivariantcardinalbyref1.pp), [tdelphivarrankpure1.pp](../tests/test/cg/tdelphivarrankpure1.pp), [tforsteplatchasm1.pp](../tests/test/cg/tforsteplatchasm1.pp), [tinheritedabstractproperty1.pp](../tests/test/cg/tinheritedabstractproperty1.pp), [tinlineenumguard1.pp](../tests/test/cg/tinlineenumguard1.pp), [tmoonarrayconstindex1.pp](../tests/test/cg/tmoonarrayconstindex1.pp), [tmoonattributemarker1.pp](../tests/test/cg/tmoonattributemarker1.pp), [tmoonconstpropglobalcalls1.pp](../tests/test/cg/tmoonconstpropglobalcalls1.pp), [tmoondelphicallbacktypes1.pp](../tests/test/cg/tmoondelphicallbacktypes1.pp), [tmooninlinemanagedexprfinally1.pp](../tests/test/cg/tmooninlinemanagedexprfinally1.pp), [tmoonoddconstu641.pp](../tests/test/cg/tmoonoddconstu641.pp), [tstrengthresultcounter1.pp](../tests/test/cg/tstrengthresultcounter1.pp), [tstrengthresultcountertrace1.pp](../tests/test/cg/tstrengthresultcountertrace1.pp), [tconstsnoregvar1.pp](../tests/test/opt/tconstsnoregvar1.pp), [tforstep9.pp](../tests/test/tforstep9.pp), and [BACKLOG.md](BACKLOG.md).

## Ownership of VMT symbols in Win64 typed exception handlers

Win64 repeated typed exception handlers now retain correct ownership of their
class VMT symbols, preventing Internal error 2016070102 for a local exception
class used both inside a procedure and in the program body. Strong class aliases
are resolved to the actual VMT provider, including aliases of imported classes.
The change affects compiler symbol bookkeeping only; exception matching and
runtime code remain unchanged. PPU representation is unchanged.

[`seh_vmt_symbol_semantic.dpr`](../RTL-test/semantic/seh_vmt_symbol_semantic.dpr) covers repeated local handlers,
imported exception classes, strong aliases and alias chains, and generic
exception classes. The Win64 O-/O2/O3 matrix also passed with unit sources
physically hidden before the consumer build; PPU EXTERN entries retain foreign
VMT references and exclude the defining module's own VMT.

## Win64 Variant to UnicodeString

The standard Win64 variant manager preserves the existing `varUString` carrier.
Reading that exact type now shares its UnicodeString storage with normal
reference counting and copy on write, removing the intermediate BSTR allocation
and both string copies. Embedded NULs and arbitrary UTF-16 code units are retained.

`SetVariantManager` updates a cached capability by comparing the actual callback
values with the registered standard `VarToWStr` function. Custom readers remain
observable, including delegating readers. By-reference values, OleVariant and
other types continue through the existing conversion callback. Registration is
revoked before Variants restores the previous manager during finalization.
`TVariantManager` retains its layout; dependent units must be rebuilt against
the updated System interface in the normal way.

Linux retains its existing observable `varOleStr` representation and conversion
path. The new code is excluded by `FPC_WIDESTRING_EQUAL_UNICODESTRING` there.

The ordinary Win64 string path performs less allocation and copying. The general
API pays an exact-type/capability guard on fallback paths; the targeted four
placement matrix measured a by-reference fallback cost up to 8.4%. This is an
explicit trade-off in favor of normal application string values, not a claim of
universal speed improvement for every Variant use.

## Persistent constant temporaries in manual loops

The constant-to-variable pass now emits the matching temporary deletion for
both real constants and static addresses. These persistent values remain live
until the function exits, including functions with Pascal labels and goto.

Previously, a PIC loop could load a global address from the GOT into RDX,
reuse EDX for the last payload load, and return through its backedge with a
corrupted base address. The usual loop register synchronization deliberately
does not handle arbitrary Pascal labels; the missing temporary deletion also
omitted its final synchronization. Restoring that existing lifecycle keeps one
GOT load before the function and requires no hot guard. Disabling the whole
constant optimization for goto was tested and rejected: it restored two GOT
loads per loop iteration instead.

The [focused gate](../qualification/optimizer-core/consttemp-lifetime/README.md)
covers integer addresses, real constants, side entry, early exit and PPU-only
inline consumers in O-/O2/O3 on Win64 and Linux, including native Linux PIC.

## Float constants and the registers of a loop

**Symptom.** A procedure whose loop needs every xmm register kept its float
constants in registers anyway and a variable of the loop went to the stack. In
the shape of `TMarket.CalcHourDeltas` (`Max` and `Min` expanded in a loop of 15
values, the constants 1 and 100 needed only after it) the loop stored a value
to `[rsp]` on every turn: 118 -> 128 instructions on Win64 against the release
(-11.5 % on the efficiency cores of Raptor Lake, model function). The release
spilled the same way in a procedure without any call: a loop of fourteen
accumulators read 0.25 three times a turn from a stack slot the entry had
stored it to.

**Cause.** The constant-to-variable pass (`do_consttovar`) gives a float
constant a register temp from the entry by the number of its uses; it cannot
know the register demand of the procedure. The register allocator could, but
did not know that the temp holds a constant: it chose the value to spill by
the number of its interferences, so a variable of the loop and a constant
needed after it were alike to it, and a spilled constant took a stack slot
stored at the entry. Since the tail-call repair of 20.09 an expanded call no
longer counts as a call, which opened the lower threshold of the pass to
procedures with expanded `Max`/`Min`.

**Repair.** In the register allocator (see
[Optimizer](OPTIMIZER.md#float-constants-in-registers)). Code generation marks
the register of an immutable temp loaded from a real constant (the temps of
the constant pass and of common subexpressions); the allocator keeps the mark
when that load is the first instruction of the register and nothing else
writes it, and gives the register the constant's memory as its initial
location. Spilled, the register reads that memory: no slot, no store, no
load. When a colouring leaves values without a register, each takes a colour
which only constant loads hold among its neighbours, and those go to their
memory - only when their reads cost less than the loads and stores of the
value, for every such value of the round, and when their memory replaces
every use without a helper register; the colouring then stays complete. When
a round spills constant loads only, the allocator also colours the code
afresh, with the moves given up under the pressure given back, and from the
start without the constants, and keeps the cheapest complete colouring. A
register which Win64 saves and restores (xmm6-xmm15) and which only constant
loads hold in the final colouring is given up when their reads cost less than
the save and the restore. Where registers suffice nothing changes. A register
coalesced into a constant register loses the mark; spilled values never share
a constant's memory, and a write to a constant spilled into its memory stops
the compiler with an internal error.

A rule on the pressure alone was tried and rejected: where more values are
live than there are registers, the cheapest constants went to their memory
before the colouring. In `ODEIV1` (numlib) the excess of such a point was
already paid by variables spilled around the calls of the loop, and a constant
of a common subexpression went to memory for nothing - one more read in the
loop, no instruction less.

**Validation.** [const-register](../qualification/optimizer-core/const-register/README.md)
runs six forms at -O2 and -O3 against the same arithmetic on writable typed
constants and checks the -O3 code: no variable of the `CalcHourDeltas` loop in
the stack; no float value in the stack for the constants of three loops with
and without calls; the constant of a light loop and of a loop that reads it
four times a turn stays in a register. The compiler before the repair fails the
first four, and on Win64 `Deltas`, where two saved registers hold only the
constants 1 and 100. RTL, packages, MoonORMot and the Pulse programs compiled
before and after: on Linux 7 functions of the RTL and the packages change
(1463 objects), none of MoonORMot (115 units) or of the Pulse programs (25);
on Win64 24 functions of the RTL and the packages (1593 objects) and one of
the Pulse programs (`RecalcDeltasByCandles`). Each has fewer instructions;
none has more memory accesses in its loops, more xmm stores and loads of the
stack or more callee-saved saves; 18 of the Win64 functions save fewer xmm
registers.

## Strong alias ownership during PPU reload

Enum, record and object strong aliases share their original type's symbol
table. Re-resolving the same target now preserves its reference count; changing
the target releases the previous table. Loading an object alias also avoids
allocating a placeholder table that would immediately be replaced.

A shared table can retain definitions after their original module is reset
for recompilation. Reset now detaches surviving definitions from the old
registration list, as module destruction already did. Otherwise their later
release could write an old DefId into the new empty list and crash the compiler.

These are compiler ownership repairs; compiled program code is unchanged.
Releasing previously leaked objects and scanning surviving registrations during
reset are required cleanup work, not a promise of faster compilation. The
[focused gates](../qualification/compiler-alias-lifetime/README.md) cover
PPU-only aliases, real dependency reload, zero remaining table references and
identical self-hosted binaries after clean and incremental builds.

## Managed-array copy construction

Shared `SetLength` and array `Copy` preserve the original array when acquiring
an element throws. The unpublished carrier and successfully constructed prefix
are released. Nested records and static arrays track their inner prefix, so
Finalize is never called merely because an untouched record was zero-filled.

FPC AddRef-only record hooks remain observable and run after managed fields.
Explicit record Copy retains its existing contract; copy construction does not
invoke Initialize. Interface copying acquires the reference before publishing
the pointer into its new slot. Ordinary fresh and unique Double/string SetLength
keeps the existing path; shared complex records and Windows WideString may pay
for transactional construction. The Windows BSTR path is not used on platforms
where WideString is UnicodeString.

Cleanup callbacks must allow cleanup to finish. A callback must undo its own
opaque acquisitions if it raises before returning ownership. Unique shrink with
a throwing interface Release provides a basic guarantee when Release consumes
its reference first: processed slots are nil, the old length remains, and retry
is safe. This does not promise rollback of arbitrary external callback effects,
or repair whole-array Clear interrupted by a throwing finalizer.

## Private definitions used by inlined PPU code

Private symbols and definitions referenced through inline bodies now contribute
to the unit's full checksum. Previously an unchanged checksum could validate old
SymId/DefId references after their targets had changed; rebuilding System with a
changed inline implementation reproduced an access violation in Heaptrc.

Implementation references are prepared before publishing the final checksum,
including cyclic implementation dependencies. The checksum uses the existing
PPU serializer; the interface checksum and PPU format remain unchanged. The
cost is checksum work and necessary dependent-unit recompilation, with no new
instructions in the generated program.

The regression gate in `qualification/compiler-private-ppu` checks a private
DefId change and its reversal. The repair also passed the original Windows RTL
toggle, compiler selfhost and native Linux reproducer.

## Win64: trailing call in noreturn procedures

An exception raised below a `noreturn` procedure whose last instruction is a
call did not reach the `except` of its caller on Win64: the process ended with
the unhandled exception `0xE0465043`. Every `InternalError` of the compiler
ended so (`verbose.InternalError` is `noreturn` and ends by calling the routine
that raises), and so did user code, e.g. a `noreturn` wrapper of a raising
procedure.

A `noreturn` procedure never removes its frame. `g_proc_exit` still emitted a
`ret` for the peephole optimizer, and `CallRet2Call` removed it behind the last
call from -O1 on. The Win64 unwinder looks up the function of a return address
in `.pdata` only below the function's end; the return address of the final
call was the end, and the frame was taken for a leaf. The `ret` itself is no
better (-O- builds, where the peephole does not run, had it): the unwinder
takes a `ret` at the return address for the end of an epilogue and emulates
just that `ret`, reading the caller's address from inside the frame. The same
executable with that one byte changed from `ret` to `int3`, `.pdata` and
`.xdata` untouched, delivered the exception.

`g_proc_exit` (`compiler/x86_64/cgcpu.pas`) now emits `int3` instead of `ret`
for a `noreturn` procedure with unwind information: one byte like the `ret`,
inside the function and no epilogue, and a trap should the impossible return
ever run. MSVC and LLVM (`X86AvoidTrailingCall`) put `int3` there too.
`CallRet2Call` finds no `ret` to remove; SysV targets and procedures without
unwind information keep their `ret`. Against the previous compiler an
optimized build grows by one byte per such procedure that ends in a call: the
main block of every program (it ends in `FPC_DO_EXIT`), `Halt`, `RunError`,
`InternalError`.

[`win64_trailing_call_semantic.dpr`](../RTL-test/semantic/win64_trailing_call_semantic.dpr)
raises through a `noinline` wrapper in O-/O2/O3, and RTL-test runs
[`pdata_tail_gate.py`](../qualification/build-driver/pdata_tail_gate.py) on its
executable: no call ends a `.pdata` function, and no `ret` follows a call in a
function whose unwind codes move `rsp`. The previous compiler fails the gate in
all three modes and the run at O2 and O3.

## Idle workers of the thread pool

`TThreadPool` of System.Threading (imported from FPC vcl-compat) signalled
queued work through `FQueueEvent`, created by the parameterless
`TEvent.Create`. In FPC that is a manual-reset event, and nothing reset it.
After the first signal every idle wait returned at once; a wait that returned
without work still counted as idle time (`AdjustWaitTime` doubled 40 s to
320 s in four rounds), and the worker left microseconds after its last task.
The pool kept no idle worker, contrary to its own `IdleTimeout` and to Delphi,
whose worker waits 40 s: every burst of tasks created threads again (20
sequential tasks created 72-76 threads), and under CPU load a task started
only with the first time slice of its new thread.

Previously, `WorkQueued` left a task to the idle workers instead of growing the pool
when `FIdleThreads>=FRequestCount`. A worker that had decided to leave still
counted as idle until it unregistered and did not look at the queue again: a
task queued in that window waited for `GrowIfStarved` of the pool monitor,
whose first check comes about a second after the first task of the process.
`task_wait_semantic` (a 40 ms FastTask must win `WaitForAny(...,1000)`)
failed once at O3 on a host loaded by parallel builds, without naming the
index; holding the leaving worker for 20 ms in that window makes the unchanged
test return -1 after 1002-1015 ms in 9 of 200 runs.

The pool retains wake notifications in a semaphore. A worker publishes its
idle state before checking the queues: work published earlier is found by
that check; work published later leaves a permit. `WorkQueued` wakes an idle
worker independently of whether demand also calls for growth, including
concurrent producers at the maximum worker count. Only a timed-out wait
counts as idle time. A departing worker leaves the idle set before its last
queue check; after releasing its worker slot it reconsiders pending requests.
Its entry in the pool's lifetime list remains until this work is finished.
Shutdown gives every remaining worker a permit. Submissions from another
pool use the destination's global queue, not the sending worker's local queue.

The Windows semaphore and mutex constructors also used to allocate a base
event and overwrite its handle. They now initialize their own handle directly,
as `TEventObject` already does, storing `UseCOMWait` without changing wait or
error handling.

[`thread_pool_idle_worker_semantic.dpr`](../RTL-test/semantic/thread_pool_idle_worker_semantic.dpr)
runs 20 tasks on a pool whose workers wait idle and requires that no thread
is created for them; the previous pool fails it in Debug/O2/O3 every time.
`task_wait_semantic` now names the index and the time of a failed finite
`WaitForAny`.
[`thread_pool_delivery_semantic.dpr`](../RTL-test/semantic/thread_pool_delivery_semantic.dpr)
covers cross-pool submission and local work behind a busy worker, including
cancellation. [`sync_handle_lifetime_semantic.dpr`](../RTL-test/semantic/sync_handle_lifetime_semantic.dpr)
checks 100 pool lifetimes and all Windows semaphore/mutex constructor forms.
The [deterministic delivery gate](../qualification/thread-pool/README.md)
forces the queue/idle/exit interleavings without relying on the pool monitor.

## Limits of the thread pool

`TThreadPool.SetMinWorkerThreads` (imported from FPC vcl-compat) accepted a
minimum only below the maximum, and `SetMaxWorkerThreads` a maximum only above
the minimum. Delphi 12.2 accepts any minimum from zero and any maximum above
zero, each on its own. MoonBot asks the default pool for
`Max(ProcessorCount*2,36)` workers, never less than the default maximum
`ProcessorCount*2`: the call was refused on every machine, and nothing read
the `False`. On a 16-thread machine the pool kept its default limits 4 and 32
and ran 32 of 36 gated tasks at once.

The two setters now accept what Delphi accepts. The rest of the pool already
reads the limits as Delphi does (`GrowPool` is `ShouldGrowPool` and
`GrowWorkerPool`): when work arrives that the idle workers do not cover and
the pool has fewer workers than the minimum, it starts the missing ones at
once, whatever the maximum; beyond the minimum, demand grows the pool only
below the maximum. A minimum above the
maximum is kept as set, Delphi does not clamp it either, and means that many
workers at once: MoonBot's 36 where the maximum is 32.

The minimum does not keep idle workers for good, in Delphi or here. A Delphi
worker leaves after 40+81 s of idle waits and a 5 s retirement delay,
whatever the minimum. Here an idle worker leaves after 280 s while the pool has
more than minimum+1 workers, otherwise after 600 s without queued work:
MoonBot's 36 workers now wait 600 s before they leave, where all but 5 of its
32 used to leave after 280 s.

[`thread_pool_limits_semantic.dpr`](../RTL-test/semantic/thread_pool_limits_semantic.dpr)
checks the accepted and the refused values and that neither limit changes the
other, then sets MoonBot's minimum with a maximum of 1 and requires that many
gated tasks to run at once on exactly that many workers; the previous setters
fail it in Debug/O2/O3. The `MinWorkerThreads` and `MaxWorkerThreads`
properties were read-only, so Delphi code that assigns them did not compile;
they now write through the same checks, as in Delphi.

## CPU usage of TThread

`TThread.GetSystemTimes` and `TThread.GetCPUUsage` (imported from FPC) did not
read the machine. Win64 had only the default `GetSystemTimes`, which returns
`False`, so `GetCPUUsage` was always 0. The Linux reader took `/proc/stat`
into a buffer of `Char`, which is a `WideChar` in the Unicode RTL, so it never
found the counters and returned `False` too; read as bytes, it would still
have stopped before the idle field. And the percentage was
`100*Trunc(1-Idle/Load)`, which turns every partial load into 0.

As in Delphi 12.2, `GetSystemTimes` now returns the counters of all
processors with the kernel time including the idle time (Windows
`GetSystemTimes`; Linux `user nice system idle`), and `GetCPUUsage` the busy
share of the interval, `(Load-Idle)*100 div Load`. The thread pool monitor
reads it (next section).
[`thread_cpu_usage_semantic.dpr`](../RTL-test/semantic/thread_cpu_usage_semantic.dpr)
compares `GetSystemTimes` with the counters of the operating system read
directly and checks `GetCPUUsage` on an interval of known share; the previous
RTL fails it on both targets (no counters).

## A thread pool whose workers are blocked

`TThreadPool.UnlimitedWorkerThreadsWhenBlocked`, True by default in Delphi
12.2, was declared but never set or read: when every worker the limits allow
was busy, queued work waited for one of them. MoonBot's pool always stands at
that limit, since its minimum of 36 is above the default maximum, so a task
queued behind 36 blocked tasks waited for one of them to finish; under Delphi
it starts at once.

The behaviour, observed with a Delphi 12.2 program and repeated here: a
producer that finds no idle worker and may not add one wakes the pool monitor
at once. While the processors are less than 80% busy, the monitor adds
threads when work is queued and no worker is idle, the queue is not shorter
than at its previous addition, and no thread was created in the same tick:
one thread below the maximum and, with the property set, up to
`MaxWorkerThreads div 2 + 1` above it. With MoonBot's limits, 80 blocked tasks
start 36 at once and 17 after the monitor's round; the other 27 wait for the
blocked ones, since the queue stays shorter than at that addition, and so does
a later task behind the then 53 blocked workers. How much of a burst one
addition covers depends on where the monitor's round falls: Linux counts that
tick in milliseconds rather than 15.6 ms steps, so a round inside the burst
adds threads for the part queued so far and the rest of the burst waits (with
MoonBot's limits under load, 7 of 12 started). Below the maximum the monitor
adds a thread only while no worker is idle; the demand path of the producer
already grows the pool there.

With the monitor measuring the processors, the imported suspension of a
worker at high load (6 s up to three times, then termination) would have
started to run; it never ran before, nor did the retirement wait
`TryToRetire`, which nothing called. Workers keep leaving on their idle
timeout, and both paths are removed with the rest of the unreachable pool
code (`PushLocalWorkToGlobal`, `TSafeSharedInteger`/`TSafeSharedUInt64`, two
monitor wrappers). `TThreadPoolStats` reports the processor usage the monitor
measured; the retired and suspended counts stay 0. A steal attempt without a
timeout, the scan of the other workers' queues each time a worker runs out of
work, no longer resets and waits on each queue's event: two kernel calls per
queue, about 70 per scan with MoonBot's 36 workers, for an attempt that does not
block anyway (Delphi's timeout only bounds taking the queue's lock). A steal
with a timeout still waits for a push.

[`thread_pool_blocked_growth_semantic.dpr`](../RTL-test/semantic/thread_pool_blocked_growth_semantic.dpr)
checks the default, a task behind two blocked workers at `Max=2` with the
property on and off, the child of the only worker while that worker blocks,
and how much one addition gives: tasks queued with the property off, then
switched on, get exactly `Min(queued, MaxWorkerThreads div 2 + 1)` threads
and no more while the queue stays shorter (eight behind `Max=2`, twelve
behind MoonBot's minimum). Its waits do not count time during which the pool
saw busy processors. The previous pool fails it in Debug/O2/O3. Tests that use `Max=1` to mean exactly one worker (local work
behind a busy worker, queued cancellation, the `TParallel.For` break stride,
the minimum on exactly that many workers) turn the property off: with it on,
the pool grows past the maximum when its workers block, in Delphi as here.

## A zero extension proved across the notes of the register allocator

**Symptom.** Pulse `loops/aliased-update` was slower than the release on all
six measured processors (+4 to +80 %): in the loop
`IntC[Index] := IntA[Index]; AliasUpdate(IntC[Index], IntC[Index])` the
element just stored from a register was read back from memory, and the index
was restored from its copy - three instructions of the inner loop the release
does not have. `loops/nonaliased-update` kept the same extension and the index
copy.

**Cause.** The repair that keeps a 32-bit zero extension (`movl %edx,%edx`)
while the upper half can still be read drops it only when
`CanDrop32BitZeroExtend` (`compiler/x86/aoptx86.pas`) proves the upper half
clear: the last write of the register is a 32-bit one, or a later 32-bit write
replaces it before anything reads the upper half. The proof walked the
instructions around the extension and stopped at anything that was not an
instruction, a comment or a line note - also at the notes of the register
allocator the peephole optimizer sees between instructions. Here
`andl $8191,%edx` had cleared the upper half, and "esi released" stood between
it and the extension: the extension stayed, and the rule that gives a load the
register just stored (`MovMov2MovMov1`) pairs only neighbouring instructions,
so the read stayed too.

**Repair.** The proof steps over the items without code and without an entry
- allocation notes, temp allocation notes, variable locations - as the
optimizer's own instruction walk does (`SkipInstr`), and its window counts
instructions only. Labels, jumps, calls and every other item still end it.
The inner loop of the Pulse case is 16 instructions instead of 19 on Win64
and 14 instead of 17 on Linux, where the release's loop is the same 14.

**Validation.** [qualification/optimizer-core/value-in-register](../qualification/optimizer-core/value-in-register/README.md)
(`StoreReload`, `StoreOther`: no 32-bit register extended into itself, the
counts of the -O3 object; red on the compiler before the repair on Win64 and
Linux). The value oracle of
[qualification/optimizer-core/register-width](../qualification/optimizer-core/register-width/README.md)
(720 and 480 functions, flags and consumers of the upper half) stays green.
Win64 images of the 25 Pulse programs, two product analogues and
`mormot2tests`: 9 functions change, all shorter or equal, none with more
memory accesses.

## A const actual the inlined body cannot change

**Symptom.** Pulse `product-forms/market-by-int-name` was slower than the
release on five of six processors (+2.8 to +3.7 %). In
`MarketName := StringReplace(MarketName, '_', '', [])` the RTL at -O3 inlines
both `StringReplace` wrappers and calls the worker directly - two calls fewer
than the release - but each wrapper stored its three `const` strings into temps
of the frame and the second copied the temps of the first: 13 memory accesses
before the call where the release passed three registers. In the tests of
mORMot the inlined assertion `Check(Cond, '')` stored the constant empty
message into the frame at every call, read it back and tested it, and kept the
branch that logs.

**Cause.** A `const` parameter passed by value is a snapshot taken before the
call, and the inliner substitutes the actual directly only when the body
cannot change it. The rule added for captured locals (`paraneedsinlinetemp`,
`compiler/ncal.pas`) materializes the snapshot whenever the body writes
anything outside its own frame, without asking whether that write can reach
the actual. A constant cannot change. A local of the caller whose address
nobody holds and which no nested routine sees can be written by the inlined
body only through the same call: an assignable actual (`var`, `out`,
`constref`, untyped) that names it or its `absolute` twin, the `Self` of a
record method, the result assigned to it (already refused by
`funcret_can_be_reused`).

**Repair.** `inline_actual_is_callers_own` asks the effect model
(`compiler/opteffect.pas`, `tree_effect`) whether the actual reads only exact
locals of the current frame and temps whose address nobody holds, without a
trap, a call or a write, and whether an assignable actual of the call names
one of them - its symbols, `absolute` resolved, and its temps. Such an actual
needs no snapshot. It goes in directly where the copy costs something: a
constant the body reads and can fold (`inline_constant_goes_in`), and a value
whose temp could not be a register - a copy through the frame. A register
copy of a variable is left: it costs nothing, and the register allocator uses
it to split the variable's lifetime (without it `TOpenAddressing.SetItem` took
one more move: the key lived from `rdx` at the entry to `r8` at the call
through registers taken by other values).

Two kinds of constants keep their register copy as well. A real constant has
no immediate form: it is a read of memory wherever it stands - once in front
of the body in the register copy, at every place the body reads the formal
when substituted - and the body folds it only in an expression of constants.
Substituted, the read of `-1` in fcl-report's `TFPReportExportPDF.DoExecute`
moved into the inlined `SetYScalation` between the address of the matrix and
the store, and the address no longer folded into the store (one instruction
more); `TFPReportLayouter.ShowColumnFooterBand` read its `Single` twice. And a
constant for a formal the body never reads: the direct form only drops the
dead move of the register copy, and at -O3 the actual of such a formal is
still evaluated (dead values stay below -O4). The move of the constant is what
the peephole put over the dead read of another actual in the same register
(`Mov2Nop 5`): in every `VariantTo*` of varutils the inlined
`VariantTypeMismatch(vType, varByte)` kept the move of `varByte` and dropped
the read of `vType`; without the move the read stayed (15 functions with one
more memory access at every `raise`).

On Win64 the call of the Pulse case takes 8 instructions with three memory
accesses - the string read from the frame and the two arguments the ABI passes
on the stack - instead of 17 with 13. In the Win64 images of the 25
Pulse programs with two product analogues and of `mormot2tests`, 314 and 925
functions change on `637933feb`: memory accesses 19853 to 18899 and 174060 to
126547 over them, instructions 50384 to 48954 and 385266 to 314117 (the
constant message of `Check` folds at every assertion of the tests). No
function has more memory accesses. Five functions of mORMot have one or two
more instructions with as many or fewer memory accesses, and dbf's
`TDbfFile.ConstructFieldDefs` of fcl-db four more and two more memory
accesses (against main `e3017da29`, full toolchains): `TSynDictionary.LoadFromBinary`
and `JsonObjectsByPath`'s `AddFromStart` (also in the copies of mORMot in two
Pulse programs), `TCryptAsymRsa.Verify`, `TRsa.LoadFromPrivateKeyPem`,
`TOrmHistory.HistorySave`. In each of the six the code the register allocator
gets is shorter - compiled with `-a -sr -s`, register allocation skipped:
`ConstructFieldDefs` 621 to 619 instructions and 188 to 186 memory operands,
`LoadFromPrivateKeyPem` 53 to 50 and 13 to 8, the others one or two
instructions fewer - and the allocator colours the smaller graph with another
spill or another move.

**Validation.** [RTL-test/semantic/inline_const_alias_semantic.dpr](../RTL-test/semantic/inline_const_alias_semantic.dpr)
holds the forms where the body can change the actual and the snapshot stays -
the same local as a `var` and a `const` actual, its `absolute` twin, a field
of the record `Self`, the result assigned to the actual, a local behind a
pointer, a global the body writes, a temp of an outer inline - for integers
and strings, green at -O-, -O2, -O3 and -O4. A compiler that does not ask the
assignable actuals fails eight of them at -O- and the temp of the outer inline
at -O2 and -O3. Each string form keeps a second reference to the string: a
`const` string is a pointer without a reference of its own, and with the count
at one the concatenation of the real call grows the block in place (Linux: the
parameter reads the new text) or moves it (Win64: it reads a freed block) -
without the second reference the real call has no value to compare with.
Delphi 12.2 gives the values of the text for all but two: a local behind a
pointer and a global the body writes, which it substitutes and reads after the
write. [qualification/optimizer-core/value-in-register](../qualification/optimizer-core/value-in-register/README.md)
counts `CleanName` and `CheckAll` in the -O3 object (red before the repair on
Win64 and Linux), `ToByte` and `FlipSheet` (the constant rules; red without
them on Win64, `FlipSheet` on Linux as well), and `ContainsMiss`: with the
constant argument substituted it stands between the two reads of the global
object, and only the forwarding of
[a read of memory whose value a register holds](OPTIMIZER.md#a-read-of-memory-whose-value-a-register-holds)
keeps it at one read. Likewise the loop of fcl-xml's `ParseMarkupDecl` on
Linux, whose inlined `Matches` calls no longer bring temps into it, keeps
`Self` in a register only with the rule of
[the fields of a local record in a loop](OPTIMIZER.md#the-fields-of-a-local-record-in-a-loop)
for the fields a loop with calls only writes.

## A load moved up past a use of its register

**Symptom.** At -O3 and -O4 `X := PInt64(P)^; Inc(P, X); Inc(X, 1);
X := PInt64(P)^` gave the element behind the step plus one: 701 for 700 in
`DeadStep` of the semantic test, on main `e3017da29` (Win64 and Linux) and on
the release `ccaa5fbaf` (Linux). The generator of the memory-order gate found
it on the branch of [a read of memory whose value a register holds](OPTIMIZER.md#a-read-of-memory-whose-value-a-register-holds)
(`fz_step_13`, `F188`, -O3 and -O4 on Linux): the forwarding turned
`add (%rdi),%rdi` into `add %rdx,%rdi` and gave the rule below its form.

**Cause.** `OptPass2ADD` ("AddMov2Mov", `compiler/x86/aoptx86.pas`) turns
`add %reg2,%reg1` and a later `mov (%reg1),%reg3` into one load with both
registers in its address. At -O3 the load need not follow the addition; where
`%reg2` changes in between, the rule moves the load up to the addition. It
asked whether anything in between writes memory (`MemoryWrittenBetween`), not
whether anything in between reads or writes the register the load writes:

    add  %rdx,%rdi           mov  (%rdi,%rdx),%rdx
    add  $1,%rdx       ->    add  $1,%rdx
    mov  (%rdi),%rdx

The increment of the value about to be replaced now came after the load and
was added to the value loaded.

**Repair.** The load moves up only past instructions that neither read nor
write its register (`RegUsedBetween`); otherwise the pair stays as it is. Every
form the condition refuses was wrong: the load would have been read before its
time or overwritten after it.

**Validation.** [RTL-test/semantic/add_load_semantic.dpr](../RTL-test/semantic/add_load_semantic.dpr):
a dead step, a read of the old value, the length an argument, a 32-bit length;
`DeadStep` red on main at -O3 and -O4 on both targets, all four green at every
level with the repair; Delphi 12.2 and -O1 give the values. The generator
round is green again.

## Win64 external linker: collect unwind sections into the image

With `-Xe`, even a program using only `SysUtils` could compile successfully
and then be rejected by Windows with error 193. The external linker script
did not collect `.pdata.n_*` and `.xdata.n_*` sections emitted for individual
procedures. GNU ld left them as hundreds of separate image sections instead
of a single exception table and read-only unwind data.

The external script now collects the same section families as the internal
linker. This changes image metadata and placement, with no change to the
compiled functions. `tests/test/cg/texternalwinunwind.pp` checks both loading
and an RTL exception crossing recursive frames with managed locals and
`finally` cleanup. The old compiler fails before entry; the repaired compiler
passes at `-O-`, `-O2` and `-O3`. The internal linker is the negative control;
the object files compiled before and after the repair are identical.

## Search paths: replace the same directory consistently

A project `-FuMixed` followed by a command-line `-FuMixed/**` could retain
the old explicit entry and load a stale PPU that the recursive path excludes.
Directory keys and list removal disagreed on case, and relative and absolute
spellings were treated as distinct directories. With `-n`, temporarily reading
project options could also initialize the cached cwd to the project directory,
making a subsequent absolute command-line path relative to the wrong place.

Search-path keys now use absolute paths and the host's case rule; replacement
uses that same key. The project reader initializes the original cwd before
switching and restores it before merging its absolute paths with existing
relative paths. Explicit PPU paths and case-sensitive directory names retain
their semantics. This changes unit selection, not generated instructions.

`qualification/compiler-search-path/run_gate.py` reproduces the stale-unit
selection in Debug and Release, with different working directories and path
spellings. The explicit PPU control remains valid. The product configuration
gate also covers path ordering, recursive trees, directory links and distinct
case-sensitive names on both targets.

## Unit pins: an identical explicit pin still has command-line priority

Given `@first.cfg --pinned-unit=Chosen=first/Chosen.pas @second.cfg`, repeating
the first config's source on the command line left the pin marked as coming
from configuration. The second config then rejected the build. Choosing a
different source on the command line correctly retained command-line priority.

The options reader now records an explicit pin even when its path is unchanged.
This repairs the origin of the selection; it changes no generated instructions.
`qualification/pinned-unit/precedence_gate.py` reproduces the failure at
`-O-`, `-O2`, and `-O3` and retains the rejection of conflicting config-only
pins, as well as valid identical config pins and later command-line replacement.

## RTL profile stands: preserve the source template names

The move to `moon-base.cfg` also renamed references to the input templates in
both stand builders, although those files retained their `fpc.cfg.*.template`
names. After building the compiler and units, configuration rendering failed
with a missing-template error. The builders now use the existing templates;
output names and optimization profiles are unchanged.

`qualification/build-driver/stand_config_gate.py --toolchain <installed-root>`
renders the templates selected by both scripts with the real `fpcmkcfg`, then
compiles and runs an IDE and a Unicode product consumer at `-O-`, `-O2`, and
`-O3`. Both profiles reject the opposite `Char` size as a negative control.

## Inline locals in the program body and unit initialization/finalization

An anonymous function escaping a top-level `begin` block could lose an inline
string or interface when that block ended. Those declarations were static
symbols, so the capture analysis never moved them into its existing owner.
An inline managed declaration in FPC-mode unit initialization could instead
leak because neither routine cleanup nor module finalization visited its block.

Top-level inline declarations now use local symbols and the same capturer
fields as routine locals. The existing module-owned capturer keeps escaped
values alive and releases them during finalization. Uncaptured declarations
retain their normal lexical lifetime in Delphi mode; FPC-mode initialization
locals receive routine initialization, cleanup and exception protection.
Ordinary routine locals and their generated instructions are unchanged.

Local controls cover escaped string/interface captures in initialization,
the program body and finalization, shared mutation, sibling names, default
initialization, early exceptions and final destruction. They pass at `-O-`,
`-O2` and `-O3` on Win64 and Linux; Delphi 12.2 agrees in Debug and Release.

FPC-mode finalization locals also receive the same selective exception cleanup.
The RTL advances its finalization table before invoking a unit callback, so an
external handler can continue after that callback raises. Without cleanup, an
uncaptured inline interface in that callback leaked even though the remaining
unit finalizers ran. A local runner control now observes balanced creation and
destruction after catching that exception on both ABIs at `-O-` through `-O4`.
Callbacks without inline block locals keep their existing generated path.

## Consume a fresh custom-managed function result once

When a managed-record destination was addressable, the caller correctly kept
a separate hidden result so the callee could still read the old destination.
After moving that result, however, the generic helper initialized its empty
slot again for routine-wide cleanup. A user's Initialize could therefore run,
acquire resources or raise after an otherwise completed value transfer.

On Win64 and Linux, fresh composite results with custom Initialize/Finalize
callbacks now use aligned raw stack storage with one explicit lifetime. The
callee and destination cleanup run under a local exception handler: before
transfer it destroys the result and reraises, while a completed move consumes
the result without starting a replacement lifetime. This also applies through
record fields and static arrays; ordinary managed fields keep their existing
path. Destination addressing still happens once before the callee, preserving
the assignment helper's evaluation order; the callee sees its old value.

Local controls cover alias reads after writing Result, fields, elements,
pointer getters, inline and non-inline callees, static-array results, repeated
calls, callee and destination-finalizer exceptions, empty records, and loaded inline PPUs.
Win64 and Linux pass at `-O-` through `-O4`; Delphi 12.2 agrees with value and
resource controls. The ordinary RVO function has identical instructions on
both ABIs, and the addressed resource loop has no measured regression.

## Keep an SSE result store inside its exception region

On Linux `-O3`/`-O4`, a supported FPC hard bitcast of a floating function result
could produce `MOVQ XMM,GPR` followed by a pointer store inside `try`.
The peephole optimizer treated instructions separated by EH labels as adjacent
and moved the store before the handler. An access violation then escaped that
handler. The same defect also affected the Single/MOVD form.

When the XMM value is unchanged, the merged store now stays at its original
position. Moving a store upward after the XMM value changes uses the existing
memory/register safety checks and also rejects EH boundaries. Register-only
merges and ordinary adjacent stores retain their optimized instructions.

Local Double and Single controls pass on Linux and Win64 at `-O-` through `-O4`,
along with indexed destinations, reads before aliased writes and neighbouring
copy/EH peepholes. Delphi 12.2 agrees with the bit values and caught exception
through its Move-based bit-view oracle; that oracle uses a different lowering.
The ordinary Linux pointer store and read-before-store functions have identical
instructions before and after the repair.
