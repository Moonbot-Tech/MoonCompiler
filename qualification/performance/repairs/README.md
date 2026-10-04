# Repair performance sentinels

`pulse_repairs` is the compact A/B gate for compiler, RTL and memory-manager
repairs accumulated after a public baseline. It measures ordinary values and
common workloads, while the semantic qualification suite remains responsible
for exceptional and boundary behavior.

The program deliberately keeps all MoonCompiler repair sentinels in one
Moon-only executable, separate from the Delphi/Moon matrix. A single `quick`
run is suitable while editing; `medium` uses seven mirrored process pairs for a
release decision. Every case returns a semantic digest, so a faster but
different result is rejected before its timing is accepted.

`list all` only reports case metadata and needs no worker CPUs. Running
`padded-counters-4`, either alone or in a comma-separated selection, requires
five reserved logical CPUs: four workers and the coordinator. Other selected
cases do not start those workers.

The primary repair comparison is MoonCompiler before versus after the repair,
not MoonCompiler versus Delphi. Run the same source with the pinned baseline
and candidate toolchains:

```powershell
uv run qualification/performance/tools/pulse.py run `
  --mode medium --programs repairs `
  --systems moon-baseline,moon-candidate `
  --moon-baseline-toolchain <baseline-toolchain> `
  --moon-candidate-toolchain <candidate-toolchain> `
  --tag repairs-before-after
```

Delphi remains an additional oracle for cases within its language and RTL
surface, but this executable is not built by Delphi. A case is accepted only
against a pinned before/after toolchain pair and an independent semantic oracle.
Where before/after timing alone cannot prove code quality, add either a reviewed
machine-code contract or a same-process reference kernel with an explicit
overhead budget. A hard-coded timing from another machine is not an oracle.

The current matrix covers:

- floating-point folding, `Round`, `RoundTo`, `Ldexp`, `Mean`, `Variance`,
  `StdDev`, `Min` and `Max`;
- division/remainder sharing, endian swaps, range proofs, unrolling, loop
  invariants and pointer traversal;
- Unicode and byte-string COW, short text comparison, UTF-8 conversion,
  `TStringBuilder`, generic lists, sets and Variant dictionaries;
- record, static-array, `array of const`, managed-argument, interface and
  multi-argument ABI paths;
- a pinned four-thread padded-counter loop, exception dispatch and small-block
  allocator rings.

Its rows keep their data in globals of the program and take them into a local
before the case loop (`tools/check_case_loads.py`). The inliner treats a global
of the program differently from the field of an object or a global of another
unit, so a form of the product with the product's data layout is a row of
`product-forms`, which Delphi builds too.

The comparison threshold follows the rest of Pulse: below `0.95` is faster,
`0.95..1.05` is parity and above `1.05` is a regression requiring attribution.
The gate complements the full Pulse matrix; it does not replace it.
