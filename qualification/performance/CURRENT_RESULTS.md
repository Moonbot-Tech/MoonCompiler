# Pulse: current results and optimization history

## Final release snapshot — 2026-08-30

The complete Win64 O3 medium run at clean HEAD
`64067c9949c24f688c29c048ec3051ddce0b5847` compared Delphi 12.2,
Moon+bundled MM, and Moon+default FPC MM:

- `757/757` semantic oracles MATCH;
- excluding 13 unstable process cases: Moon/Delphi geomean `0.8310`, 360 faster,
  289 at parity, 95 slower;
- Heartbeat: geomean `0.8185`, 18 faster, 2 at parity, 0 slower;
- allocator group: bundled MM / default FPC MM `0.6069`, meaning our MM is
  approximately `1.65` times faster;
- across 369 shared stable cases relative to the final 2026-08-23 snapshot,
  geomean improved from `0.7722` to `0.7439`.

Versioned evidence, hashes, and process-stability boundaries are in
[`evidence/release-final-20260830/EVIDENCE.md`](evidence/release-final-20260830/EVIDENCE.md).
A new column was added at the right of [`PULSE_HISTORY.html`](PULSE_HISTORY.html);
previous results were not overwritten.

## Heartbeat after inline exit and trigonometric reduction

The exact Win64 O3 medium run on the current tree executes 20 independent lines
of one composite Heartbeat program. All `20/20` semantic oracles match. Result
Moon/Delphi: geomean `0.848`, 15 lines faster, 4 at parity, 1 slower.

Two proven roots were closed separately:

- local `Exit` from an inline body no longer inherits the caller's unwind and
  does not call `_FPC_local_unwind` when control remains inside the caller;
- ordinary `Sin/Cos` argument reduction uses multiplication by `2/Pi` and one
  `Trunc` instead of division and two `Floor` calls, retaining `Double` and the
  previous Payne/Hanek fallback.

The isolated nine-run `Sin+Cos` measurement: Delphi `54.895`, Moon `48.607`
cycles/pair, Moon/Delphi `0.8854`. In complete Heartbeat, the only remaining
loss is FFT `1.087x`; this is no longer trigonometric runtime but the
address/loop/register-allocation portion of code generation.

## Additional TDictionary matrix

At clean HEAD `10f422932c8e4789e87ae4693535d3b3b77041ba`, a 24-case dictionary
matrix was added and run separately: three scalar/string key/value combinations,
100 and 10 000 elements, four independent operations. The compiler binary did
not change relative to the complete snapshot below.

- semantic oracle: `24/24 MATCH`;
- one Delphi process pair is marked with `1.255x` drift;
- across 23 stable cases, Moon/Delphi geomean `0.9569`: 10 faster, 3 at parity,
  10 slower;
- string hit/miss lookup is faster than Delphi: `0.311x`/`0.505x` at
  100/10 000 elements;
- open roots: large reserved table in the bundled MM and managed-value churn.

Exact numbers, hashes, and the conclusion boundary are in
[`evidence/dictionary-matrix-20260823/EVIDENCE.md`](evidence/dictionary-matrix-20260823/EVIDENCE.md).
The new general HTML-table column inherits the prior 390 cases and adds 24 new
ones; old results were not overwritten.

## Exact current main

The complete Win64 O3 medium run at clean HEAD
`81daffaa8bd943c02a011f57b2af6e94085d398f` compared Delphi 12.2,
Moon+bundled MM, and Moon+default FPC MM:

- 390 cases;
- semantic oracle: `390/390 MATCH`;
- nine process-drift cases are excluded from focused conclusions;
- stable Moon/Delphi result: geomean `0.7318`, 195 faster, 118 at parity,
  68 slower;
- allocator group excluding unstable `alloc-free-1m`: bundled MM / default FPC
  MM geomean `0.6179`, meaning our MM is `1.62` times faster on average.

Across 379 shared stable cases in the previous and current snapshots, geomean
changed from `0.7233` to `0.7323`, so the current snapshot is `1.24%` slower.
These are different complete runs, not pre/post A/B of one fix: the figure is
recorded as product state but not attributed to a particular change without
focused A/B.

Versioned evidence, hashes, and the full list of unstable pairs are in
[`evidence/integration-final-20260823/EVIDENCE.md`](evidence/integration-final-20260823/EVIDENCE.md).
A new column was added at the right of [`PULSE_HISTORY.html`](PULSE_HISTORY.html);
previous results were not overwritten.

## Previous safe integration snapshot

The complete Win64 O3 medium run at clean HEAD
`c0139f0ea4cf7f0265a7df9ef349fff8c77dc612` compared Delphi 12.2 again with
Moon+bundled MM and Moon+default FPC MM. The unsafe historical `Ref=1` fast path
is absent from this HEAD.

- 390 cases;
- semantic oracle: `390/390 MATCH`;
- three process-drift cases are excluded from focused conclusions;
- stable Moon/Delphi result: geomean `0.7230`, 203 faster, 120 at parity,
  64 slower;
- MM group: bundled MM / default FPC MM geomean `0.591`.

Versioned evidence, hashes, and the full list of unstable pairs are in
[`evidence/integration-current-20260820/EVIDENCE.md`](evidence/integration-current-20260820/EVIDENCE.md).
This column is retained as the previous product result in
[`PULSE_HISTORY.html`](PULSE_HISTORY.html) and was not overwritten by the new
snapshot.

> **Applicability boundary.** This is a historical journal of branch
> `perf/remaining-gaps-20260817`, not a measurement of current `main`.
> Waves 35–38 contained experiment `5859133d` (`Ref=1` without atomic
> increment), which the integration audit rejected: two threads can
> simultaneously read one shared string with a single initial reference, both
> write `2`, and lose one refcount. Therefore, the absolute results of these
> waves are retained only as research history. The exact current snapshot is
> published in a separate column above.

## Remainder-audit result, wave 1 — TStringHelper facades (PERF-035)

The complete Win64 O3 medium snapshot `results/pulse/wave38-full` — 390 cases
(+7 helper sentinels). Fix `b33fe461`: one-pass Split with
vectorized IndexChar, IndexOf(string) through Pos, nocase facades without
allocations (shared SameTextRange), and SameText with an inline ptr-equal
shortcut; in addition, a Pulse data bug was fixed (trim-string measured
empty strings).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After batch C (wave37) | 383 | 0.724 | 210 | 117 | 56 |
| **After helper facades (wave38)** | **390** | **0.718** | **216** | **116** | **58** |

Helpers in the complete snapshot: `helper-split-16` **0.893** (was 2.255),
`helper-indexof-string` **0.803**, `helper-startswith-nocase`
**0.064**, `helper-endswith-nocase` **0.062** (about 15 times faster than
Delphi — they build Copy/LowerCase temporaries on every call),
`sametext-short` 1.07 (noise around parity), `trim-string` **0.560**
on real data. The shared set of 383 cases: 0.724 → 0.725 — prior cases are
unchanged. Matrix 156/156 across 52 sources, gate 58, oracles MATCH.

## Batch C result (PERF-034)

The complete Win64 O3 medium snapshot `results/pulse/wave37-full` — 383 cases
(+9 batch-C sentinels). Fix: signed mod by a constant without idiv
(`a78cb980`, at nmat node level — pow2 branchless mask, all other cases through
`x-(x div C)*C` with CSE merging into the adjacent div).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After batch B (wave36) | 374 | 0.710 | 211 | 110 | 53 |
| **After batch C (wave37)** | **383** | **0.724** | **210** | **117** | **56** |

The numerical geomean increase is composition: batch C added cases where
**ceiling parity** is confirmed (int64-mod-latency 1.000 — identical magic
chains to Delphi at 11.77 cycles; packed-odd-sizes 1.004; int64-div-const
1.010). Across the shared set of 374 cases, 0.710 → 0.722 is entirely placement
variation (case-dense up ↔ case-sparse/call-virtual/branch-random/for-byte down,
noise overall). Batch-C wins: `int32-div-const` **0.786** (our shared division
versus two separate Delphi magic sequences), `uint32-div-const` 0.877, generic
specialization is bit-for-bit equal to handwritten code, and 16-byte records
are copied 2.7× faster (`generic-reverse-rec` 0.373). Matrix 153/153 across
51 sources, gate 58, oracles MATCH.

## Refcount-wave and batch-B result (PERF-031/032/033)

The complete Win64 O3 medium snapshot `results/pulse/wave36-full` has 374 cases
(+8 batch-B sentinels). Fixes after the optimum pass: unconditional lock
refcounts + the ANSI-ASM trio (`PERF-031`), Ref=1 without bus lock (`PERF-032`),
and dynarray loops with an advancing pointer (`PERF-033`, optloop `a9e02d16`).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After the optimum pass | 361 | 0.725 | 182 | 115 | 64 |
| After the refcount wave (wave35) | 366 | 0.733 | 186 | 116 | 64 |
| **After batch B (wave36)** | **374** | **0.710** | **211** | **110** | **53** |

Wave36 key result: `for-length-array` **0.57** (was 1.03 — the dynamic-array
loop reread the base on every iteration); through the same transformation,
`aos-one-field` 1.02 → **0.62**, `soa-one-field` 1.01 → **0.56**, and
`generic-list-remove-128` → **0.48**; `minmax-double` **0.41** (we use
`minsd`/`maxsd`, Delphi branches), while Min/Max NaN/±0 semantics are
bit-for-bit equal to Delphi (matrix pin). Matrix 150/150 across 50 sources,
gate 58, oracles MATCH. The slow tail consists of closed zones (MM/Move:
`inttohex-int64` 1.93, `move-1024` 1.52; decrement locks:
`insertrange-2048` 1.55) and the placement class (`call-virtual` 1.38,
`case-sparse` 1.43, `try-finally-normal` 1.44 — code is bit-for-bit, proven
previously).

## Optimum-pass result (BRANCH_AUDIT “Optimum pass”)

The complete Win64 O3 medium snapshot `results/pulse/wave31-full` has 361 cases.
The pass is measured against the algorithmic ceiling (mORMot/SWAR/bandwidth),
not Delphi: direct integer parser (`8a4e8e42`), StringReplace with an inline
scan without heap allocation before the first match (`a819cb5a`), SWAR kernels
for string operations (`64220bf6`), and two nibbles per hexadecimal step
(`04bc2503`).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-030 | 360 | 0.727 | 183 | 114 | 63 |
| **After the optimum pass** | **361** | **0.725** | **182** | **115** | **64** |

Key cases of the pass: `trystrtoint` `1.90 → 1.14` (edges **0.88**, ahead of
Delphi), `string-replace-all` `1.40 → 1.11` (reached 0.999 in RTL focus), and a
case-map probe at **1.4 cycles/character** — the bandwidth ceiling. The
call-interface/call-virtual `1.16` “regressions” are a twice-proven placement
class (code is bit-for-bit identical to baseline at the same addresses). Matrix
144/144 (48 sources), gate 58.

## RTL-audit result, wave 3 + conversion cleanup (PERF-030)

The complete Win64 O3 medium snapshot `results/pulse/wave21-full` has 360 cases
(+5 wave-3 sentinels). Fixes: inline ASCII branches for char conversions
(`63324770`, completing the StringBuilder line: `append-literals`
**5.85 → 0.97**, ahead of Delphi), one-scan StringReplace (`a21817cb`,
`1.77 → 1.40`), TStringStream without double conversion (`8bef8a58`,
`1.39 → 1.03` + loss of characters outside the ANSI page fixed), and ASCII
string case conversion in one loop (`d3d24226`, `uppercase/lowercase-4k → 0.75`).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-029 | 355 | 0.723 | 182 | 113 | 60 |
| **After PERF-030** | **360** | **0.727** | **183** | **114** | **63** |

Cross-snapshot spikes (`open-array-const`, `fillchar-4k`, `alloc-free-1m`,
`realloc-shrink`, `object-create-virtual-free`) are in the placement/drift
class, all in the run's drift list or the permanent list; across shared cases,
geomean 0.723 → 0.725 is noise. Matrix 144/144 (48 sources), gate 58.

## RTL-audit result, waves 1–2 (PERF-029)

The complete Win64 O3 medium snapshot `results/pulse/wave18-full` now has 355
cases: 347 prior cases + 8 audit sentinels (`3345826a`). Wave fixes:
`bf245a8e` (IntToHex through a stack buffer and Char table), `8b66c8c4`
(date fields without heap strings), `0c870761` (ASCII string conversions
without WinAPI), and `20786015` (ASCII UpCase/LowerCase without the manager).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-028 | 347 | 0.717 | 175 | 115 | 57 |
| **After PERF-029** | **355** | **0.723** | **182** | **113** | **60** |

Audit cases after the fixes: `datetime-format` **2.99 → 0.565** (Moon is almost
twice ahead), `inttohex-int64` **7.04 → 1.85**, `datetime-encode-decode` 0.52,
and `datetime-ms-arith` 0.19; remaining PERF-029 tails are string-replace 1.77
and trystrtoint 1.72. Across the shared 347 cases, geomean shift 0.717 → 0.719
is noise (drift-marked pairs); call-interface/scan-strided “regressions” are the
proven placement/drift class. Matrix 144/144 (48 sources), gate 58.

## Builder cleanup and wrong-code fix result (PERF-028)

The complete Win64 O3 medium snapshot `results/pulse/wave15-full` follows a
live copy of builder capacity (`9a3c3b23`) and the correctness fix for
untyped-const arguments (`2f7ef0cc`, `formal_const_address_semantic` pin,
matrix 144/144).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-027 | 347 | 0.723 | 178 | 113 | 56 |
| **After PERF-028** | **347** | **0.717** | **175** | **115** | **57** |

Targets (A/B `wave15c-ab`, control `0.995`): `growth` `1.65 → 1.41` (baseline
`0.856`); builder cases lose nothing from honest address marking
(`append-literals` `1.146`, `insertrange-2048` baseline `0.582`). The run itself
marked cross-snapshot spikes (`fragmented-mixed`, `stream-triad`) as drift;
`alloc-free-1m` returned to `1.01`.

## TStringBuilder and char-conversion result (PERF-027)

The complete Win64 O3 medium snapshot `results/pulse/wave13-full` follows three
fixes for one gap (`bb26d287`, `784bfa07`, `dc198d2a`): direct field-based
Append paths, folding char constants after inlining, and ASCII character
conversion without widestringmanager.

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-026 | 347 | 0.718 | 179 | 113 | 55 |
| **After PERF-027** | **347** | **0.723** | **178** | **113** | **56** |

Targets (A/B `results/focused/wave13b-ab`, control `0.992`):
`append-literals` **5.85 → 1.142** (baseline `0.191` — 5.2 times),
`append-integers` `0.851` — Moon ahead, `append-prepared-floats` `2.6 → 1.366`
(baseline `0.514`); additionally, `json/generate-64` `0.85 → 0.49`. The +0.005
geomean shift is cross-snapshot noise: disassembly checked the
`call-virtual`/`open-array-const` spikes (code is bit-for-bit baseline-identical
at the same addresses — process BTB context), while the run itself marked
`alloc-free-1m` as drift. Matrix 141/141, gate 58. Builder tails are
PULSE-TODO-009 (growth 1.65, prepared-floats 1.37).

## String bulk-incref result (PERF-026)

The complete Win64 O3 medium snapshot `results/pulse/wave11-full` follows bulk
raising the refcount of string rows (`914449dc`): one call per array in
`fpc_addref_array` + a block-copy `TList<T>.InsertRange` path.

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-025 | 347 | 0.723 | 180 | 111 | 56 |
| **After PERF-026** | **347** | **0.718** | **179** | **113** | **55** |

Targets (A/B `results/focused/wave11-ab`, control `0.986`):
`list-string-insertrange-2048` `1.174 → 0.884` (Moon ahead of Delphi, baseline
`0.587`), `addrange-4096` `0.577`, and `clear-4096` `0.312`. Additional
complete-snapshot wins through COW copies of string dynamic arrays:
`queue-string-roundtrip` `0.99 → 0.52`, `list-string-toarray` `0.72 → 0.54`,
and `unicode-pos-4k` `0.80 → 0.66`. Cross-snapshot spikes (`fillchar-4k`
`1.33`, `fragmented-mixed` `1.07`, `object-create-virtual-free` `1.13`) are
all in the permanent drift class; the last is marked drift by the run itself
(`1.476x`). Matrix 141/141 (47 sources), gate 58.

## Bump-with-live-counter result (PERF-025)

The complete Win64 O3 medium snapshot `results/pulse/wave9-full` follows
expansion of the pointer-bump gate (`66d6bbcc`): bump of global arrays is
allowed with a live counter when the loop is guaranteed to reach its end. The
case-strategy change was reverted by A/B (a table under an unpredictable selector
is a 2.73x regression; the chain is optimal).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-023 | 347 | 0.728 | 172 | 120 | 55 |
| **After PERF-025** | **347** | **0.723** | **180** | **111** | **56** |

Targets (A/B `results/focused/wave9-ab`, control `0.997`): `case-dense`
`1.53 → 1.27` (baseline `0.842`), `enum-set-membership` `→ 0.952` — Moon ahead
of Delphi (baseline `0.936`), `case-sparse` baseline `0.988`, and
`branch-predictable` baseline `1.001` (bump code mirrors Delphi; the remainder
is the “frontend/layout” cluster, PERF-025). Cross-snapshot spikes
`call-interface` `1.159` and `mm/alloc-free-1m` `1.267` are the proven placement
class (PULSE-DECISION-007) and a drift-marked pair of this run. Matrix 141/141
(47 sources), gate 58.

## String bulk-finalization result (PERF-023)

The complete Win64 O3 medium snapshot
`results/pulse/full-medium-wave6-20260818` follows bulk finalizers for string
arrays (one call per array instead of a call per element).

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After PERF-022 | 347 | 0.729 | 171 | 116 | 60 |
| **After PERF-023** | **347** | **0.728** | **172** | **120** | **55** |

Targets (A/B `results/focused/wave6-ab`, control `0.997`):
`list-string-insertrange-2048` `1.349 → 1.174`,
`list-string-addrange-4096` → `0.763`,
`list-string-clear-4096` → `0.450`. Cross-snapshot suspicions
(`scan-small-16`, `object-create-virtual-free`) were dismissed by honest A/B —
Moon/baseline `1.000`/`0.984`. Matrix 138/138, gate 58.

## Variant/InsertRange layer result (PERF-022)

The complete Win64 O3 medium snapshot
`results/pulse/full-medium-wave5-20260818` follows two fixes: direct
Variant-to-integer conversions (conversion-phase parity with Delphi) and
notification-free managed InsertRange.

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After cleanup | 347 | 0.734 | 175 | 112 | 60 |
| **After PERF-022** | **347** | **0.729** | **171** | **116** | **60** |

Targets (A/B `results/focused/wave5-ab`, control `0.999`):
`managed/variant-numeric` `1.46 → 1.174`,
`list-string-insertrange-2048` `1.62 → 1.349`,
`list-string-add-reserved` → `1.063`; additionally,
`list-string-clear-4096` `0.69 → 0.53`. `dispatch/list-index` swung again
`1.00 → 1.33` — the documented placement pendulum (PULSE-DECISION-007); code
is unchanged bit-for-bit. Matrix 138/138 (46 sources), gate 58.

## Third-wave cleanup result (PERF-021)

The complete Win64 O3 medium snapshot
`results/pulse/full-medium-wave4-20260818` follows four cleanup fixes: the
exit-free `TList.Delete` fast path, inline `TObject.ClassInfo`, GPR copies of
small blocks (STLF), and the unchecked fast path for 32-bit Variant arithmetic.

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After the third wave | 347 | 0.738 | 172 | 115 | 60 |
| **After cleanup** | **347** | **0.734** | **175** | **112** | **60** |

Target cases (A/B `results/focused/wave4-ab`, control `0.997`):

| Case | Before | After |
|---|---:|---:|
| `abi/record32-value` | 1.44x | **0.363x** — 2.8 times faster than Delphi |
| `rtl/generic-list-delete-front-128` | 1.22x | **1.037x** |
| `rtl/generic-list-add-reserved` | 1.15x | **1.034x** |
| `rtl/generic-list-reserved-512` | 1.07x | **0.996x** |
| `managed/variant-numeric` | 1.46x | **1.32x** (the remainder is Variant copies) |

Additionally, `rtl/generic-list-delete-tail-512` `1.055 → 0.636`.
`abi/open-array-const` `1.19` is proven placement (code is bit-for-bit
baseline-identical). Matrix 138/138 (46 sources), gate 58.

## Third-wave result: generic list, record/ABI, managed (PERF-017..020)

The complete Win64 O3 medium snapshot
`results/pulse/full-medium-wave3-20260818` follows four fixes: pointer bump for
elements wider than the hardware scale, `TList.Add`/`DoRemove` fast paths,
inline x86-64 code generation for atomic intrinsics, and flattened managed
assignments (`_AddRef`/`_Release`, `fpc_dynarray_assign`). All oracles MATCH;
there are no regressions >15% between snapshots.

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| After the second wave | 347 | 0.747 | 167 | 106 | 74 |
| **After the third wave** | **347** | **0.738** | **172** | **115** | **60** |

Target cases (Before → After, A/B `results/focused/wave3-ab`, control
`0.997`):

| Case | Before | After |
|---|---:|---:|
| `codegen/record-aligned` | 1.73x | **0.998x** |
| `managed/interface-copy-call` | 1.72x | **0.942x** |
| `rtl/generic-list-reserved-512` | 1.64x | **1.072x** |
| `rtl/generic-list-add-reserved` | 1.59x | **1.147x** |
| `managed/dynamic-array-assign` | 1.43x | **1.021x** |
| `rtl/generic-list-growth-512` | 1.42x | **1.101x** |
| `rtl/generic-list-delete-front-128` | 1.36x | **1.223x** |

Additionally: `algorithms/generic-list-512` `1.42 → 1.08`,
`local-pressure/used-buffers-100` `1.23 → 0.85`; atomics became cheaper by two
call levels throughout the system. Queue tails are in PULSE-STATUS-007.

## Second-wave result: table tail + stack (PERF-011..016)

The complete Win64 O3 medium snapshot `results/pulse/full-medium-gapblock3-20260817`
follows Delphi stack parity (PERF-011), six tail fixes (PERF-012..015), and
verification that closed two regressions introduced by the block (PERF-016).
All oracles MATCH; run drift pairs (`fillchar-4k`, `histogram-random`,
`alloc-free-1m`) and proven placement cases (`dispatch/list-index`,
`codegen/call-interface` — code bit-for-bit baseline-identical, dynamic parity
in an isolated probe) are excluded from conclusions.

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| Before RTL work (old baseline) | 248 | 0.967 | 79 | 83 | 86 |
| After the first wave (PERF-005..010) | 347 | 0.770 | 168 | 101 | 74 |
| **After the second wave** | **347** | **0.747** | **167** | **106** | **74** |

Target cases of the block (Before → After, interleaved medium A/B, control
`0.992`):

| Case | Before | After |
|---|---:|---:|
| `codegen/for-byte-0-255` | 2.82x | **1.008x** |
| `layout/static-array` | 2.00x | **1.083x** |
| `layout/indexed-walk` | 2.00x | **1.079x** |
| `loops/manual-copy-8192` | 1.96x | **0.984x** |
| `abi/record16-value` | 1.94x | **0.398x** |
| `rtl-collections/list-integer-delete-insert-range-4096` | 1.82x | **0.825x** |
| `threads/thread-start-join-4` (stack, PERF-011) | 1.17x | **1.035x** |
| `threads/producer-consumer` (stack, PERF-011) | 1.14x | **0.993x** |

Additional root wins: `abi/record24-value` `0.41→0.22`,
`loops/vector-add-8192` `1.00→0.72`,
`rtl-collections/list-integer-addrange-4096` `1.13→0.69`,
`insertrange-list-4096` `1.70→1.12`. Groups: threads `0.108`, layout `0.715`,
RTL `0.756`, ABI `0.781`. A new “Tail block” column was added to
`PULSE_HISTORY.html`.

## Perf-gap block result (branch `perf/remaining-gaps-20260817`, PERF-005..010)

The complete Win64 O3 medium snapshot
`results/pulse/full-medium-after-gaps-20260817` follows six block fixes (Grisu
digit core in `FloatToDecimal`, elimination of a managed funcret temporary in
the compiler, per-thread console-codepage snapshot, heap-free format engine,
widechar-in-set comparison chain, exponent parser). All oracles MATCH; six run
drift pairs (`json/scan-large-4096`, `mm/alloc-free-1m`, `mm/alloc-free-2m`,
`workloads/stream-add`, and their control sides) are excluded from conclusions,
as in earlier snapshots.

| Snapshot | Cases | Moon/Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|---:|
| Before RTL work (old baseline) | 248 | 0.967 | 79 | 83 | 86 |
| Previous HEAD (before the block) | 339 | 0.845 | 155 | 95 | 89 |
| **After the block** | **343** | **0.768** | **168** | **101** | **74** |

The compiler became another `1.10x` faster than its state before the block and
`1.26x` faster than its original state across the entire matrix, not per case.
Groups: threads `0.153`, layout `0.765`, RTL `0.766`, numeric `0.771`,
RTL collections `0.774`, JSON `0.966` (within it, `json/generate-64` is now
`0.95x` — Moon is ahead of Delphi). A “Perf-gaps” column was added to
`PULSE_HISTORY.html`.

Top of the remaining tail (next queue): `codegen/for-byte-0-255`
`2.82x`, `layout/indexed-walk` `2.00x`, `layout/static-array` `2.00x`,
`loops/manual-copy-8192` `1.96x`, `abi/record16-value` `1.94x`,
`rtl-collections/list-integer-delete-insert-range-4096` `1.82x`.

## `threads/padded-counters-4`: from a mixed metric to a compiler root

| Stage | Moon / Delphi | What was actually measured |
|---|---:|---|
| Original baseline | 67.089× | Four create/start/join/free thread cycles inside each sample, plus the loop itself. |
| Before this investigation | 76.655× | The same mixed metric; it is not the cost of a padded counter. |
| Persistent workers, before compiler repair | 1.185× | Pure signal/work/wait; a diagnostic measurement that was not yet pinned. |
| Persistent pinned workers, after compiler repair | **0.500380×** | Identical CPU placement, 8 process runs per compiler, 37 samples; Moon is almost exactly twice as fast. |

Final balanced half-sample modes: Delphi `0.854804145` ticks/op, Moon
`0.427726649` ticks/op. The cause is neither MM nor thread API: Moon now hoists
the address of `PaddedCounters[FIndex]` before the loop. Countdown was already
register-resident before the fix; Delphi 12.2 recomputes base/index/stride on
every iteration in the same form. Focused semantic and assembly gates fix the
causal boundary of this repair.

The same persistent/pinned methodology removed the false `5.08–5.25×` for
independent CPU work: 1/2/4/8 workers now yield `1.000×`, `1.017×`, `0.998×`,
and `1.037×` respectively. Compiler code generation and scaling of this pure
form are therefore already at parity. The true heavy thread-group tails remain
the separately measured lifecycle `thread-start-join-4 = 2.742×` and queue
`producer-consumer = 2.448×`; persistent workers do not mask them.

## `dispatch/try-except-no-raise`: eliminated dead exception region

| Stage | Delphi ticks/op | Moon ticks/op | Moon / Delphi |
|---|---:|---:|---:|
| Before compiler repair | 5.038801 | 16.628339 | 3.300060× |
| After compiler repair | 5.038801 | 5.038717 | **0.999983×** |

After AUTOINLINE, only unchecked ordinal arithmetic remained in the benchmark,
but the compiler did not reconsider its earlier `try/except`, retained
`pi_uses_exceptions`, and spilled the hidden inline parameter to the stack. One
conservative proof now removes only a genuinely non-throwing scalar tree; calls,
managed values, indirect/reference-parameter loads, delayed temporary
initialization, division, range, and overflow checks retain the exception region.
The focused runtime test and Win64 O3 assembly gate check both sides of this
boundary.

## `json/generate-64`: first accepted fix — Str exponent in FloatToDecimal

The `2.18x` gap was decomposed by step: six `FormatFloat` calls on quote dominate
(~87% gap); within them, the first proven bottleneck is `Val(Copy(...))` while
parsing the `Str` exponent in `FloatToDecimal`. The fix parses the sign and
digits in place using a separate index; candidate validation found and removed
an `N`-shift defect (uncleared `Digits` tail, false round-up at `Precision = 17`)
caught by a new poisoned semantic test.

Single-session A/B against the clean baseline toolchain (8 processes per system,
`296/0` kept/rejected, control `str-extended = 1.0034`):

| Case | Candidate/Baseline | Moon/Delphi after |
|---|---:|---:|
| `json-decompose/float-to-decimal` | **0.9275** | 2.642 |
| `json-decompose/format-core` | 0.9760 | 2.139 |
| `json/generate-64` | 0.9837 | 2.189 |

Commit `069bafee`; the table above retains the accepted A/B and absolute tail.
The primary tail owner (`format-core ≈ 2.14x`) is the cost of
`FloatToTextFmt`/`FormatFloat` over a ready `TFloatRec`; the task remains open.

## `rtl-collections/list-string-read`: accepted compiler fix for funcret temp

The `2.72x` gap was a dead post-inline optimization,
`optimize_funcret_assignment`: it never triggered for managed results of inline
getters (nested non-strippable blocks, lowered helper calls instead of `assignn`,
leading range check). After the compiler fix (commit `714061ff`), the managed
temporary and its refcount traffic disappear when the result is consumed in
place; required copies remain.

Single-session A/B against the clean baseline toolchain: target case
`9.334 → 2.587` cycles/op (**0.2771x**), `Moon/Delphi 2.72x → 0.755x` —
Moon is now faster than Delphi; enumerate `0.9600x`, additionally `generate-64`
`0.9882x`, control `0.9917x`. Gates: repair gate rows=58, RTL matrix
114/114, self-host cycle.

## `threads/thread-start-join-4` and `producer-consumer`: console CP snapshot

The phase ladder justified the benchmark methodology (double WaitFor and barrier
are percentages, repeated WaitFor is 1.03 parity) and led to process level: raw
`CreateThread` without RTL bootstrap already carried the whole gap, and zeroing
the PE TLS Directory removed it. Instrumented `InitThread` found 215K of 220K
extra cycles per thread in `SysInitStdio`: five console-LPC code-page requests
(`GetConsoleCP`/`GetConsoleOutputCP`) for every new thread. The fix is a
process-wide snapshot of two console CPs (commit `6f53ec91`).

Single-session A/B against the clean baseline toolchain (control
`str-extended = 0.9970`):

| Case | Cand/Base | Moon/Delphi after |
|---|---:|---:|
| `threads/thread-start-join-4` | **0.4387** | 1.166 (was 2.61) |
| `threads/producer-consumer` | **0.4931** | 1.142 (was 2.41) |

One fix closed both thread gaps in the initial queue; case methodology is
unchanged. The `~1.15x` remainder (stdio tail, exit path) is the next separate
layer.

## Current complete Win64 medium snapshot after RTL fixes

Exact HEAD: `3e2e5642c8076456d9b7ac83e40147df6b5465e0`. The comparison ran on the
same Win64 machine with the same two systems: Delphi 12.2 + standard FastMM4
and MoonCompiler + pinned fpcx64mm. The semantic oracle matched in every case.

For an honest “before/after” comparison, 248 identical cases were taken from old
`pulse-win64-medium-final-2` and current medium runs. The overall ratio excludes
eight cases in which the current reporter found impermissible process
drift: `codegen/fillchar-4k`, `codegen/scan-llc`, `mm/alloc-free-1m`,
`mm/alloc-free-2m`, `mm/fragmented-mixed`, `workloads/stream-add`,
`workloads/stream-triad`, `rtl/object-create-virtual-free`. Their values are
retained, but their ratio cannot be published as a stable result.

`< 1.0` means Moon is faster than Delphi. Report classes: `< 0.95` faster,
`0.95..1.05` parity, `> 1.05` slower.

| Snapshot of identical cases | Moon / Delphi geomean | Faster | Parity | Slower |
|---|---:|---:|---:|---:|
| Before RTL work | 0.967 | 79 | 83 | 86 |
| Current HEAD | 0.877 | 95 | 82 | 71 |

The current-to-old geomean ratio is `0.907`: across the shared unchanged set,
Moon became approximately `1.10x` faster than its own initial state. This does
not mean that every individual loss was eliminated.

| Group | Cases | Before | Now |
|---|---:|---:|---:|
| ABI | 24 | 0.885 | 0.875 |
| algorithms | 9 | 0.977 | 0.924 |
| calibration | 4 | 1.096 | 1.000 |
| codegen | 41 | 0.992 | 1.002 |
| dispatch | 15 | 1.548 | 0.986 |
| teaching JSON/byte scan | 9 | 0.913 | 1.063 |
| kernels | 10 | 0.978 | 0.922 |
| layout | 20 | 0.739 | 0.761 |
| local pressure | 9 | 0.278 | 0.254 |
| loops | 20 | 1.002 | 1.000 |
| managed | 12 | 1.224 | 0.973 |
| MM | 12 | 1.302 | 1.295 |
| numeric | 21 | 0.784 | 0.771 |
| RTL, old identical cases | 12 | 1.765 | 0.839 |
| threads | 17 | 0.970 | 0.721 |
| workloads | 13 | 1.007 | 0.995 |

The `threads` geomean cannot be read as a claim that the whole multithreaded
layer is fixed: several allocator cases yield a very large win, while
`independent-cpu`, `shared-read`, `false-sharing`, and some scaling remain
substantially worse than Delphi. `padded-counters` is separated into its own
compiler-root series above.

Current Pulse also includes 43 new RTL cases and a separate 48-case container
matrix absent from the initial baseline. They are therefore not mixed into the
“before/after” table. The standalone container-matrix result is `0.789`; the
whole current stable set of 339 cases, including the new ones, has
geomean `0.845`, 155 faster / 95 parity / 89 slower.

Exact artifacts:

- `results/pulse/pulse-current-nonrtl-medium-20260816`;
- `results/pulse/pulse-current-rtl-medium-20260816`;
- `results/pulse/rtl-collections-final-medium-20260816`.

The `json` group remains not a benchmark of mORMot JSON API: it consists of
`byte-scan-*`, an in-house teaching parser, and a generator. Actual product
mORMot JSON is now measured by a separate `mormot-json` program; exact Win64
medium on 2026-08-24 produced 18/18 MATCH and Moon/Delphi geomean `0.957`.
Full report:
[`evidence/todo-status-20260824/REPORT.md`](evidence/todo-status-20260824/REPORT.md).

## After the current RTL pass

The latest exact container snapshot is
`results/pulse/rtl-collections-final-medium-20260816/summary.json`: 48 cases,
Moon/Delphi geomean `0.789`, 32 faster than Delphi, 6 at parity, and 10 slower.
The semantic oracle matched in all 48 cases. The prior general RTL snapshot
`results/pulse/rtl-exact-20260816/summary.json` contains 56 cases and precedes
the latest container pass, so it is not presented as the result of current
HEAD.

| Case | Moon / Delphi before | Latest snapshot |
|---|---:|---:|
| list enumerator | 147.82x | 0.666x |
| `IntToStr(Int64)` | 7.87x | 1.061x |
| UTF-8 encode/decode 4K | 4.35x | 0.709x |
| Unicode concat | 3.64x | 0.846x |
| `StrToInt64` | 2.86x | 0.961x |
| indexed generic list read | 2.65x | 1.078x |
| Unicode `Pos` | 1.64x | 0.725x |
| `FloatToStr(Double)` | 1.63x | 0.896x |
| mixed `Format` | 1.50x | 0.729x |
| unmanaged dynamic-array `Copy` | no separate case existed | 0.920x |

### Containers on current HEAD

`< 1.0` means Moon is faster than Delphi 12.2 on the same Win64 machine.

| Case | Moon / Delphi | Physical meaning |
|---|---:|---|
| `TList<Integer>.Pack` | 0.288x | one pass instead of bitmap and repeated deletion |
| dictionary pair enumeration | 0.295x | direct bucket traversal |
| `TList<Integer>.IndexOf` | 0.510x | native ordinal scan |
| queue 128-byte record steady state | 0.544x | ring path without unnecessary copying |
| `TList<Integer>.Clear` | 0.651x | exact plain list without empty callbacks |
| `TList<UnicodeString>.IndexOf` | 0.729x | pointer/length/word compare fast path |
| `TObjectList<T>.Clear` with ownership | 0.784x | owning path retained and faster than Delphi |
| `TList<UnicodeString>` indexed read | 2.722x | compiler creates an extra managed-result copy |
| integer `InsertRange(TList)` | 1.711x | `Move`, allocation, and caller costs remain |
| integer delete/insert range | 1.662x | `Move` dominates |
| string `InsertRange` | 1.478x | managed assignment; `CopyArray` was worse |
| integer `Exchange` | 1.161x | body is already minimal; remainder is virtual call/codegen |

Thus, container geomean is already approximately `1.27x` faster than Delphi,
but the table does not hide individual losses behind the overall mean. Their
next provable layer is compiler lowering, allocation, and managed assignment.
At this stage, `System.Move` had already been compared with the mORMot candidate
and deliberately left unchanged; container cases were not a reason to reopen it.
Later, separate 297-case PERF-042 evidence led to production baseline `75190e41`.

This is a retained performance snapshot, not a replacement for semantic
qualification. After it, the simplification pass removed the unproven
notification cache, load factor 0.5, and that experimental AVX `Move`; these
candidates are not in final commits. Later `75190e41` is a different
implementation with an independent complete matrix.

## Original queue before RTL repairs

Source: `results/pulse/pulse-win64-medium-final-2/summary.json`.
This is the complete Win64 O3 measurement of MoonCompiler + bundled MM against
Delphi 12.2 + default MM on one machine before the current RTL pass. The table
below is the original problem queue, not the performance of the new HEAD. It
lists only cases where Moon was slower; wins are excluded.

## Severe regressions: more than twice as slow

| Case | Moon / Delphi |
|---|---:|
| `dispatch/list-enumerator` | 147.82x |
| `threads/padded-counters-4` | 67.09x |
| `rtl/inttostr-int64` | 7.87x |
| `threads/independent-cpu-8` | 5.25x |
| `threads/independent-cpu-4` | 5.08x |
| `threads/shared-read-4` | 4.47x |
| `rtl/utf8-encode-decode-4k` | 4.35x |
| `rtl/unicode-concat-32` | 3.64x |
| `threads/false-sharing-4` | 3.23x |
| `dispatch/try-except-no-raise` | 3.15x |
| `threads/thread-start-join-4` | 3.12x |
| `mm/realloc-grow` | 3.04x |
| `rtl/strtoint-int64` | 2.86x |
| `codegen/for-byte-0-255` | 2.80x |
| `threads/parallel-alloc-free-96-4` | 2.75x |
| `dispatch/list-index` | 2.65x |
| `threads/producer-consumer` | 2.55x |
| `algorithms/generic-list-512` | 2.24x |
| `rtl/generic-list-512` | 2.15x |

## Substantially slower: 1.25x–2.00x

| Case | Moon / Delphi |
|---|---:|
| `layout/indexed-walk` | 2.00x |
| `loops/manual-copy-8192` | 1.97x |
| `abi/record16-value` | 1.95x |
| `kernels/lu-decomposition-32` | 1.87x |
| `codegen/record-aligned` | 1.74x |
| `managed/interface-copy-call` | 1.68x |
| `abi/dynamic-array-value` | 1.67x |
| `rtl/unicode-pos-4k` | 1.64x |
| `rtl/floattostr-double` | 1.63x |
| `local-pressure/used-strings-100` | 1.62x |
| `codegen/case-dense` | 1.60x |
| `local-pressure/used-mixed-300` | 1.57x |
| `mm/alloc-free-17409` | 1.56x |
| `mm/alloc-free-17408` | 1.55x |
| `mm/alloc-free-16k` | 1.54x |
| `local-pressure/used-buffers-100` | 1.54x |
| `dispatch/raise-catch` | 1.53x |
| `layout/move-1024` | 1.52x |
| `managed/unicode-assign` | 1.50x |
| `rtl/format-mixed` | 1.50x |
| `managed/unicode-return-ppu` | 1.49x |
| `codegen/try-finally-normal` | 1.49x |
| `codegen/case-sparse` | 1.49x |
| `managed/managed-record-return` | 1.49x |
| `threads/independent-cpu-2` | 1.47x |
| `managed/dynamic-array-assign` | 1.47x |
| `managed/managed-exception-cleanup` | 1.47x |
| `abi/record32-value` | 1.45x |
| `mm/alloc-free-256` | 1.44x |
| `mm/alloc-free-1024` | 1.43x |
| `loops/loop-try-finally` | 1.41x |
| `dispatch/managed-object-create-free` | 1.38x |
| `managed/variant-numeric` | 1.37x |
| `rtl/stringlist-sort-128` | 1.36x |
| `codegen/fillchar-4k` | 1.34x |
| `threads/parallel-alloc-free-1` | 1.28x |
| `codegen/recursion-tree-8` | 1.27x |
| `calibration/asm-memory-read-64m` | 1.25x |

## Moderately slower: 1.10x–1.25x

`managed/rawbytestring-assign` 1.24x; `abi/record32-var` 1.21x;
`mm/alloc-free-64` 1.21x; `managed/managed-early-exit` 1.20x;
`rtl/strtofloat-double` 1.20x; `workloads/fft-1024` 1.20x;
`workloads/floyd-warshall-64` 1.19x; `calibration/asm-dependent-add` 1.17x;
`abi/open-array-const` 1.17x; `workloads/jacobi-2d-128x4` 1.17x;
`mm/alloc-free-16` 1.17x; `codegen/call-interface` 1.17x;
`codegen/call-virtual` 1.17x; `abi/dynamic-array-const` 1.16x;
`algorithms/open-hash-4096` 1.14x; `layout/move-256` 1.13x;
`algorithms/sha256-4k` 1.12x; `workloads/stream-scale` 1.10x.

## Slightly slower: 1.03x–1.10x

`numeric/int32-add-mul` 1.09x; `layout/aos-all-fields` 1.09x;
`workloads/binary-trees-depth-10` 1.09x; `mm/ring-same-class-96` 1.09x;
`layout/pointer-walk` 1.08x; `codegen/move-4k` 1.08x;
`codegen/matrix-double-16` 1.07x; `kernels/neural-dense-32x32` 1.07x;
`json/scan-large-4096` 1.07x; `json/scan-medium-256` 1.06x;
`workloads/linked-list-insert-sort-512` 1.06x; `rtl/dictionary-512` 1.06x;
`dispatch/virtual-polymorphic` 1.06x; `json/scan-small-16` 1.05x;
`codegen/int8-int16-promotion` 1.04x; `workloads/stream-copy` 1.03x;
`abi/no-args` 1.03x; `mm/alloc-free-2m` 1.03x.

Values below 1.03x are retained in machine-readable `summary.json`, but are not
considered a repair signal without a repeatable stable A/B: at that scale they
cannot be distinguished from layout, CPU frequency, and statistical noise.

## MM checkpoint: 44 classes

Source: `results/pulse/mm-44-padding-medium-20260816/summary.json`.

After restoring the original 44 small classes up to payload 2600 while retaining
the 4096-byte arena line, `mm/realloc-grow` changed from the original `3.04x` to
`1.046896x` Moon/Delphi. Absolute modes: Delphi `57.986`, Moon `60.706`
cycles/op; the oracle matched, with cycle samples kept/rejected `7/0` for both systems.

This stage does not declare the entire MM group stable: `alloc-free-256` showed
process drift of `1.268x` and requires a separate repeat if it becomes a repair
target. The conclusion about `realloc-grow` does not rely on it.

## System.Move: complete x86-64 profile

Exact Win64 O3 medium after `75190e41`: 297/297 semantic oracle MATCH,
Moon/Delphi geomean `0.936`; 124 cases are faster, 144 are at parity, and 29
are slower. This is a separate matrix of sizes, alignments, overlap,
same-pointer, and streaming copies, not the previous two `Move(256/1024)` rows.

Key ordinary hot-copy Moon/Delphi ratios: 33/48/64 bytes — `0.995/1.000/1.000`,
65 — `0.723`, 512 — approximately at parity, 1024 — `0.85`, 4096 — `0.79`.
Copying 16 MiB at the first transition to non-temporal stores is `0.653`;
32/64 MiB remain at parity or faster. The most visible deliberate residual is
the empty `Source = Dest` after 96 bytes (`~1.143`, difference below one TSC tick):
a general early check would make every real Move slower and was therefore rejected.

The paired old/new A/B showed why the old 256 KiB NT threshold was not restored:
at 1 MiB, the new hot/reuse path is `0.425x` of the old one, while one-pass
streaming is `1.522x`. These are incompatible requirements for the same `Move`
arguments; the current cache-aware policy selects reuse up to half of the
largest cache and NT after that.

Full figures and process-drift annotations:
`qualification/performance/evidence/system-move-20260824/`.
On Linux x86-64, the same HEAD built the full toolchain and passed focused 3/3,
full RTL 237/237, and medium 297/297 oracle MATCH on an Intel Xeon W-2295.
Linux medium compares two link layouts of the same RTL, so it does not replace
the Win64 verdict against Delphi with a separate performance conclusion.
