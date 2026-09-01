# Devil — Work Status

## Current classification

The investigation history is retained below, so older tables describe the state
when a finding was made and are not a registry of current defects. The canonical
result is:

- fixed Devil clusters have their own `findings/dvl-*` analysis, permanent
  regression, and final repair description in
  [`../../../../doc/COMPILER_FIXES.md`](../../../../doc/COMPILER_FIXES.md);
- the final language correctness cluster—`Default(T)` for a static array with
  management operators (dvl-0058)—is closed by transactional heap-backed
  lowering; evidence and rejected variants are retained in its
  [`FINDING.md`](findings/dvl-0058-class-array-field-init-table/FINDING.md);
- extended RTTI methods/public properties/`RTTI EXPLICIT`, both parts of
  dvl-0029, open-array custom-managed records, and every other former complex
  cluster are already closed by causal repairs;
- raw `PTypeInfo.Kind=tkBool`, permissive syntax, and other accepted
  deviations belong in `KNOWN_ISSUES.md`, not an active TODO;
- dvl-0061 (`Variant/OleVariant -> Cardinal`) and dvl-0062 (external-global
  mutation after AUTOINLINE) are closed by causal RTL/effect-model repairs and
  permanent semantic/Devil regressions;
- dvl-0063 (invalid scale-8 LEA) and dvl-0065 (late reread of `threadvar`
  rather than a result) are closed by causal x86 repairs and permanent
  regressions;
- dvl-0066 no longer raises an internal error: a generic-unit cycle with an
  imported classvar is rejected with a fail-closed diagnostic, while the allowed
  form without explicit cross-cycle inline continues to build;
- dvl-0064 is fixed: source constant folding is checked in the operation's
  signed/unsigned domain, while post-AUTOINLINE runtime wrap is preserved;
- dvl-0067 is closed: CONSTS no longer creates a persistent register temporary
  without REGVAR; the exact Advect regression agrees under ordinary O2/O3 and
  `-OoNOREGVAR`;
- dvl-0068 is not wrong-code: `inline` does not expand a method with a
  `const` record parameter and an external write. It is a measured missed
  optimization of a hot form, deferred to post-release optimizer work;
- dvl-0069 is accepted as a release boundary: Moon evaluates ordinary call
  arguments right to left, DCC64 left to right; the language does not fix the
  order and no product call proven to depend on it was found;
- dvl-0070 is closed in the RTL: `TArray.BinarySearch` continues its
  lower-bound search after equality and returns the first item in a run, like
  DCC64; Chimera checks the corrected caller contract, not a MoonBot application
  error;
- Devil's remaining work is coverage expansion and the mutation score from
  `BACKLOG.md`, then a full exact-HEAD run.

> This document was restored after the working directory was erased by a reverse
> minimizer launched from someone else's path. Facts and numbers were checked
> against source anew; the wording is new and the previous wording lost. What
> was lost irretrievably is stated in “Losses.”

## The `resident` layer — a handwritten production-scale program

A separate program, [`resident.dpr`](../resident/resident.dpr), is a ring of
dynamically registered stages that transfer ownership between threads; state
lives between laps. It calculates for real—Navier–Stokes, Fourier, long
arithmetic, Keccak-256 and secp256k1, π to many digits, ciphers, and
compression. Oracles are conservation laws, reversibility, and external vectors
from specifications.

Gate: [`run_devil_resident_gate.py`](../../scripts/run_devil_resident_gate.py).
All four profiles must produce one root; thread count must not affect the
result; rerun and rebuild must match. Design and rules:
[`README.md`](../resident/README.md).

The raw-ABI part of dvl-0049 is an accepted exact boundary in
`KNOWN_ISSUES.md`; the product `Rtti` facade is already fixed. dvl-0046
(StringToGUID), dvl-0047 (System.Integer/Word), dvl-0048 (empty Split),
dvl-0050 (BOM), and dvl-0051 (Unicode Variant) are already fixed by separate
causal repairs and focused regressions. dvl-0055 (Release reused a table lookup
address selected on the first pass) is fixed by the common loop-strength-
reduction invariant and locked down by a focused regression.

### Optimizer effects: from atoms to a closed matrix

The former `opt` contained correct but isolated forms: global reload after a
call, pointer mutation inside a loop, and table-index strength reduction. Their
combination was not mandatory, so every atom was green while O3 could break the
composition.

Every seed now always contains 504 forms from the complete product
`12 mutation routes × 7 optimizer consumers × 6 side-effect timings`,
distributed across four loop contexts and four integer ABIs. A fail-closed
manifest requires all 504 critical triples, all 414 dimension pairs, and the
exact anchor of the former stale-global scenario.

The first A/B on HEAD `88df3a25` immediately proved the value of the expansion.
Across three seeds Debug/O1/O2 and Delphi 12.2 matched completely; O3 produced
20/20/19 model mismatches. Causal analysis separated two old defects: strength
reduction did not see static-storage mutation through call/procvar, and constant
propagation carried the initial constant of a non-registerable parent-frame
local through a nested call. Both were closed as `dvl-0060`, without accepting
experimental LICM/address-cache branches. After ordinary bootstrap, exact seed
1 gives `905` checks in every Debug/O1/O2/O3 with one digest
`7E04B8BF7E8F8D9E`; findings/known = `0/0`.

## What is in place

47 generator layers, in declaration order (also the program order under
`--layers all`):

`expr`, `unary`, `fold`, `cmp`, `life`, `abi`, `float`, `str`,
`disp`, `gen`, `arr`, `unit`, `chk`, `thr`, `set`, `rtti`, `flow`,
`i128`, `lang`, `uni`, `exc`, `init`, `opt`, `call`, `inl`, `intf`,
`dyn`, `asm`, `io`, `decl`, `chain`, `meta`, `weave`, `matrix`,
`composite`, `genpath`, `narrowpath`, `pick`, `scope`, `lit`,
`capture`, `attr`, `deliver`, `load`, `rtllib`, `ppu`, `region`.

Plus separate gates for properties that cannot be checked by value: `reject`
(compilation as source, 82 forms), `stress` (internal errors and hangs), and
`codegen` (machine-code properties, 17 probes).

### Decision layers

The final layers ask not “what calculated,” but which decisions were made
**before** calculation. No model is written for them: rules are numerous and
their edges are precisely what is contested, so a case records the selected
decision and the oracle is agreement among three profiles and Delphi.

| Layer | Question | Size |
|---|---|---|
| `pick` | Which candidate did the compiler choose? | 74 questions |
| `deliver` | The same question, asked **after a transfer** | 178 |
| `scope` | Which of two same-named declarations does an identifier mean? | 19 forms |
| `lit` | What does a literal-originated value carry? | 52 |
| `capture` | What and when did a closure capture? | 18 forms |
| `attr` | Does an attribute reach RTTI tables? | 10 targets |
| `genpath` | Generic × narrowing × edge value | 240 |
| `narrowpath` | Route to narrowing × narrowing × edge value | 384 |
| `load` | Real allocator contention: owner canary, size, zeroing | 101 |
| `rtllib` | Standard-library contract against Delphi | 34 |
| `ppu` | What a declaration carries across a separate-compilation boundary | 24 |
| `region` | How many times did a protected region run? | 18 |

`scope` and `capture` match Delphi completely. That negative result is also
knowledge: name resolution and closure capture are sound in the compiler.

## Matrix: passenger × transfer

Every defect in this compiler's repair history has the same form: a value carries
something invisible besides magnitude, crosses a boundary between two stages,
and the invisible thing does not arrive. Signedness lost during folding. A
codepage lost on narrowing. A node flag lost during inline. Provenance that did
not survive PPU.

An unknown defect is an unknown pair (passenger, transfer). The pair space is
finite, so the `matrix` layer does not guess which pair is broken; it carries
**every passenger through every transfer**, recording a passport on both sides
of the boundary.

There are nineteen passengers: width, signedness, exact type, codepage, element
width, buffer, range-check state, visibility through an alias, lifetime,
refcount, RTTI identity, byte-string provenance, alignment, enum base size,
method-pointer data, exception-class identity, character-type width, aggregate
packing, and generic-argument identity.

There are twenty-seven transfers: folding, inline, module boundary,
specialization, closure capture, Variant, thread, narrow-and-widen, unwind,
record copy, interface cast, virtual call, typed file, property accessor, open
array, const parameter, dynamic-array detachment, declaration amid code,
variant-argument list, handwritten assembler, RTTI read, untyped file,
`inherited` call, raw byte move, universal `TValue` container,
message-number dispatch, and a method from a class helper.

There are **382** meaningful pairs, and all 382 are covered. Excluded pairs are
excluded by meaning and explanation (a codepage does not survive narrowing to a
byte; lifetime does not travel in a typed file); the manifest counts them.

Above each pair is a third dimension—**edge values**. A value from the middle of
the range survives lost narrowing invisibly because bits that should have been
cut are already zero. Every ordinal passenger therefore rides the matrix several
times, once for each edge value, and the case names which one. This found
dvl-0026: it sat exactly at an edge.

Above that is **composition**: a passenger crosses two boundaries in sequence.
One boundary is where a passenger is lost; two are where the loss is
**concealed**: the first stage clears an attribute, the second restores a
similar one, and a check looking at one boundary sees nothing. The 3D space has
1,954 triples, so each seed takes its own slice. A passport is captured three
times—before, between, and after—showing not only that a passenger did not
arrive, but which boundary lost it. Every third case adds a third boundary.

The stream carries **meaning, not a number**: type-kind numbering differs
between two compilers, so it receives not `Ord(Kind)` but the fact of equality
with a named constant.

### A slice must travel over the table

A layer taking `--cases` forms from its table once always started at position
zero: hunting over forty seeds asked the same two dozen questions forty times,
while the table tail reached only a run large enough to hold all forms. The
slice start now depends on the seed. The tail surfaced on its own—dvl-0031 came
from it. Small handwritten tables (`pick`, `scope`, `lit`, `capture`,
`attr`) are asked in full on every run.

## Circulation and passports

The chain previously carried a bare `Int64`, and the oracle was magnitude
identity. Magnitude is the most resilient passenger: it breaks only when
narrowing actually cuts a particular number. Everything else a value carries—
exact type, width, sign, carrier codepage, buffer, range-check state—could be
washed away at any stage and magnitude identity would remain silent.

Each stage now feeds a **passport** of what it received into an end-to-end
digest: size; behavior when narrowed to different widths (including an unsigned
type of the same width—the step that lost the passenger in dvl-0001 and
dvl-0026); sign; for string carriers, length, element width, and buffer
presence; and, for directives, actual `{$R}`/`{$Q}` behavior at that point.

The feed step is a bijection of the accumulator, so one wrong bit cannot
cancel: it spreads avalanche-like to the final result instead of dying at a
case boundary that did not inspect it. A subtotal is also computed per layer:
the root says that something broke; the layer says where.

Two things are deliberately excluded from circulation: observations of already
analyzed defects (otherwise a known difference colors the root forever and
masks a new one) and everything executed beneath threaded branching (two
branches feed the stream interleaved, so the digest stops being a program
property). The dvl-0018 trap is removed from chains for the same reason and
lives as a separate guard: it changes the **number** of passes, not only a
value.

## Instrument under observation

Circulation works only while every feed reaches the accumulator. If an optimizer
decides a feed is dead, or a layer silently stops feeding the stream, digests
continue to match and the construction goes blind without a signal.

The program therefore counts its own feeds and ordered-channel steps, prints
both counts, and the gate compares them between builds: a build that fed less
into the stream or took fewer steps stopped measuring somewhere even if digests
match. (The feed count was printed from the beginning, but the gate did not read
it, so the protection existed only on paper. Both counters are now read and
compared.) The code-generation gate has two neighboring probes for the same
property: the accumulator must multiply at every step and the opacity barrier
must not fold.

## Allocator load

The memory manager is the first unit in every program, so it runs in thousands
of executions—yet before the `load` layer it was checked by nothing. Worse,
allocator defects live beyond exhausted spin/retry, reached only by threads
genuinely fighting for one block class, and no layer created that fight.

Oracles were chosen to avoid MM diagnostics (the product profile builds it with
`FPCMM_BOOSTER`, which disables `FPCMM_DEBUG`): an **owner canary** catches
one address issued to two threads, plus issued-block size, zeroing where
promised, and balance of acquired and returned blocks.

The layer must prove the fight is real. The first version (eight threads, four
hundred rounds) showed zero waits using allocator counters—it never reached the
contested branch: MoonShard gives threads separate arenas and the short lock
finishes while spinning. Working parameters were found by measurement:
**48 threads**, hold time calculated from block size (small classes need more
blocks to exhaust the pool), cycling rather than volume for the largest class,
plus a **handoff** form where a block is freed by a thread other than its
acquirer, returning it outside its own arena.

Sizes are taken around the 704-byte boundary: 44 classes by 16, exactly where
the allocator's diagnostic array ended while the index continued. Separately,
`MaximumSmallBlockSize = 2608` was shown not to be the last serviced size: a
2608 request already takes the medium path; the last small size is **2600**.

Every heavy case captures the allocator wait counter before and after and
reports it as an observation: zero means the load degenerated into idle work.

## Planes found by the mutation bench

Sixteen reintroduced defects did not surface in the suite, and analysis produced
not a list of missing bugs but four entirely absent classes.

**The library as an object under test.** Devil ran the RTL in every program but
checked only its own code. The `rtllib` layer asks the contract: string lists
(case-sensitive/insensitive search, sort, duplicates, shift after deletion,
`Names`), streams (`Seek` to and beyond end, `CopyFrom`, partial reads,
Unicode), dynamic arrays (managed/unmanaged copy, tail zeroing on growth,
insertion/deletion), generic collections (deletion, sorting, `Extract`,
value overwrite, rehash, pair traversal), string functions, UTF-8 round-trip,
and paths. Delphi is the oracle.

**Instruction encoding.** A defect caught not by a wrong value but by assembler
rejection. The stress gate covers constants beyond an immediate, a field at a
large offset, more arguments than registers, a set spanning a byte's full
width, `case` labels at range edges, and a by-value aggregate too large for a
register.

**The separate-compilation contract.** The `ppu` layer asks not values but
what a declaration carries when a consumer sees it only in a compiled module:
alias width/sign, subrange bounds, enum/set size, typed-constant precision,
record/packed-record layout, field offset and method-table slot, interface GUID,
overload set, default value, calling convention, a generic specialized on both
sides, inline body, helper, class constant, published property, attribute.
dvl-0045 came from it immediately.

**Structure of exception regions.** The `region` layer counts not unwind
order (already covered), but how many times a `finally` body runs: in a loop,
on `Break`/`Continue`/`Exit`, at five nesting levels, around an inlined call
and inlined managed body, on re-raise, on handler exit, around a closure and a
thread wait. The language fixes this count unambiguously, so there is a model
and it is checked directly.

**What is deliberately excluded:** performance. Reverting an optimization
produces slow but correct code, which value checking cannot kill; a separate
project handles it.

## Build-mode matrix

The main gate varies optimization level, where divergence is meaningful. But a
build has knobs forbidden to affect behavior: debug information, smart linking,
symbol stripping, verbosity, disabled assertions, and building over ready PPU.
The modes gate (`run_devil_modes_gate.py`) builds one source under each and
compares not bytes but meaning: root digest, check count, instrument counters,
and every observation. Its first run found dvl-0044—the RTTI type catalog
depended on debug information.

## Ordered channel

The trail catches order only where it was explicitly written, while defects such
as dvl-0018 change the **number** of passes and live in a separate guard. The
ordered channel makes this a whole-program property: an event whose order is
fixed by the language feeds circulation through a noncommutative
`DevilStep` containing the event sequence number. An eaten, duplicated, or
reordered step breaks the root everywhere, not only where someone thought to
place a guard.

It is placed around every matrix transfer (a vanished or duplicated transfer is
now visible even if its value survived) and on every case in layers with fixed
tables (`pick`, `scope`, `lit`, `capture`, `attr`, `deliver`), where
table order is a program property.

It is absent, and must be absent, below threaded branching. Two branches feed
the stream interleaved, so the digest ceases to be a program property. The
`thread` transfer therefore does not feed steps, while layers with threaded
forms place the step in the case body, always on the main thread.

## Register-allocator pressure

The matrix carried passengers through calm contexts and the same allocator
paths. But defects such as “a definition read by another conditional move was
deleted,” “a needed extension was removed,” or “a receiver did not survive
register allocation” depend not on an operation itself but on what lies beside
it: peephole sees adjacent instructions and register allocation sees live-value
count.

Every third matrix case therefore travels inside scaffolding where the bank is
occupied: twelve live integers, a managed string, and an interface, all coupled
by one expression and all consumed **after** the transfer, plus an exception
frame around it. The allocator must spill and peephole sees different neighbors.
An incorrect spill is not an internal error but silent corruption, caught only
by the circulation passport. A pressured case names itself with the `-p`
suffix, so a finding under pressure does not appear to be one without it.

Two holes in the instrument itself were found and closed:

- **a case name must begin with its layer name.** The gate derives the layer
  from the name to avoid comparing a check between builds where one lacks that
  layer. Five layers used an abbreviation that matched no layer, so all their
  checks and observations silently dropped out of every comparison. The rule is
  now enforced twice: the generator refuses to write such a case and the gate
  refuses to call a run green after an unknown layer.
- **the per-layer subtotal must be read by the gate.** Runtime printed it from
  the beginning so a divergence in a value feeding the stream without its own
  check could be located. The gate did not parse that line. Subtotals are now
  compared, and the “digest follows an analyzed defect” rule absorbs them only
  when exactly the layers containing analyzed defects diverge.

## Mirrors

In addition to profile differential and rebuild-over-PPU, the program is
compared with itself:

- **fold mirror** — the same operation where the compiler can see constants and
  where it cannot;
- **inline mirror** — one body with inline forbidden and allowed;
- **specialization mirror** — a generic expanded here against the same generic
  pulled from PPU;
- **process mirror** (`--separate-units`) — units built one by one by separate
  compiler invocations against one invocation: the consumer then sees only what
  actually entered PPU, not the producer's live symbol table;
- **environment gate** (`run_devil_env_gate.py`, part of the suite)—perturbs
  everything unrelated to source: count/names of neighboring files, extensions,
  creation order, subdirectory, large file. Artifacts must match byte for byte.
  Before dvl-0041, nine of ten perturbations changed one uninitialized
  set-constant padding byte; after the repair, all 16/16 variants match;
- **determinism mirror** (`--determinism`) — the same source, same profile,
  second run, content comparison of `.o`/`.ppu`/`.exe`. Its first run found
  dvl-0041: machine code depended on unrelated directory files, so the build
  was unreproducible. Every trigger preserves evidence: both builds are retained
  in the run work directory under `results/runs/`, while
  `determinism-baseline.json` keeps source-fingerprint baselines. A mode holds
  in series, so divergence is more often visible **between** runs than within
  one.

## Leaking bait

If everything feeds the digest, the optimizer has nothing to discard and half
of its passes never run. The carrying stream is therefore accompanied by code
that looks removable, hoistable, or foldable—let it consume it. Yet one thread
from each bait feeds into the stream: through a pointer to a “dead” variable,
through a field behind an alias, through a closure capture, or across a unit
boundary. A legal optimization leaves the thread's value unchanged; a faulty
proof of “dead,” “does not alias,” or “can be hoisted” causes an avalanche.

## What makes it Devil rather than broad

Layers provide breadth: each asks one mechanism about one property. That is not
enough: defects live at the joins, and the two most severe findings came exactly
from there (dvl-0017—inline inside `finally`, dvl-0018—inline plus common
subexpression elimination). Layers that ask nothing independently therefore sit
above that breadth:

- `chain` — nesting **calls**. A value enters the first stage, and each stage
  obtains its answer only by calling the next from inside its own machinery:
  inside `finally`, a worker thread, an exception handler, a closure, a typed
  file, or an assembler routine. Stages are joined by an adaptor: it descends
  only from inside a loop, branch, `case` arm, `with`, or double guard block.
  Half the transitions also leave the source file—they enter a separate unit,
  receive the continuation through a function pointer, and call it there. The
  chain contains no straight-line code. Every chain runs twice: once carrying a
  value and once unwinding—an exception rises from the deepest level through
  every floor, and the invariant is not the value but balance: after it is
  caught at the top, nothing traversed may remain alive.
- `meta` — equivalent spellings of one semantic operation (loop, `for-in`,
  `while`, `repeat`, recursion, pointers, `goto`, closures, `Move`) that must
  agree **with each other**. No external oracle is needed, so this layer works
  even where no model exists and cannot be fooled by an incorrect expectation.
- `weave` — nesting **types**: a tree up to nine levels deep of generics,
  arrays, classes, interfaces, and managed records, checking width, copying,
  and the absence of leaks.

Chains and trees are woven together: a stage carries a value through a
four-level type, two spellings of the same semantics are compared midway through
the chain, two specializations of one generic live alongside it, a generic body
and virtual base arrive from a separate unit, and one stage passes its value to
the entire chain of an adjacent case—the layer ceases to be a set of independent
passes and becomes a graph.

A chain stage may be a **real form from any other layer**: a layout check, a
string operation, or a calling-convention probe. All execute from deep nesting,
inside a thread, an unwind, or a closure rather than from straight-line
top-level code.

The chains contain traps that reproduce the shape of already found defects
(dvl-0003, 0012, 0013, 0015, 0016). A trap breaks nothing—it reports an
observation—so identity remains a clean oracle while relatives of a known
defect surface on their own, without another test.

Independent axes over the whole construction:

- **declaration order** (`--shuffle-order`): the same seed is generated a
  second time with layers permuted. The compiler may lay out forms differently;
  it may not compute a different result.
- **second program** (`--second-program`): the same seed with one extra case
  per layer; everything both programs calculate for identically named forms
  must match.
- **whole-program invariant**: no one resets `EverBorn`/`EverGone` counters on
  the tagged object (the working `Alive`/`Born` layers cycle for themselves), so
  a leak in any layer is visible during finalization.

## Reverse minimization

`devil_minimize.py` cuts a divergence down to one small program. That is right
for most defects, but it destroys an entire class: a divergence that exists only
in the full program and vanishes together with its environment. In production,
these defects are the worst—they activate when user code grows the program into
the required state, while no isolated repro will reveal them.

`run_devil_bisect.py` cuts in the opposite direction: it fixes the case and
cuts the environment. First comes delta debugging over the layer composition
(the “a case name carries its layer” rule supplies ready-made cut boundaries),
then binary search over slice size, then named checks—removing which layer kills
the divergence. The last such layer names the mechanism. This found dvl-0040:
the bisector reduced the program to two layers and identified the culprit, after
which it became clear that the culprit left behind the
`{$RTTI EXPLICIT ...}` directive, which lives until the end of the module.

## Ban on arithmetic

No new numeric forms are added. Not one. Comparing the result of an arithmetic
operation is easiest, so coverage work naturally slides into endless numerical
permutations, leaving everything else unchecked. The numeric layers (`expr`,
`unary`, `fold`, `cmp`, `float`, `i128`) are frozen and limited to one tenth of
the case budget (`ARITHMETIC_SHARE`).

This also gives the criterion for a finding's value: a divergence matters only
if it can corrupt a production program. `Inf-Inf` producing zero instead of NaN
is not worth a line in the report.

One qualification for the `deliver` layer: it uses forms such as `x + 0` and
`x * 1`, but these are not numeric tests. It is not the result that is added,
but the delivery form; the check is not its magnitude, but which candidate was
called. These forms come from the compiler's own repair notes, which say that
constant provenance is reset by parentheses, casts, and arithmetic identity.

## How Devil is built

Only through the build-driver contract: `devil_toolchain.py` reproduces the
`build.ps1` command line word for word—Delphi-Unicode ABI, fixed MM as the first
unit, System aliases—and changes exactly the optimization level. `debug` and
`release` match the driver byte for byte; `o1` and `o2` exist so a defect living
between levels is visible. Building Devil with bare `ppcx64` and a custom set of
switches is forbidden: that would test a compiler no one ships.

The generated program declares `mormot.core.fpcx64mm` first in `uses` under
`{$ifdef FPC}`: Delphi has no such unit, while the arbiter must compile the
same source. For the same reason, `{$push}{$optimization off}` islands are
enclosed in `{$ifdef FPC}`, and atomic operations use the portable
`AtomicIncrement`.

## Findings (findings/)

> Classified by meaning—problems, known deviations, questionable cases, and
> “for reference”—in the [findings journal](FINDINGS_JOURNAL.md). It also
> cross-checks against the defect catalog.

| id | summary |
|---|---|
| dvl-0001 | **fixed by the common narrow-extension peephole repair; five layers are green in Debug/O1/O2/O3** |
| dvl-0002 | ICE 200706094 on `Odd(UInt64 constant)` |
| dvl-0003 | O2/O3 reverse finalization order during exception unwinding |
| dvl-0004 | comparison with a C-style Boolean is not normalized to 0/1 |
| dvl-0005 | an out-of-bounds constant array index is silently accepted |
| dvl-0006, 0008, 0009, 0010 | divergences where Delphi is wrong |
| dvl-0007 | **fixed: the product runtime installs the platform monitor manager automatically; Win64/Linux gates and the generated `monitor-counter` form are active** |
| dvl-0010 | Delphi truncates an Int64 case selector to 32 bits; our compiler is correct |
| dvl-0011 | O3 sign-extends the upper half of a 128-bit result |
| dvl-0012 | **fixed: a Delphi-Unicode ASCII literal/`Chr` produces `Char`, and `array of const` receives `vtWideChar`** |
| dvl-0013 | **fixed: an explicit byte-string cast preserves storage/code page; assignment still transcodes** |
| dvl-0014 | observation: RTTI names of string types differ from Delphi |
| dvl-0015 | **fixed: the carrying Variant type of an integer-valued constant is selected by value, as in Delphi** |
| dvl-0016 | a real literal in Variant is stored as Double rather than Currency |
| dvl-0017 | `Internal error 200405231`: inline of a managed procedure in `finally` |
| dvl-0018 | `release` coalesces two calls to a side-effecting function in one expression |
| dvl-0019 | `TProc`, `TFunc<T>`, `TPredicate<T>` are absent from the RTL—a code-porting blocker |
| dvl-0020 | `inline` with an open array: Delphi rejects, we accept |
| dvl-0021 | `varargs` without `external`: Delphi accepts, we reject—a blocker |
| dvl-0022 | a set element outside range: Delphi accepts, we fail with an assembler error |
| dvl-0023 | `{$mode}` in source overrides switches supplied by the driver |
| dvl-0024 | anonymous `reference to` in a variable declaration: Delphi rejects, we accept |
| dvl-0025 | constant shift wider than the type: Delphi rejects, we accept |
| dvl-0026 | **fixed by the same repair: generic return preserves unsigned narrowing** |
| dvl-0027 | real literal versus `Double`/`Currency`: Delphi rejects it as ambiguous; we silently choose `Double` |
| dvl-0028 | **fixed by the common range rule for `Integer/Cardinal` and `Int64/UInt64` pairs** |
| dvl-0029 | **the ASCII part is fixed; non-ASCII source-codepage semantics remain a separate TODO** |
| dvl-0030 | **fixed: ASCII literal concatenation in Delphi-Unicode preserves `UnicodeString`** |
| dvl-0031 | **fixed: a string literal materializes in owning escaping storage; stack shared semantics are preserved** |
| dvl-0032 | **fixed: attributes are parsed on parameters, inline variables, and `class var`; `[ref]` is not broken** |
| dvl-0033 | a marker attribute without its own constructor is rejected in every position |
| dvl-0034 | a method name without parentheses before `reference to`: we invoke it, Delphi takes its address |
| dvl-0035 | **fixed: Delphi management operators work for records, value/open/static-array parameters, and aggregates** |
| dvl-0036 | **fixed: `const [ref]`/`[ref] const` use the existing `constref` ABI** |
| dvl-0037 | **fixed: fields, methods, and public properties with attributes are visible through extended RTTI** |
| dvl-0038 | helper name in type position: we accept it, Delphi rejects |
| dvl-0039 | **fixed by the same range rule: a type outside signed range selects the unsigned candidate** |
| dvl-0040 | **fixed: `{$RTTI EXPLICIT ...}` controls attribute payload without breaking published enumeration** |
| dvl-0041 | **fixed: logical 5–7-byte set constants are separated from eight-byte ABI padding; environment gate 16/16** |
| dvl-0042 | **fixed: COFF bigobj no longer truncates the 32-bit section unwind-symbol number to `Word`; the focused gate crosses 65 535 sections and runs the result** |
| dvl-0043 | **fixed by the same repair: the exact `with`/register-allocation repro is green** |
| dvl-0044 | **not a defect: `-gl` connects the actual `LineInfo`/`ExeInfo` units; the two extra types are `LineInfoCache` and `TExeFile`; modes gate now compares DWARF2/DWARF3 with the same unit graph** |
| dvl-0045 | **fixed by the common narrow-extension repair: PPU alias is green in Debug/O1/O2/O3 and on PPU reuse** |
| dvl-0046 | **fixed: the byte-based `ShortString` GUID parser uses `PAnsiChar`; valid/invalid/round-trip gate is green** |
| dvl-0047 | **fixed: qualified `System.Integer` matches the language type; Word sorting and binary search are green** |
| dvl-0048 | **fixed: empty source produces an empty array across the whole `Split` family; Delphi/FPC regression is green** |
| dvl-0049 | **the exact boundary is accepted: the facade is Delphi-compatible; the raw ABI retains the agreed FPC `tkBool` layout** |
| dvl-0050 | **fixed: `TStrings.WriteBOM=True` is the Delphi default; UTF-8/UTF-16, empty/save/load, and opt-out regression are green** |
| dvl-0051 | **fixed: Unicode sources produce `varUString`; operator/compare/concat and BSTR-storage Variant SAFEARRAY are verified before the full runtime** |
| dvl-0055 | **fixed: strength reduction does not hoist an indexed lookup across a loop that changes the same array; focused test and AES/FIPS oracle are green** |
| dvl-0053 | **fixed: O2/O3 CSE distinguishes IEEE `+0.0` and `-0.0` when fast math is not permitted** |
| dvl-0056 | **accepted in our favor: inline preserves the sequential semantics of non-inlined side-effect calls** |
| dvl-0057 | **fixed: the callee owns finalization of an operator-record value copy; the inline frame preserves the same lifecycle** |
| dvl-0058 | **fixed: the class init table expands static-array fields with management operators; `Default(T)` and temporary reuse are covered by adjacent repairs** |
| dvl-0059 | **fixed: TList and adjacent containers preserve one unified model of live managed slots** |
| dvl-0060 | **fixed: O3 does not retain a global/static or captured scalar across an opaque call, procvar, or nested parent-frame mutation** |
| dvl-0061 | **fixed: `Variant`/`OleVariant` convert to `Cardinal` through unsigned `varLongWord`, not signed `Integer`** |
| dvl-0062 | **fixed: strength reduction checks a static scalar against the unified effect model of the final post-AUTOINLINE tree** |
| dvl-0064 | **fixed: source constant overflow is distinguished from legitimate runtime wrap after AUTOINLINE and optimizer reassociation** |
| dvl-0069 | **accepted boundary: the language does not promise ordinary-call argument order; no live product dependency is proven** |
| dvl-0070 | **fixed: `TArray.BinarySearch` returns the lower bound of equal values, as in Delphi** |

## Losses

The working directory was deleted by the reverse minimizer run against the
suite's own path. Git restored only committed files.

- Restored: the `devil_runtime.pas` instrument (it survived as a copy in the
  bisector's work directory), analyses dvl-0027…dvl-0040, the analyzed registry
  (rebuilt; entries for lost defects are marked directly in the file), this
  document, and `BACKLOG.md`.
- Lost irretrievably: the full analyses of **dvl-0012…dvl-0026** and their
  `repro-standalone.dpr`. Only the row in the table above remains for each—the
  sole surviving trace.
- The generator and gates were unaffected: they live in `scripts/`.

## Status of criteria

- **Criterion 1** — `TMonitor` and platform differential are no longer
  blockers. Only mutation score/family usefulness and moving a reproducible run
  into CI remain in `BACKLOG.md`.
- **Criterion 2** — deferred to the end by the owner's direct instruction. The
  bench is ready (baseline measurement before the cycle, driver build, refusal
  on a dirty tree) and runs only on a clean tree.

## Rules earned in blood

- rebuilding the compiler is mandatory after a mutation; otherwise the next run
  measures the mutant;
- `Synchronize` from a worker while the main thread calls `WaitFor` is a
  deadlock in the test itself, not a compiler defect; the layer retains only
  `Queue`;
- every binary run needs a timeout, otherwise one hung run stops everything;
- every divergence is checked against Delphi first: half the “findings” turned
  out to be model errors;
- every gate needs its own registry of analyzed findings, otherwise it remains
  red forever or, worse, a rule from another registry suppresses a build break;
- subroutine names in a layer must carry the layer name: every layer enters one
  program, and `DvlMake00011` from two layers is a compilation error for the
  entire run;
- **a case name must begin with its layer name**—otherwise the gate silently
  excludes it from every comparison;
- **the per-layer subtotal must be read by the gate**, otherwise a divergence
  without its own check reaches the root digest without an address;
- **a table-driven layer's slice must travel across the table**, otherwise the
  table tail is never queried;
- an observation without a model must have at least one check nearby: a layer
  whose only output is an observation shows zero checks, and zero is
  indistinguishable from “the layer did not run”;
- the model follows the Delphi contract rather than our behavior; otherwise the
  reference turns red and a finding looks like an arbiter error;
- the trail is program-wide: a layer that needs to measure order beyond its own
  case must maintain its own;
- **two direct runs of the same standalone gate require different `--work`**;
  `run_devil_all.py` gives every full run its own unique directory;
- everything the program prints uses the same lock as the trail: otherwise a
  worker-thread stage joins its line to the main-thread line;
- runtime stays outside the inliner (`{$optimization noautoinline}`): otherwise
  dvl-0017 takes every layer that writes the trail, and measuring code must not
  dissolve into what it measures;
- **a layer must restore a directive that acts until the end of the module
  (`{$RTTI}`, `{$M}`) immediately after its case**—otherwise it colors every
  subsequent layer and their divergences look contextual (that is how dvl-0040
  was born and remained unresolved for a day and a half);
- **directive state must be restored to its exact default**, not a “similar”
  one: narrowing stronger than the default crashed the arbiter at runtime
  across the entire program;
- **a tool that deletes its work directory must refuse to operate in someone
  else's**—and the check must sit outside probes, otherwise a probe consumes its
  `SystemExit` and counts it as a negative answer;
- scripts print ASCII only: this console is cp1251, and a Russian string in
  `print` makes the patch fail after it wrote the file—duplicating the result;
- paths to the work directory resolve to absolute paths **before** entering it:
  the build runs with `cwd=work`, and a relative path turns into `work/work`;
- some suite units are handwritten rather than generated: a tool that builds a
  program in a foreign directory must copy them there.
