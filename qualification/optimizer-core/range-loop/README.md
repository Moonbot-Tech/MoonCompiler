# Proven full-range loop gate

With range checking enabled, `for I := Low(A) to High(A)` already proves that
every executed `A[I]` is in range while the array descriptor remains stable.
This gate checks that MoonCompiler's O3 loop-strength pass replaces the indexed
access with a maintained pointer for dynamic, open and static arrays in both
loop directions.

The runtime matrix is run at O-, O2 and O3 and covers empty, single-element and
populated arrays. At O3, deliberate out-of-range bounds and a descriptor changed
through a `var` call are negative controls. Offset and narrowing conversions
also remain outside the proof. Their range helpers and source semantics must
remain.

Run it against an installed toolchain:

```sh
python qualification/optimizer-core/range-loop/run_range_loop_gate.py
```

For an isolated developer backend, pass its compiler and matching configuration
explicitly:

```powershell
python qualification/optimizer-core/range-loop/run_range_loop_gate.py `
  --compiler dev-backend/bin/x86_64-win64/ppcx64.exe `
  --config toolchain/ide/bin/x86_64-win64/fpc.cfg
```

The release matrix runs it at the medium stage on both targets (job
`range_loop`), as the public CI does. The compiler of the release before the
repair fails it: the range helper stays in the five dynamic and open-array
loops at -O3 (Win64, 28.09).
