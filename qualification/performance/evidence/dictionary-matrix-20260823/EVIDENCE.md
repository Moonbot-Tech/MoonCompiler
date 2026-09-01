# Pulse evidence: dictionary-matrix-20260823

This is a versioned summary of a separate Win64 O3 medium qualification of
`TDictionary<TKey,TValue>` at two sizes. The matrix was added after it became
clear that prior `rtl`/`rtl-collections` cases measured dictionaries mainly at
one medium size and could not reveal size-dependent degradation.

- source HEAD: `10f422932c8e4789e87ae4693535d3b3b77041ba`;
- worktree at manifest capture: clean;
- compiler binary is the same as in `integration-final-20260823`;
- system: Windows 11 x86-64, AMD Family 25 Model 33, 16 logical CPU;
- mode: `medium`;
- matrix: 24 cases, Delphi 12.2 / Moon+bundled MM / Moon+default FPC MM;
- types: `UInt64 -> UInt64`, `UnicodeString -> UInt64`,
  `UInt64 -> UnicodeString`;
- sizes: exactly 100 and 10,000 elements;
- operations: growing build, build with reserve, hit+miss lookup,
  remove/reinsert of half the table;
- semantic oracle: `24/24 MATCH`.

One `Delphi/dictionary/u64-u64-build-grow-100` process pair had `1.255x` drift.
The runner therefore deliberately returned a non-zero exit code. Raw logs and
the aggregate are retained, but this case is excluded from the stable summary.
For the remaining 23 cases, Moon/Delphi geomean is `0.9569`: 10 faster, 3 at
parity, 10 slower.

The matrix exposed three distinct physical effects:

1. A string key is not a general bottleneck: Moon hit/miss lookup takes
   `0.311x` of Delphi at 100 and `0.505x` at 10,000 elements.
2. `UInt64 -> UInt64` reserved build at 10,000 takes `1.378x` of Delphi, and
   the bundled MM makes it `2.533x` slower than the FPC default MM. This is a
   separate large-array allocation/zeroing/release path, not hash or `Add` cost.
3. `UInt64 -> UnicodeString` churn takes `1.563x` at 100 and `1.744x` at
   10,000. The MM effect here is `1.005x`/`1.006x`, so the allocator is excluded
   as the cause. The remaining execution path is backward-shift deletion in a
   dense open-addressing table and managed assignment/refcount on deletion and
   reinsertion; the contribution of the two parts still needs A/B separation.

`build-reserved` means checking the ordinary application idiom
`Dictionary.Capacity := Count`, not asserting that both implementations choose
the same internal slot count. At 10,000 elements, Moon chooses 16,384 slots at
load factor `0.75`; Delphi chooses 32,768 at load factor `0.50`. The matrix must
keep precisely this memory/time-policy difference visible.

Full aggregate report: [REPORT.md](REPORT.md). Machine-readable values:
[summary.json](summary.json). Raw logs, binaries, and the complete manifest are
in ignored `results/pulse/dictionary-matrix-medium-20260823`.

Key hashes:

- compiler: `2448238e15a306be14b6a24433afa8cb5c0641e1204d055d97baa289f9d2d53c`;
- compiler config: `91f931689135277c317a9fb325b42b9bdbb5995e165b51bae7d8de39e52a8543`;
- bundled MM: `b0af17e29e98cca60a8c5ca8a7670552b78b43cafa6171289a4a6c6107ff40af`;
- Delphi `dcc64`: `68cf81c0b1044e585eb584d96947a01e669605d8ac1ed048a2de44fd867fdb88`;
- raw manifest: `A1C8D51F72B7C5C283E73A64922AB31984C0D1456D1DF96AEB314CD70C0E7619`;
- `summary.json`: `64F36134A32E6E50BD3D2F2795820D44E77D6DFA80DFDC18A044BA33E5472B79`;
- `REPORT.md`: `B21E17810AA37F7C263A8CFD0A7638B3495AEE087EB975073EB485A52D1834C5`.
