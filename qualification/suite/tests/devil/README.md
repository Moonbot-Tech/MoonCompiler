# Devil

> **Quidquid latet apparebit, nil inultum remanebit.**
> *What is hidden will appear; nothing will remain unpunished.*
>
> **Festina lente.**
> *Make haste slowly.*

Two mottos, both operational.

The first sets the measure of coverage. In full:
`quod abundat non obstat, quod deficit nocet`—**what is abundant does no
harm; what is missing harms**. We therefore do not economize on independent
code forms: an additional layer increases run cost, but a missing class silently
leaves production code unchecked. At the same time, volume does not replace an
oracle: every form must prove its result rather than merely add lines.

The second sets the pace. Work begun before the subject is fully understood has
to be redone in full.

A generator of hunting programs for the compiler. Not a corpus: each seed
builds a new program rather than repeating an old one.

## Oracle design

No check compares against an answer captured from the compiler under test. Four
independent sources of truth operate:

1. **generator model** — a Python arithmetic model calculates the expected
   value (integers, IEEE bits, string operations, refcount balance);
2. **a second computation inside the program** — the same value is obtained
   through different lowering (64-bit masks instead of narrow types), so a
   faulty model and a faulty compiler cannot silently agree;
3. **build differential** — one source builds with `-O-`, `-O1`, `-O2`,
   `-O3`, and with `--ppu-reuse` also rebuilds over ready PPU; any difference
   between two builds is a defect even without external truth;
4. **Delphi 12.2 as arbiter** — the identical source compiles with `dcc64`;
   where the language does not define behavior (finalization order, mixed
   expression domain, layout), the result is compared rather than asserted.

Where no one has an established truth, the value is printed as an
**observation** (`DEVIL_NOTE` / `DEVIL_TRAIL`) and compared between builds.

## Representative layers

The generator currently contains 47 value-producing layers. The table below
highlights the main families; the complete ordered inventory is kept in
[`STATUS.md`](STATUS.md).

| Layer | What it hunts |
|---|---|
| `expr` | Binary arithmetic: 8 integer types × 10 operators × provenance × consumer × nesting |
| `unary` | `-`, `not`, `Abs`, `Sqr`, `Succ`, `Pred`, `Odd` |
| `fold` | Folding against runtime, including mixed types |
| `cmp` | Comparisons, including mixed signed/unsigned |
| `life` | Managed lifetime: balance, destruction order, exceptions, closures |
| `abi` | Record layout, sizes, offsets, by-value passing |
| `float` | Single/Double/Currency, conversions, rounding, intrinsics |
| `str` | AnsiString/UnicodeString/UTF8String/ShortString, COW, Copy/Delete/Insert/Pos |
| `disp` | virtual/inherited/metaclasses/method pointers/interfaces/closures |
| `gen` | Specializations, generic methods, class var per specialization, constraints |
| `arr` | Static/dynamic arrays, pointer traversals, ragged arrays, Slice |
| `unit` | Cross-unit inline, generics, and aliases through PPU |
| `opt` | Transformation correctness under hidden memory changes and aliasing |
| `reject` | Compilation as source: what must be rejected and with which diagnostic |

### Optimizer-effects matrix

The `opt` layer is not limited to a random set of known repros. Every run
constructs all 504 critical triples without omission:

- 12 routes that modify a value: global/cross-unit call, `var`, pointer,
  record/array element, ordinary/virtual/interface method, nested/anonymous
  capture, and procedural variable;
- 7 consumers provoking different transformations: induction multiply, CSE,
  array index/address, branch, division, shift, and mixed expression;
- 6 modification points: before, between, and after reads; only after the first
  or even iteration; and through `finally`.

Forms are distributed over `for`/`while`/`repeat`/nested loops and four
integer ABIs. The manifest requires all 504 triples, all 414 pairs of the
remaining axes, and one exact `I * Global` anchor with a call-induced change
after the first iteration. If the generator leaves a white spot, it fails before
the test program is compiled.

The oracle is calculated by a Python model of side-effect placement. One source
is then compared across Debug/O1/O2/O3 and Delphi 12.2. A green standalone test
`global changed by call` or `loop value changed by pointer` can therefore no
longer conceal their broken combination inside a particular optimizer pass.

## Running

Main gate:

```bash
python qualification/suite/scripts/run_devil_gate.py \
  --dcc "C:/Program Files (x86)/Embarcadero/Studio/23.0/bin/dcc64.exe" \
  --dcc-lib "C:/Program Files (x86)/Embarcadero/Studio/23.0/lib/win64/release" \
  --seeds 1,2,3 --cases 200 --ppu-reuse
```

Optimizer effects and adjacent legacy `opt` forms only:

```bash
python qualification/suite/scripts/run_devil_gate.py \
  --layers opt --seeds 1,2,3 --cases 200
```

Mandatory-rejection layer:

```bash
python qualification/suite/scripts/run_devil_reject_gate.py \
  --dcc "C:/Program Files (x86)/Embarcadero/Studio/23.0/bin/dcc64.exe" \
  --dcc-lib "C:/Program Files (x86)/Embarcadero/Studio/23.0/lib/win64/release"
```

One program for a specific seed, without the gate:

```bash
python qualification/suite/scripts/generate_devil.py --seed 7 --cases 300
```

The complete mandatory suite runs with one command and creates a unique report
directory under `qualification/suite/results/runs/`:

```bash
python qualification/suite/scripts/run_devil_all.py \
  --dcc "C:/Program Files (x86)/Embarcadero/Studio/23.0/bin/dcc64.exe" \
  --dcc-lib "C:/Program Files (x86)/Embarcadero/Studio/23.0/lib/win64/release"
```

The full runner stops at the first red stage, preserves the complete log, and
lists failed stages in the final JSON. For research collection of all independent
signals there is an explicit `--keep-going`; a release run does not require it.

### Fast and local loops

After a narrow repair, first run its exact focused/RTL repro, then the fixed
broad Light cycle:

```bash
python qualification/suite/scripts/run_devil_targeted.py light
```

Light is not a reduced random seed: it takes every layer at minimum density,
Debug/Release, registry, codegen, reject, ASM oracle, Chimera, and stress. On
the accepted Win64 machine, one all-layer program takes about five seconds; the
whole cycle takes roughly a minute.

When a repair is local, choose the next cycle by physical meaning rather than
the name of the changed file:

```bash
python qualification/suite/scripts/run_devil_targeted.py list
python qualification/suite/scripts/run_devil_targeted.py impact \
  --areas rtl-containers,managed-lifetime
```

The impact profile combines related layers and, where needed, adds an
independent gate: optimizer includes ASM/code shape, PPU includes
reuse/separate-unit/second-program, lifecycle includes Chimera. Every report
contains exact layers, commands, hashes, and the line `targeted regression only`;
a green partial run must not be presented as complete `run_devil_all.py`.

The full run also includes `asm-oracle`: seven families and 57 executable
comparison groups with independent handwritten x86-64 implementations. This
checks Pascal code generation and two ABIs, not an imitation of the product
mORMot path; see [`asm-oracle/README.md`](asm-oracle/README.md) for details.

All runners use the product toolchain from the current repository and write
generated sources, PPU, and binaries outside the tracked corpus. The mutation
bench deliberately changes product files and therefore requires an explicitly
provided disposable clone through `--repo`:

```bash
git clone --no-local . ../mooncompiler-mutation
python qualification/suite/scripts/run_devil_mutation.py \
  --repo ../mooncompiler-mutation --seeds 1,2,3 --cases 150 \
  --report .qualification/devil-mutation.json
```

The bench retains regression/tests while reverting only the
`compiler/rtl/packages` portion of each repair. A conflicting or non-building
mutation is not considered “killed”: it is an invalid experiment and the bench
itself is red. If a later causal repair rewrote the same product hunk and the
old reverse diff no longer applies, the bench retains a minimal current-tree
semantic mutation in `mutations/`; a conflicting application of that patch is
also an invalid experiment, not a kill. `killed/total` counts only actually
built mutants; a separate aggregation reports Devil families that emitted a new
signal. The full matrix also runs in a dedicated weekly/manual GitHub workflow.

Comparison uses the gate's complete JSON report before splitting it into `NEW`
and `known`. A broad known-deviation registry entry therefore cannot hide a
mutant signal, while existing known observations from a clean baseline are not
counted as its finding. A baseline is built separately for every exact generated
layer set: reports from different programs are not compared.

By default, each mutant runs its own and adjacent relevant generated families:
this fully proves observability without senselessly recompiling unrelated
multi-megabyte layers. `--all-layers` remains a rare stress mode; it changes
neither the mutant inventory nor the score formula.

## What red means

- `model-mismatch` — a build diverged from the model or another build;
- `observation-split` — an observation diverged (finalization order, layout,
  raw bool);
- `internal-error` — the compiler crashed instead of issuing a diagnostic;
- `timeout` — a hang;
- `false-reject` / `false-accept` / `verdict-split` — from the `reject`
  layer.

Already analyzed defects are listed in `known_findings.json` and count as a
separate `known:` line. They are not hidden—they are separated so that new
ones do not drown in known ones. Every registry entry links to an analysis in
`findings/`.

## Findings

`findings/` contains one directory per defect: a minimal repro and an analysis
of its boundaries.
