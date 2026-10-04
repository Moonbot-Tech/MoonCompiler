# Medium-arena verification

`medium_single.dpr` is a minimal smoke test of ordinary allocation.

`medium_arenas.dpr` checks more than successful `GetMem`, `ReallocMem`, and
`FreeMem`. It requires the medium-arena profile to be active, creates medium
blocks from eight threads, proves the presence of several pool owners, and
passes blocks to other threads for `ReallocMem` and `FreeMem`. This executes
the owner-recovery path through the aligned pool header on Linux x86-64 and
Win64.

The test must run at least in O2 and O3. A diagnostic build with
`FPCX64MM_DIAGNOSTIC` also checks the internal lists and counters after the
cross-thread workload.

The full instrumentation is checked by
`../suite/tests/memory/memory_mm_diagnostic.dpr` and the
`../suite/scripts/mm/qualify_current_mm.sh` runner. The positive mode checks
the registry, `$A5/$DE` fills, realloc, tagged context, and explicit heap
traversal. Negative modes deliberately create a double free, a foreign pointer,
oversized `FreeMem(P, Size)`, corruption of the small owner, large links, and
deferred small/medium lists, including a worker-thread race. Each must print
exactly the first diagnostic error and exit with code 218.

This is an allocation registry and validation of allocator structures, not a
red-zone or guard-page mode for every block. The full contract, cost, and
boundaries are described in the “Diagnostic instrumentation” section of
`../../doc/MEMORY_MANAGER.md`.

`profile_contract.ps1` and `profile_contract.sh` check the product contract:
the precisely pinned MM must compile with `FPCMM_BOOSTER` and
`FPCMM_MOONSHARD`, and a missing profile must stop compilation.
The same scripts run `memory_hot_small_pool.dpr` (the pool reuse rules) and
`memory_zero_copy_contract.dpr`: `AllocMem` zeroes and a moving `ReallocMem`
copies every size from 1 to 5000 bytes correctly and leaves the neighbour block
alone, under both values of the zeroing threshold.

`zero_fill_map.dpr` and `copy_map.dpr` are the measurements behind those
thresholds ("Zeroing and copying" in `../../doc/MEMORY_MANAGER.md`): cycles for
zeroing or copying 256..4096 bytes with `rep stosd/stosq/stosb`, `rep movsb`
and SSE2 loops.  They build with plain `fpc -O3` on both systems; on Linux run
them under `taskset`.

`mm_profile_matrix.py` compiles and runs `mm_probe.dpr` (a smoke test that
names the MM unit itself, so it links under a vanilla runtime) over 21
`FPCMM_*` profiles: plain, standalone, server, boost, booster, the product
profile with `NOPAUSE`, `REPORTMEMORYLEAKS`, `CMPBEFORELOCK`, `SLEEPTSC`,
`NOMREMAP` and `NOSFRAME`, server and plain with `SLEEPTSC` and `NOSFRAME`,
moonshard, multithread, erms, tinyperthread, multiplesmall.  The unit keeps
every upstream conditional and the hand-written bodies branch on several of
them; a branch that no longer compiles, or a profile whose allocator no longer
works, fails here instead of at a user who builds their own mORMot with it.
The written-out short jumps (`db $75, $76 // jne @Pending`) are found by their
bytes - a `db` line (a label may stand in front) whose first byte behind
legacy prefixes is a jump opcode.  A line is a `db` line by its start, whatever
follows, and is read whole or fails naming the line: its bytes as `$XX`,
`0xXX` or decimal without a leading zero (the AT&T reader takes one for
octal), then nothing but a `//` or `{ }` comment - the finder reads no
expression (`$75 / 1`), no other spelling and nothing else behind the bytes,
and would not see a jump in them.  Each jump has to name its mnemonic and
label in the comment, or the matrix fails before it builds anything.  Each
profile is built a second time from a copy with these mnemonics: every direct
jump of the unit object (`mormot.core.fpcx64mm.o`, every routine of the unit,
also those the linker leaves out of `mm_probe` - `FreeSmallPoolLockedHandoff`
in the plain profiles) has to reach the same
instruction in both builds, so a displacement counted over the bytes of
another profile fails with the routine and the jump.  The compiler says which
written-out jumps a profile compiles, and they have to be the compared jumps
behind the marks, one for one - the copy puts a mark (a `nop` whose
displacement is the line) in front of its mnemonic, and a mark the compiler did
not name (its messages lost) fails too; each profile's line counts them, and
the matrix lists per jump in how many profiles it was compiled (the Linux one
of `_ReallocMem` in none on Win64).  A listing of the object that leaves any
byte of its code out - an objdump that prints nothing, a lost line, a `...`
(the listing is `objdump -z`, zeros are listed too), a direct jump whose text
names another target than its bytes reach - fails the profile naming the
written-out jumps it did not compare.

Every profile is built at -O3 and at -O-: a Release program compiles the
pinned unit at the first, a Debug program at the second.  From -O1 on the
internal assembler writes some addresses of hand-written code shorter
(`optimize_ref`: an index without a base at scale 1 or 2 becomes
base+index - `lea P, [rcx*2 + SmallBlockUpsizeAdder]` in `_ReallocMem` is 8
bytes at -O- and 5 at -O3), so an instruction in the span of a written-out
jump can have two lengths, and the jump be on its label in Release and off
it in Debug.  None does today; a copy of the unit with such an instruction
behind the written-out `jne @Slow` of `_GetMem` passes a -O3-only matrix and
fails this one at `product -O-`.

What this check (`code_placement.same_jumps`, shared with
`rtl_asm_layout_gate.py`) does not guard, and why:

- The object is read by objdump alone.  The listing is held whole and
  consistent in itself - every line understood, every byte of every code
  section, each jump's bytes against its text and target - not against the
  file: a listing forged in bytes, text and section table alike passes.  A
  second reader of PE/ELF would be one more tool to keep in step with objdump.
- The finder reads the lines that start with `db`/`.byte` (a label may stand
  in front).  A jump spelled with a wider directive (`dw`, `dd`, `.word`,
  `.long`), behind anything else on its line (another instruction, a comment)
  or behind a REX byte is not seen; the rule writes it as `db`/`.byte` on a
  line of its own and pads with DS prefixes, and no judged source has another
  data directive, a byte directive behind other code or a REX in front of a
  jump today.
- The RTL gate reads the files of its ASM provenance (`ASM_SOURCES`): a
  written-out jump in another RTL file is not seen.  A new hand layout joins
  the gate with its file; no other x86-64 RTL file writes a jump out today.
- A written-out jump is its line: finder, compiler message and mark agree on
  the line number, the routine in a message only labels the place.  Two
  written-out jumps of one unit on the same line of two files could stand in
  for each other, but only if one's message and the other's mark were lost at
  once; no two share a line today.
- A jump a platform compiles in no profile is listed, not failed (`compiled in
  0 of N profiles`, the RTL gate's `not compiled for this target`): the other
  ABI's spelling rightly compiles nowhere here, and the two platforms are two
  runs.  These lines are also all a run shows if the build of the copy were not
  the copy - the check writes the copy and points the compiler at it itself.
- A profile outside the 21 above, or a level other than -O3 and -O-, is not
  checked.

`mm_layout_gate.py` builds the same probe with the product profile and checks
the hand-laid code placement of `_GetMem`, `_FreeMem`, `_ReallocMem`,
`_AllocMem`, `FreeMediumBlock` and `InsertMediumBlockIntoBin` with the
placement tools of `qualification/performance/tools`: every entry on a
64-byte line, no jump, call or macro-fused pair crossing or ending on a
32-byte boundary inside the hot region of a routine, and no more cold sites
behind it than the documented residue (`--list-sites` prints them).  The
layout itself is described in `doc/MEMORY_MANAGER.md`, "Hand-laid hot paths".

The Win64 small-pool retirement handoff keeps the existing class lock only
after the leaf proves the pool must be released. Qualification must also
cover pending cross-thread frees: draining `LastFreeCount` concurrently
does not imply `BlocksInUse = 1`, and that predicate alone does not decide
whether a hot single-block pool should be retained. For contention timing,
record actual home class/medium-owner collision graphs and keep worker
identities fixed across compared implementations; equal worker counts
with fresh arbitrary thread IDs are not equivalent allocator inputs.
