# Code layout rules for hand-written x86-64 assembler

## Acceptance of a manual layout change

The guidance below records earlier experiments; satisfying a layout rule does
not prove a speed improvement. The 2026-09-28 review rejected the subsequent
RTL and MoonORMot layout packet and retained the preceding layouts. In particular,
removing alignment and prefixes is a candidate change, not a safe fallback.

Compare a candidate with the existing product bytes at each supported CPU,
ABI, input case, entry phase, page offset and caller placement separately.
Include offset zero. Never average entry phases or positions for acceptance,
discard the slow tail, or turn a loss into zero because the A/A band is wide.
Missing coverage, failed byte/semantic checks and noisy controls prevent acceptance.
Use `qualification/performance/tools/manual_layout_judge.py` with an explicit
manifest. A uniformly faster result is preferred; a tradeoff requires a measured
gain above 10% and no measured loss above 5%, including the uncertainty reserve.

An aligned code section lets the assembler/linker preserve the requested entry
residue (check the object and linked executable). It does not fix its page offset
or the addresses of callers and neighbouring functions. The review probe spans
64 offsets at a 64-byte step and caller phases 0/32, and checks unpinned entries
at phases 0/32 separately. This is finite coverage of a warmed call loop, not a
guarantee for arbitrary program contexts, cold instruction caches or every
branch-predictor history. An accepted change also needs representative input
paths and a consumer comparison. The preserved layouts are the baseline, not
a claim that they have been newly proved optimal.

The frozen probe, commands and counterexamples are described in
`qualification/performance/asm-layout/README.md`. Hybrid Intel cores must be
tested separately: Linux's explicit PMU selector uses `cpu_core` or `cpu_atom`,
and a counter which did not run must fail instead of yielding a timing result.

Rules for routines written or rewritten by hand (`Move`, `FillChar`,
`CompareText`/`SameText`, number parsers, UTF-8, hashes) and for anyone
who audits them.  They come from the measured loop maps (Zen 3 and
Cascade Lake, `doc-int/experiments/tiny-loop-map/`), from the vendor
documents (AMD SOG 17h/19h on fetch and branch prediction, the Intel JCC
erratum note) and from the RTL profile stand, where every rule below
was accepted only after the A/B gate on both machines.  The code
placement draft of the internal assembler applies the same rules to
compiled code when it is switched on (`doc/OPTIMIZER.md`, "Code
placement"; off by default); hand-written blocks are kept as written, so
the author has to place them.

The assembler puts nothing inside a hand-written block: no branch pad,
no target pad, neither nops nor prefixes, and it does not place the
entry either - the routine asks for its line itself (rule 1), and its
bytes are the same with the draft and without it.  The reason is
length: a hand-written routine may be copied, patched or measured by
other code with its length hard-coded (mORMot's `PatchJmp(@fpc_ansistr_assign,
@_ansistr_assign, $3f)` copies exactly that many bytes of the routine
over the RTL's), and one pad the assembler once put behind a tail jump
cut the return off such a copy.  Everything below is therefore the
author's to do, by hand, in the source - and a routine that is copied
by length must keep its length.

The units of the machine:

- a **64-byte line** is what the instruction cache holds and what the
  front end fetches from; a taken branch into byte 52..63 of a line gets
  a fetch block of 12 bytes or less, and every extra line a loop touches
  is an extra fetch and decode per iteration;
- a **32-byte boundary** is where Intel excludes a branch that crosses
  it or ends on it from the decoded-uop cache (the JCC erratum
  mitigation); the prefixes that move a branch off it cost on Zen 3 at
  most +0.9% and on Zen 4 +2.4% in the worst form of the stand, on Zen 2
  and Zen 5 up to +6..8% (see "Where the rules were measured");
- the **fill** in front of a label is executed whenever the label is
  reached by fall-through: nops cost a uop each and fetch bandwidth, DS
  prefixes (`3E`) on ordinary instructions next to nothing on Zen 3 and
  Zen 4 and, inside a loop, up to +42..265% on Intel (same section).

## The rules

1. **Entry.** A routine begins on a 64-byte line: `{$push}{$codealign
   proc=64}` in front of it and `{$pop}` behind it (a `.balign 64` inside
   the routine lines its section up as well).  Neighbours share one pair:
   `{$codealign}` acts at once and `{$pop}` at the next token, so a pop
   followed by nothing but directives undoes the next routine's
   alignment.  The bytes before the entry are dead (after the previous
   routine's `ret`), so they may be nops.

2. **Short loop (at most 64 bytes).** The whole loop, head label to the
   end of its back-edge, lies inside one 64-byte line, and the back-edge
   does not end on byte 29-31 or 62-63 of the line (Zen 3: +25% and
   +66% even with the loop inside the line; a 63/64-byte loop has no
   such position and only stays inside the line).  Do not shift a loop
   off byte 53/54 for the sake of the map: it cost 10% on the stand.

3. **Long loop (more than 64 bytes).** The head is on byte 0, 16 or 32
   of a line - never in the tail of a line, inside the fast head zones of
   both maps (Cascade Lake runs a tiny loop at head 5..12 at half speed).
   Of these three positions take the one from which the loop touches
   the fewest lines: from byte 32 a loop of 97..128 bytes touches three
   lines instead of two (Pos +8%, UTF8Encode +6% on the stand), a loop
   longer than 112 bytes needs byte 0 for two lines.  Among equal line
   counts take the least fill: the fill is executed on every entry, and
   a loop that runs once per call (CompareText on one-character strings)
   lost 9% to 55 bytes of it.

4. **Branches and 32-byte boundaries.** No `jcc`, `jmp`, `call`, `ret`
   and no macro-fused pair (`cmp`/`test`/`add`/`sub`/`and`/`or`/`xor`/
   `inc`/`dec` followed by `jcc`) crosses a 32-byte boundary or ends on
   one.  Move them with DS prefixes (`.byte 0x3E` in front of the
   instruction) on the ordinary instructions of the same block, nearest
   first, at most three per instruction - not on branches, `lock`/`rep`
   instructions, VEX/EVEX encodings, `tzcnt`/`lzcnt`/`popcnt`/`crc32`
   (their F2/F3 prefix is part of the opcode), `int`, `push`/`pop`/
   `leave` or anything touching `rsp` (the Win64 unwinder recognizes an
   epilogue by its exact bytes), or instructions without operands.  A
   `call` or a forward jump does not end the block: prefixes may go in
   front of it as long as the moved branch keeps to this rule itself.
   A TLS GD `call` immediately preceded by raw prefix bytes is excluded:
   padding there would split the 16-byte sequence required by the ELF linker.
   Nops only where nothing executes them (after `jmp`/`ret`) or in
   front of a loop head, and there as few as rule 3 allows.

5. **Jump targets inside loops.** Every label a taken branch reaches
   lies in the first 52 bytes of its line.  Move it with prefixes on
   the block in front (rule 4's window); when that block cannot carry
   the pad - a `call` and a `test`, a fused pair - leave the target
   where it is rather than put nops in the path (TList.Exchange and
   CompareText loops lost 7-22% to such nops).  Never put a pad behind
   a tail jump in front of the routine's last label: it lengthens the
   routine for nothing (see the length warning above).

6. **Nests.** An outer loop with a loop inside cannot control its own
   end: keep its prefix (head up to the inner loop's head) inside one
   line and place the inner loop by rules 2 and 3. Among positions that
   fit the prefix, first minimize the number of 64-byte lines touched by
   the whole outer loop, then the fill: aligning the inner head while
   moving a 107-byte outer loop from two lines to three cost 5.6% in the
   Variant dictionary. Detect the nest before classifying the total span
   and measure its length without the pads (a 43-byte nest measured with
   last pass's pads as 70 bytes went "long" and lost 6-19%).

7. **Lines and branches.** Between taken branches an executed stretch
   should not cross a 64-byte line without need; at most two branches
   per 64-byte line from one entry (AMD BTB).  Constants for `movdqa`
   (`.balign 16`) never inside hot lines.

## Where the rules were measured

Rules 1-7 were measured on Zen 3 and Cascade Lake and hold there; they are
not a law of other cores.  The seven-CPU layout stand (Zen 2, Zen 3, Zen 4,
Zen 5, Haswell, Cascade Lake, Raptor Lake P-cores; 38 forms of code, each
laid out in 10-20 ways, cycles per operation against a control that differs
in the one thing measured, + = slower) found for the DS prefixes of rule 4
and of the fill:

- prefixes on the prologue that move a head, against a `jmp` over dead
  bytes to the same byte: median -3.2% on Zen 3 and -3.6% on Raptor Lake,
  within 0.8% on the others; the worst form +24.9% on Haswell, +8.3% on
  Zen 5, +6.9% on Cascade Lake, +6.3% on Zen 2, +2.4% on Zen 4, +2.0% on
  Raptor Lake, +0.9% on Zen 3;
- prefixes inside a loop, executed on every iteration, the loop's lines
  unchanged: median 0 on all seven; the worst form +265% on Raptor Lake,
  +45% on Cascade Lake, +42% on Haswell, +7.7% on Zen 5, +6.2% on Zen 2,
  +0.8% on Zen 4, +0.2% on Zen 3;
- prefixes on an outer loop's body that move the inner head: median -5.4%
  on Haswell and -2.7% on Cascade Lake, within 0.5% on the others; the
  worst form +0.8% on Zen 4.

No form had one layout faster than the release's on all seven cores (one
within the noise of the release's on all seven existed for 35 of the 38), so the
layout of a routine for all of them is not derived from these rules: it is
chosen on the stand, per routine, as the variant whose worst loss over the
seven is the smallest, and the rules stay what they are, a list of what not
to do.  The stand and its tables live in the local lab next to the `doc-int`
material: `lab/asmstand` (the table above: `SUMMARY_7CPU_20260927_run1.txt`,
the costs per knob) and the corpus of real routines `lab/asmstand2`.

## What is a coin, not a rule

- The end position of a long loop's back-edge.  The 66-byte map (Zen 3:
  fast when the back-edge ends on byte 7..36 of the next line) did not
  transfer to other lengths (the 85-byte map has the opposite zones);
  the stand lost on `containstext` and `move-16` when it was applied.
- A 64-byte loop that cannot fit a line because of a branch pad inside
  (head 63 with the end on 62 beat head 32 by 5% on `ldexp`).
- Anything that differs between the four placements of one binary
  (`variant-vartostr-int`: one placement equal to the baseline, two 15%
  slower) is address aliasing, not layout.

The mechanism behind the last item is now measured, not guessed: the
decoded-instruction cache is set-associative on the address inside the
page (Zen 3: 64 sets of 8 ways, bits 6..11; Cascade Lake: 32 sets of 8
ways of 32-byte windows, bits 5..9), so hot 64-byte lines of *different*
functions that the linker put at the same page offset compete for the
same eight entries. Three such lines with a few entry points each (a
function entry, a return address after a `call`, a loop head) need more
than eight, evict each other every iteration, and the path runs from the
decoders: +20% on the dictionary update case with byte-identical code
(`doc-int/experiments/prefix-lab/DICT_REGRESSION.md`). Moving any one of
the three by 64 bytes restores the speed. Small functions with several
`call`s in one line are the worst tenants. `qualification/performance/
tools/opcache_sets.py` counts the hot lines per set from a profile of the
executable and names the function to move; the procedure for a red row is
in `qualification/performance/README.md`.

## How to check - never by eye

```bash
python qualification/performance/tools/check_placement_rules.py <exe> --match '<routine>' --assert R4,R2E,R2X,R3H,R3L,RT,R1 --list-violations
```

reports every rule above per routine (R1 entry, R2E short loops, R3H
and R3L long loop heads and lines, RT targets with RTU for the
unpaddable ones, R4 branches) on the linked executable, where the final
addresses are known.  `hotdiff.py summary <exe>... --match '<routine>'`
prints the entry, every loop (head, length, lines touched, end byte) and
every target with its byte in the line for the same routine across
builds; `hotdiff.py dump` annotates the disassembly with line marks,
targets and crossings.

A new routine's candidate positions can be explored with a map: the generators in
`doc-int/experiments/tiny-loop-map/` (`gen_tiny_map.py`,
`gen_long_map.py`) build 64 copies of the routine behind `align 64` plus
N nops and time each with at least 15 rdtsc samples on both machines;
keep the map next to the routine. Acceptance follows the per-position policy
above. The older aggregate Pulse family gate is useful for consumer checks,
but its median and overlapping quartiles cannot certify a manual layout across
all placements. A/A instability has to be resolved or reported as unproved.

For an existing routine: audit with the checker and a map first, then
rewrite; report before and after in Pulse over the four placements.

The bundled memory manager is the worked example of a hand layout: block
order for the common path, DS prefixes for rule 4, a documented residue
of cold sites, and a gate that holds it
(`qualification/memory-manager/mm_layout_gate.py`; the layout is
described in [MEMORY_MANAGER.md](MEMORY_MANAGER.md#hand-laid-hot-paths)).

`Move` (`rtl/x86_64/x86_64.inc`, stand K of 2026-09-17) is the worked
example in the RTL: from 16 branches on 32-byte boundaries, five short
loops across lines and nine tail targets to none of each, with three
techniques that the rules above do not spell out:

- **Park a block, do not pad it.**  A block that a taken branch reaches
  and that is shorter than a line can start on any byte of its line: put
  `.balign 64` behind the previous `jmp`/`ret` and dead bytes in front of
  the label until its branches sit clear of the 32-byte boundaries
  (`.LCheckAvx` on byte 5 so that its tail `jmp` ends past byte 32; the
  small AVX tails on byte 32 with `.balign 32`).  Two 12-byte
  compare/jump pairs fit a 32-byte window only as bytes 0..23 or
  32..55; three never do.
- **Shorten the pairs before moving them.**  `lea -256(%rax), %r10` in
  front of the AVX dispatch turns four `cmp $imm32` (6 bytes each) into
  `cmp $imm8` (4 bytes): the signed compares against -128/-96/-64/64
  decide 128/160/192/320 just the same, and the dispatch fits a line
  with every pair off the boundaries and no prefix at all.
- **Short jumps forward are decided once.**  The internal assembler
  sizes a forward jump in one pass, on the addresses of its first pass,
  where every forward jump is long and a `.balign` takes its full width:
  the jump is short only if its target lies within 128 bytes counted
  that way (the draft repeated the pass to a fixed point, the default
  does not).  Place such a target *before* the jump (a short backward
  jump is decided at once), make the line in front fit even with the
  long forms, or write the short form out, on a line of its own with
  the mnemonic and label in the comment: `.byte 0x77,0x72 { ja
  .LWordwise_Prepare (rel8 written out) }` - data bytes are kept as they
  are.  The displacement is then the author's, per ABI where the two
  spellings differ in length and per FPCMM_* profile, and an edit
  between the jump and its target has to recount it.  The gates find
  such jumps by their bytes and build the unit a second time with the
  mnemonics of the comments - `rtl_asm_layout_gate.py` the RTL units
  with the RTL make's own command line, `mm_profile_matrix.py` every
  FPCMM_* profile of the memory manager - and fail on a written-out jump
  that lands elsewhere than its mnemonic or whose comment names none, on
  one the compiler compiled and the comparison did not reach, and on a
  `db`/`.byte` line they cannot read whole (write its bytes as `$XX`,
  `0xXX` or decimal without a leading zero, no expression, then at most a
  `//` or `{ }` comment): the listing of the object has to account for
  every byte of its code (what the check does not guard:
  `qualification/memory-manager/README.md`).
  In the memory manager a jump whose span holds `{$ifdef FPCMM_*}` code
  is written out only under the defines it was counted with and stays a
  mnemonic otherwise (`jne @Pending` in `FreeSmallPoolLockedHandoff`).

The SysV entry is the other lesson: register shuffling on every call
(three `mov`s) cost the first line nine bytes and pushed the 9..16 path
over it; the small paths now read `rdi`/`rsi`/`rdx` as they arrive and
only moves above 32 bytes take the Win64 roles.

`CompareByte`, `CompareWord`, `IndexByte`, `IndexWord`, the 4..8 tails of
the fill family and the string helpers (`fpc_ansistr_assign`,
`fpc_unicodestr_assign`, `fpc_ansistr_compare`, `fpc_ansistr_compare_equal`,
`fpc_unicodestr_compare_equal`) followed on 2026-09-18, and added four more
things worth knowing:

- **Make the hot length the fall-through.**  `CompareByte`/`CompareWord`
  used to test the short and the odd cases first and jump to the vector
  path.  One signed check in front (`cmp $16; jl`) sends everything short
  or unbounded away, and the vector path - what a string or record compare
  asks for - runs straight from the entry with the loop and the tail
  vectors behind it, no fill, no taken branch.
- **Two pairs in a row cannot be parted by prefixes.**  A prefix moves a
  pair as a whole, so two compare/jump pairs back to back have no position
  where the first ends before a boundary and the second starts on it.  Put
  an ordinary instruction between them (the assign routines move the store
  of the new pointer there, and their nil exit stores on its own), shorten
  one pair by bringing its jump target within a short jump
  (`fpc_ansistr_compare`'s generic stub), or reorder independent checks
  (`IndexByte` tests the page first and builds the search pattern behind
  the check).
- **Far paths get their own exits.**  A short path that lives in another
  line and jumps back into the main block's exits makes the block a loop
  for every tool that finds loops by backward jumps, and costs a long jump.
  A three-instruction exit is cheaper as a copy (`CompareWord`'s short
  path, `CompareByte`'s near zero exit).
- **Count the dead bytes when `.balign` would not converge.**  Where a
  block must start a line and the jumps in front of it are only short
  once it does, a fixed dead pad behind the `ret` (`.byte`, per ABI) gets
  there; `.balign 64` stays a line further with the jumps long
  (`IndexByte`).
- **One layout for both ABIs.**  Where the two spellings of a routine
  differ by an instruction length, make them equal and lay the routine out
  once: a DS prefix on the shorter first instruction (`RoundTo`: `movsx
  edx,dl` against `movsx edx,dil`), or each ABI working in its own argument
  registers instead of copying them into the other's (`StrComp`: the loop
  starts on byte 3 in both and lies inside the entry line, where the copy
  put it behind a 16-byte alignment and across the line).
- **The nearest return, the nearest trampoline.**  A conditional exit may
  take any `ret` of a frameless routine, and a jump to another routine may
  stand in the dead space behind the fast path's returns: every jump to it
  becomes a short one and none of them needs a pad (`RoundTo(Single)`).
  An address form without the `67h` prefix (`lea eax,[rdx+22]` for
  `[edx+22]` after a zero-extending `movsx`) is a free byte when a pair has
  to move back by one.

Outside the System unit the same rules were applied to `StrComp`, the three
`RoundTo` routines of Math (the fast path of every `RoundTo(Double)` call
ended its compare+jump exactly on a line), `SysRelocateThreadvar` of Win64
(every threadvar access; its return ended on byte 32), the varset routines
of `set.inc`, the error path of the Linux system call stubs and the two
hashers of Generics.Hashes: `crc32c` (its 16-byte loop ended on byte 32
behind the Win64 prologue: `align 32` instead of `align 16`; the exit of
every short key, `@1: not eax; ret`, lay across a line from byte 62: two
DS prefixes put it on the start of the next one) and `xxHash32`,
the hasher of a CPU without SSE4.2 and of the default Linux Variant comparer
(DS prefixes per ABI; on Linux the dword tail reuses its running pointer
and jumps over the space left by the removed pointer calculation).
Both entries explicitly request 64-byte alignment, including with GNU ld.
The Linux packages are built as PIC,
which takes out only the table code of `crc32cfast` (i386 assembler with
absolute addresses), so both routines run there in their SysV spelling:
`xxHash32` carries its own prefixes for it, the SysV `crc32c` needs none,
and the entry, rule 2 and rule 4 hold for both on a Linux image.  The list
of what nobody has laid out,
`qualification/performance/tools/unlaid_asm_routines.txt`, is empty: the
rule-4 gate of the stand checks the whole Pulse program, compiled and
hand-written code alike. The accepted Move preparation sites below are named
individually; a new entry in the unlaid list is a debt.

The gate for all of them is `qualification/build-driver/rtl_asm_layout_gate.py`.
The accepted Move count-bias implementation has two explicitly named rule-4
sites in its once-per-copy non-temporal preparation: the alignment-test `je`
at entry +2145 and the jump to the aligned loop at +2174, on both x86-64 ABIs.
They are outside the 60-byte hot NT loop, which fits in one 64-byte line.
The gate recognizes these exact offsets and branches; it does not allow two
arbitrary boundary violations or treat layout rules as proof of performance.
The semantic net under a layout edit is
`RTL-test/semantic/asm_block_routines_semantic.dpr` (a layout edit moves
blocks and rewrites jumps; the checker says where the bytes are and the
gate that a written-out jump goes where its mnemonic would, only a test
says the block it reaches still does the right thing).  The gate also compares
the exact source hashes recorded by the toolchain build with the current
hand-written ASM sources.  A source edit therefore requires rebuilding the
toolchain first: checking an older installed `System.ppu` is a hard failure,
not a green layout result.

## Unwinding hand-written frames

An exception, the stack walk of the diagnostics and a debugger find the
caller of a routine from its unwind information alone. The compiler writes it
for the frames it builds; a routine written in assembler writes it itself, or
it has none: then it is a leaf that moves neither `rsp` nor a callee-saved
register. A routine that pushes without saying so sends the unwinder to a
wrong return address - a fault inside `xxHash32` on a key that was not there
hung a Linux release program and left a debug one dead past its `try/except`
- and one that saves a callee-saved register without saying so hands the
caller its register back wrong (the same fault on Win64 was caught, with the
caller's locals damaged).

- **Linux** (`{$ifdef FPC_HAS_ASM_CFI_OFFSET}`: this compiler defines it for
  x86_64-linux; the bootstrap compiler, which builds the RTL of the build
  tools, knows no such directive): `.cfi_def_cfa_offset`, `.cfi_offset` and
  `.cfi_restore`, in standalone `assembler; nostackframe` routines of either
  reader (Intel: `.cfi_offset rbx, -16`; AT&T: `.cfi_offset %rbx, -16`).
  The saves are 64-bit integer registers at non-positive, eight-byte-aligned
  CFA-relative offsets, written in bytes. Inline ASM and compiler-owned frames
  cannot use them.
- **Win64** (`{$ifdef WIN64}`): `.seh_pushreg`, `.seh_stackalloc` and
  `.seh_endprologue`, each *behind* the instruction it describes (the
  unwinder counts a push as done from the address after it; directives in
  front put every one an instruction early). Win64 knows a frame only by a
  prologue at the entry and an epilogue of the shape `add rsp`/`lea rsp`,
  pops, `ret` or a jump away: nothing in the body may move `rsp`, so keep a
  value in a volatile register rather than push it there
  (`InterlockedCompareExchange128` keeps its result pointer in `r10`).
- A scratch slot needs no frame: the red zone below `rsp` on SysV, the home
  area of the parameters above the return address on Win64
  (`Math.FloatExceptionsUnmasked`).

Describe every push/pop and every out-of-line entry after an earlier epilogue.
A correct CFA alone can find a caller's catch while still corrupting its
callee-saved registers. Preserve the System V call alignment independently:
unwind metadata cannot repair a misaligned call into a Pascal or system
unwinder routine.

`qualification/build-driver/rtl_asm_layout_gate.py` checks this on every
routine of every object the toolchain installs and of the bundled memory
manager: `qualification/performance/tools/unwind_frames.py` walks each
routine along its branches and compares the stack depth and the pushed
callee-saved registers at every instruction with the routine's FDE or
UNWIND_INFO. Before that the gate compiles
`qualification/performance/tools/unwind_fixture.pas`, whose `Bad*` routines
the check has to report and whose `Good*` ones it may not. Three things are
let through by name: `fpc_longjmp`, which gives up its frame on purpose; the
Linux process entry and exit stubs (`si_c`, `si_g`, `si_prc`), which lie
under `PASCALMAIN` - its FDE marks the return address undefined, so no unwind
passes them; and three routines of the bundled memory manager whose Linux
paths push without CFI (`LockMediumBlocks`, `FreeMediumBlock`, `_FreeMem`):
the manager is MoonORMot's, `runtime/mm` its byte copy, and their repair
belongs there. The epilogues of compiled code on Linux carry no CFI (a stack
walk that samples a thread between its pops and its `ret` reads a wrong
caller; an exception cannot start there); the check counts them apart.
