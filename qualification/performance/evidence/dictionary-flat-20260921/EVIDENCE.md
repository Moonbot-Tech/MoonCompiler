# TDictionary flat path and notification flag — evidence

Date: 2026-09-21. Change: `packages/rtl-generics/src/inc/generics.dictionaries*.inc`
(one commit with `RTL-test/semantic/dictionary_flat_semantic.dpr`). Baseline:
`47bae96c0` built in a clean worktree; candidate: the same tree with the change.
Both are complete toolchains (`build.ps1 compiler`), the benchmarks are built
against the installed `Generics.Collections` of each — no source-tree overrides.

## What changed

1. **Notification flag.** `TCustomDictionary` notified `KeyNotify`/`ValueNotify`
   on every add, update, remove and clear whether anyone listened or not: two
   virtual calls per operation, and `SetValue` (the update path) copied the old
   value only to hand it to a listener that was not there. `FNotify` is now set
   when a handler is assigned (property setters) or when the instance's class
   overrides `KeyNotify`/`ValueNotify` (checked once in the constructor against
   this class's slots — `TObjectDictionary` and user descendants keep every
   notification without any handler). With the flag clear, `PairNotify`,
   `SetValue`, `DoRemove` and `Clear` skip the calls; `Clear` no longer needs the
   exact-class test it had.
2. **Flat lookup.** `TOpenAddressingLinearLP` (the class behind `TDictionary`)
   looks a key up on one straight path when the comparer is the default one
   (pointer identity with the per-type static instance) and the key kind is
   one of `tkInteger, tkInt64, tkQWord, tkEnumeration, tkBool, tkChar, tkWChar,
   tkClass, tkClassRef, tkPointer, tkUString, tkAString` (`GetTypeKind(TKey)`
   folds at specialization): hash, probe loop, compare, inlined into
   `TryGetValue`, `ContainsKey`, `AddOrSetValue`, `TryAdd`, `Remove` and
   `Items[]` — no interface calls into the comparer, no virtual
   `FindBucketIndex` hop. Custom comparers, `TIStringComparer`, records and
   floats keep the comparer path unchanged; `FindBucketIndex` and
   `FindBucketIndexForHash` are overridden so every base-class method (rehash,
   `Add`, `ExtractPair`, base-typed references) shares the same table and hash.
3. **Hash of ordinals and pointers.** Strings keep the factory hash (CRC32C) of
   their content. Ordinals and pointers are hashed with the MurmurHash3
   finalizer of the value (fmix32 for 1/2/4-byte keys, fmix64 for 8-byte) — see
   "Why this hash". The enumeration order of a dictionary with such keys
   therefore differs from the comparer path; the container never promised one.

## Semantics: differential oracle and the RTL test

`dict_oracle.dpr` runs one deterministic script (20 000–30 000 random
operations: `AddOrSetValue`, `TryAdd`, `Remove`, `TryGetValue`, `ContainsKey`,
`Items[]` read/write with exceptions, `ExtractPair`, `Add` with duplicates,
`TrimExcess`, `Clear`, enumeration, `Keys`/`Values`, `ToArray`) over 16 key/value
kinds, handlers assigned and removed mid-run, a descendant overriding
`KeyNotify`/`ValueNotify`, and `TObjectDictionary` ownership, and prints one
digest per section.

- `results/oracle-baseline.txt` = `results/oracle-candidate.txt` byte for byte
  (order-free folding of the enumerations: `-dORACLE_ORDERFREE`), on Win64 and
  on Linux (`results/linux-xeon-ab.txt`, "LINUX ORACLE IDENTICAL").
- With the enumeration order in the digest (`*-ordered.txt`) exactly the eight
  ordinal/pointer sections differ (`int`, `i64`, `cardinal`, `word`, `byte`,
  `enum`, `pointer`, `int-cap4096`); strings, records, doubles, the
  case-insensitive comparer, notifications and ownership are identical.

`RTL-test/semantic/dictionary_flat_semantic.dpr` is the permanent contract
(flat selection per kind, a model-checked operation mix per kind, colliding
key pairs, base-class references, exact notification counts, overrides,
ownership, hash spread, and since round 2 object-key equality and the
construction contracts); `negative_controls.py` here proves that each of its
sections fails against a sabotaged dictionary (old hash, flag always on,
override detection lost, flat detection lost, equality skipped, `SetValue`
assignment lost, object identity, the reservation lost or counted in slots,
`ExtractPair` losing the key, the copy constructor raising, a nil comparer
kept) — all twelve caught.

## Win64, Ryzen 5800X (Zen 3)

`dict_bench.dpr`, product options (`-Mdelphi -O3`, bundled MM), four
placement families per side (`-dPULSE_FILLER_k`), five fresh processes per
executable, median of 11 samples each; the number is the median over
families, in brackets the min..max over families. Thread cycles per operation,
**including the benchmark loop's own `idiv`** (`Index mod FillCount`, about
10 cycles). Delphi 12.2 (`dcc64 -$O+ --inline:auto`, one placement) is the
same source. `results/matrix-win64.txt`.

| scenario | baseline | candidate | Δ | Delphi 12.2 |
|---|---:|---:|---:|---:|
| update int c256 f25 | 44.6 | 32.9 | −26% | 99.7 |
| update int c4096 f50 | 44.7 | 34.1 | −24% | 100.7 |
| lookup int c256 f25 | 33.7 | 14.9 | −56% | 38.2 |
| lookup int c4096 f50 | 33.7 | 16.5 | −51% | 37.6 |
| miss int c4096 f50 | 37.6 | 16.3 | −57% | 38.7 |
| insert int c1M f25 (DRAM) | 122 | 102 | −17% | 160 |
| mixed int c1M f25 (DRAM) | 84.5 | 69.0 | −18% | 151 |
| update int c64, constant-hash comparer | 89.4 | 83.5 | −7% | 89.7 |
| lookup str c256 f50 | 41.0 | 28.9 | −30% | 81.0 |
| lookup str c4096 f50 | 45.8 | 33.3 | −27% | 87.8 |
| update str c256 f50 | 53.6 | 45.0 | −16% | 108.1 |
| miss str c256 f50 | 41.9 | 30.4 | −28% | 79.0 |
| insert str c262144 f25 (DRAM, page faults) | 637 [532..770] | 531 [487..632] | −17% | 327 |
| lookup i64 c4096 f50 | 41.3 | 17.6 | −57% | 60.3 |
| update i64 c4096 f50 | 58.0 | 37.8 | −35% | 74.4 |
| lookup obj c1024 f50 | 69.0 | 17.7 | −74% | 30.3 |
| update obj c1024 f50 | 81.5 | 38.9 | −52% | 41.5 |

Family spread of the candidate is ≤0.3% on every cache-resident row: with the
hot path in two functions the placement lottery has almost nothing left to
draw. The three DRAM rows moved with the machine's memory state during the
day (the string insert re-ran at 716/706/344, `matrix-win64-insert-str.txt`;
the 1M-int rows at 279/146 in the int-only run) — the ratio held, the absolute
numbers of those rows are not a property of the change. String insertion of
new keys (Delphi faster) is the untouched insert path of `doc/BACKLOG.md`
"Reserved dictionary construction".

`dict_ptrhash.dpr` (`results/ptrhash-*.txt`): `TDictionary<Pointer,Integer>`,
512 keys at the strides an allocator hands out, lookup cycles/op:

| stride | 8 | 16 | 24 | 32 | 48 | 64 | 96 | 128 | real `TObject`s | ints 0..511 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 33.6 | 33.6 | 34.6 | **67.3** | 38.0 | **68.0** | 43.9 | 33.6 | **68.7** | 38.1 |
| candidate | 14.7 | 14.9 | 14.6 | 15.3 | 14.6 | 14.5 | 14.9 | 14.8 | 15.1 | 14.9 |

The bundled MM hands out small objects at a 32-byte stride: every
`TDictionary<TObject,...>` in MoonBot (`DetectTimes*`) sat on the slow column.

## Linux, Xeon W-2295 (Cascade Lake)

Same programs, one placement, `taskset -c 5`, min of three process medians,
TSC ticks per operation (no per-thread cycle counter on Linux). Built against
the installed toolchain of 2026-09-10 with the base and the candidate
`Generics` compiled from source (`results/linux-xeon-ab.txt`,
`linux-xeon-ptrhash.txt`, `linux-xeon-sizes.txt`).

| scenario | base | candidate | Δ |
|---|---:|---:|---:|
| update int c256 f25 | 47.9 | 24.7 | −48% |
| update int c4096 f50 | 48.5 | 35.7 | −26% |
| lookup int c256 f25 | 36.6 | 20.8 | −43% |
| lookup int c4096 f50 | 36.0 | 34.6 | −4% |
| miss int c4096 f50 | 46.6 | 52.1 | **+12%** |
| insert int c1M f25 | 133 | 95 | −28% |
| mixed int c1M f25 | 95.7 | 67.7 | −29% |
| update int c64, constant-hash comparer | 98.7 | 90.8 | −8% |
| lookup str c256 f50 | 53.5 | 41.0 | −23% |
| lookup str c4096 f50 | 60.2 | 51.5 | −14% |
| update str c256 f50 | 65.3 | 42.1 | −36% |
| miss str c256 f50 | 59.8 | 46.4 | −22% |
| insert str c262144 f25 | 627 | 599 | −4% |
| lookup i64 c4096 f50 | 53.4 | 37.1 | −31% |
| update i64 c4096 f50 | 65.5 | 37.3 | −43% |
| lookup obj c1024 f50 | 73.1 | 25.5 | −65% |
| update obj c1024 f50 | 89.6 | 29.2 | −67% |

Pointer strides on the Xeon: base 32.3/31.4/32.7/**68.2**/46.0/**68.2**/60.3/30.6
for strides 8..128, real `TObject`s **72.9**; candidate 18.5–20.1 everywhere,
real `TObject`s 20.1.

## The boundary: sequential integer keys in tables beyond L1

The two rows above that did not improve are sequential integer keys (the
benchmark's `int` keys are 0..n−1, looked up in order) in a 64 KiB table.
Sweeping the table size on the Xeon (`results/linux-xeon-sizes.txt`) and on
the Ryzen (`results/matrix-win64-int-flatcrc.txt`, `flatcrc` = the flat path
with the old CRC32C hash, built from a source copy with `build.ps1 -Generics`):

| int keys, lookup / miss | base | flat + CRC32C | candidate (fmix) |
|---|---:|---:|---:|
| Xeon c1024 f50 | 36.4 / 31.4 | 18.0 / — | 25.7 / 28.7 |
| Xeon c4096 f50 | 36.0 / 47.1 | 18.5 / 33.9 | 34.6 / 52.0 |
| Xeon c16384 f50 | 36.1 / 46.9 | 18.7 / 34.9 | 39.1 / 60.0 |
| Ryzen c4096 f50 | 33.7 / 37.7 | 19.4 / 28.7 | 16.6 / 16.3 |
| Ryzen c16384 f50 | 33.7 / 38.0 | 19.4 / 29.2 | 22.1 / 43.9 |

For an arithmetic progression of keys the GF(2)-linear CRC happens to be a
*perfect* hash in these tables (`results/hash-probes.txt`: 1.00 probes for
`int seq 0..n` at every size), while the finalizer is random-like (1.5 probes
per hit, 2.5 per miss at load 0.5). Every extra probe is a data-dependent
branch the predictor cannot learn once the key sequence is longer than its
history, and beyond L1 a second line: on the Xeon that costs 7–15 cycles, on
the Ryzen it shows only past 16 K slots. Misses pay the most (2.5 probes).

Why the CRC is not kept for ordinals anyway: its perfection is an accident of
which key bits vary. The same CRC collapses on the populations the product
actually has — allocator-strided pointers (10 probes per hit, 28 per miss at
512 keys; 67–73 cycles per lookup measured on both machines) and sequential
keys that start at an offset (`int seq 1000000+`: 7.6 probes per miss) — and a
hash that is perfect on every progression and never collapses does not exist:
the low index bits of a multiplicative hash see only `stride * K`, a linear map
is injective on a bit window only when its columns happen to be independent
(`hash_probes.py`, worst cases: CRC32C 28.5, Fibonacci high half 11.2,
multiply-fold 4.3, finalizer 2.7 probes). The finalizer has the smallest worst
case, 1.5/2.5 everywhere, which is also the behaviour class of Delphi's FNV-1a;
the sequential-key rows above are the price of that robustness, on the Xeon
+12% (misses) and −4% (hits) against the old path at 64 KiB, +8% hits at
256 KiB, on the Ryzen +15% misses at 256 KiB.

## Round 2 (same day): the Delphi contracts the test did not check

The RTL test was strengthened against Delphi 12.2's `TDictionary` contract
and found five deviations, one of them in the flat path, one a lost
reservation that had been there all along (`results/matrix-win64-capacity.txt`,
three-way: `baseline` = before, `candidate` = round 1, `candidate2` = this):

1. **Object keys ignored `Equals`/`GetHashCode` overrides.** Delphi's default
   comparer for class keys calls the virtual `TObject.Equals` and
   `GetHashCode`, so a class can define value equality for use as a key.
   The flat path hashed and compared the address (and so did the comparer
   path: FPC's Generics binds `tkClass` to the pointer comparer). Now the
   default comparer of `tkClass` is the Equals/GetHashCode one, and the flat
   path checks the key's VMT slot: a class that does not override keeps the
   address fast path (one compare per hash), an overriding class is
   dispatched. Cost on `lookup obj c1024`: none measurable beyond the
   capacity effect below.
2. **`Create(N)` reserved nothing.** `TOpenAddressing.Create` set the load
   factor *after* the inherited constructor had already sized the table, so
   the threshold was computed from a factor of zero; the first `Add` took the
   table for an unallocated one and replaced the 4096-slot reservation with
   eight slots, then grew it back through nine rehashes. `doc/BACKLOG.md`
   "Reserved dictionary construction" (307 vs 176 cycles per element) was
   this. The test now checks the capacity after every add of the fill; a
   check only at the end passes, because the last add grows the table back
   to the reserved size (the negative control `capacity-lost` found that).
3. **`Capacity` counted slots, not items.** Delphi's `Create(N)` /
   `Capacity := N` hold N items without growing; ours held 0.75 N. Now the
   slot count is the power of two whose threshold covers N (Delphi allocates
   at least 2 N for its 50% factor; we allocate N/0.75 rounded up).
4. **`Create(collection)` raised on a repeated key**; Delphi keeps the last
   value. Now merges (`AddOrSetPair`), and the `Create(array of TPair)`
   constructors exist.
5. **A nil comparer crashed on first use**; Delphi takes the default one.
   **`ExtractPair` of a missing key returned `Default(TKey)`**; Delphi returns
   the requested key.

What the capacity contract costs and buys (Ryzen, cycles/op; a benchmark
that says `Capacity := 1024` now gets 2048 slots):

| scenario | baseline | round 1 | round 2 | Delphi |
|---|---:|---:|---:|---:|
| insert str c262144 f25 (no rehash inside the reservation any more) | 567 | 655 | **216** | 289 |
| miss int c4096 f50 | 38.1 | 16.5 | **12.7** | 39.1 |
| miss int c16384 f50 (the round-1 boundary) | 38.0 | 44.0 | **19.6** | 35.9 |
| lookup int c16384 f50 | 33.7 | 22.0 | **19.2** | 40.1 |
| lookup obj c1024 f50 (2048 slots + 512 objects leave L1) | 68.5 | 17.6 | 23.9 | 30.5 |
| lookup i64 c4096 f50 | 41.1 | 17.6 | 20.3 | 60.3 |
| lookup str c256 f50 | 41.1 | 28.9 | 31.3 | 78.0 |
| mixed int c1M f25 (32 MB table, past L3) | 85.7 | 74.9 | 112.5 | 163.9 |

A dictionary that never sets a capacity - every MoonBot one - is untouched
by item 3: it grows the same way as before. The reserved benches pay the
larger table where it crosses a cache level and win where the reservation
used to be thrown away or the load was high.

The official Pulse `dictionary` program (quick mode, one placement,
`results/pulse-dictionary-quick-delphi-vs-moon.md`): Moon/Delphi geomean
**0.633** over 30 cases, 25 faster, 3 within 5%, 2 slower
(`u64-string-build-grow-100` 1.21x, `u64-string-churn-10000` 1.11x);
`u64-string-build-reserved-100` 0.90x, the backlog row closed. The release
number is the medium run with placement families, not this.

Not in this round: Delphi's `TObject.GetHashCode` is `Integer`, FPC's is
`PtrInt` - a Delphi class overriding it as `Integer` does not compile against
our RTL yet (the test overrides it as `PtrInt`); the `Collisions` property of
Delphi's `TDictionary` is not provided.

## What the change does not touch

- `TObjectDictionary` derives from `TObjectOpenAddressingLP`, not from the
  linear-probing class: it keeps the comparer path and its notifications.
- Insertion of new string keys (`insert str`), the memory manager, the load
  factor (0.75) and the table layout are unchanged.
- The op-cache placement effect that started this work (`doc-int/experiments/
  prefix-lab/DICT_REGRESSION.md`) is not "fixed" by this change; the hot path
  merely became small enough that the lottery has little to draw from. The
  diagnostic for it is `qualification/performance/tools/opcache_sets.py`.

## Reproduce

```powershell
# a baseline toolchain in a clean worktree (build.ps1 compiler), then:
cd qualification\performance\evidence\dictionary-flat-20260921
.\build.ps1 -Toolchain <baseline>\toolchain -Tag baseline -Fillers 0,1,2,3
.\build.ps1 -Toolchain ..\..\..\..\toolchain -Tag candidate -Fillers 0,1,2,3
.\build.ps1 -Toolchain <baseline>\toolchain -Tag baseline -Program dict_oracle -Define ORACLE_ORDERFREE
.\build.ps1 -Toolchain ..\..\..\..\toolchain -Tag candidate -Program dict_oracle -Define ORACLE_ORDERFREE
python run_matrix.py --variants baseline,candidate --exe-extra delphi=build\dict_bench-delphi\dict_bench.exe --out results\matrix.json
python negative_controls.py
python hash_probes.py
```
