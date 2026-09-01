# TDictionary numeric lookup — final evidence

Date: 2026-08-24. Win64, O3, `medium` mode, interleaved process order.
Systems: Delphi 12.2 + FastMM4, MoonCompiler + bundled MM, and MoonCompiler +
default FPC MM.

All 30/30 semantic oracles matched. Overall Moon/Delphi geomean: `0.883`, with
15 wins, 6 results at parity, and 9 losses. MM geomean: `1.083`; lookup does
not depend on the MM, and allocator cases are included only as an adjacent control.

## Target results

| Case, 10,000 | Before | Final | Physical result |
|---|---:|---:|---|
| `UInt64 -> UInt64`, mixed lookup | 1.056 | **0.963** | 3.7% faster than Delphi |
| `UInt64 -> UnicodeString`, mixed lookup | 1.160 | **1.007** | parity with Delphi |
| `UInt64 -> UInt64`, hit-only | — | **0.885** | 11.5% faster than Delphi |
| `UInt64 -> UInt64`, miss-only | — | **0.974** | 2.6% faster than Delphi |
| `UInt64 -> UnicodeString`, hit-only | — | **0.960** | 4.0% faster than Delphi |
| `UInt64 -> UnicodeString`, miss-only | — | 1.080 | 8.0% slower |

Three general RTL changes were accepted: Delphi-compatible `var` in
`TryGetValue`, sequential pointer traversal of linear-probing slots, and
explicit `inline` on the thin wrapper. The table's load factor and layout did
not change.

Exact-source verification: complete compiler bootstrap/install; focused semantic
Debug/O2/O3 `3/3`; full RTL-test Debug/O2/O3 `240/240`; Pulse `30/30`; ASM
contains no `TryGetValue` call from the benchmark loop and no
`TLinearProbing.Probe` call from linear lookup.

The MM and global load factor were not changed by this fix. This directory
contains the pinned final report and exact hashes of the accepted A/B.
