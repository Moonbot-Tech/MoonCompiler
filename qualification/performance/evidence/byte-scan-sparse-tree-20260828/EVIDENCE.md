# Sparse `case` / byte-scan evidence

## Initial signal

Stable Win64 medium baseline before the fix:

| Case | Moon/Delphi |
| --- | ---: |
| `byte-scan-small-16` | `1.070x` |
| `byte-scan-medium-256` | `1.091x` |
| `byte-scan-large-4096` | `1.093x` |

Moon ASM already used pointer bump and retained the string length. The gap was
in seven sequential comparisons of sparse `case` values. DCC 12.2 split the
range around byte `91` and resolved ordinary misses at a lower depth.

## Fix

- the shared backend retains upstream threshold 64;
- x86-64 permits a tree from seven labels;
- this permission applies before the old linear-list gate only when the range is
  sparse;
- a small dense `case` remains linear and is not turned into a jump table.

Generated `ScanJson` now first compares the byte with `91`, then resolves the
left or right half. The old `subb` cascade is absent.

## Correctness

```powershell
uv run python RTL-test\run.py `
  --only sparse_case_tree_semantic
```

Result: Debug/O2/O3 `3/3 PASS`. The test exhaustively covers all 256 byte
values and signed range `-1200..1200` with independent oracles.

## Short performance checks

Five independent interleaved quick process pairs `Delphi, Moon`:

| Run | small | medium | large |
| --- | ---: | ---: | ---: |
| 1 | `1.029x` | `1.043x` | `0.994x` |
| 2 | `1.019x` | `1.011x` | `1.028x` |
| 3 | `1.002x` | `1.031x` | `1.024x` |
| 4 | `1.027x` | `1.010x` | `1.039x` |
| 5 | `1.028x` | `1.045x` | `1.015x` |
| median | **`1.027x`** | **`1.031x`** | **`1.024x`** |

Raw outputs are in
`qualification/performance/results/pulse/byte-scan-sparse-tree-20260828*`
and are intentionally not versioned. These short runs prove the direction of
the fix but do not replace the final exact-HEAD medium gate.

A separate codegen quick retained dense dispatch at the previous level and
improved sparse dispatch. Its overall report is not accepted as qualification
evidence: unrelated `fillchar-4k`, `scan-llc`, and `scan-strided` violated the
process-drift policy.

These measurements prove a win for the measured mostly-miss byte scan and no
regression in its dense control. They do not prove universal superiority of the
balanced tree: a linear chain can win when its first label is very hot. Without
a PGO profile, the balanced variant is selected to limit the worst comparison
depth of a small sparse `case`, without claiming minimax for actual x86-64 cost.
