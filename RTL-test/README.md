# RTL-test

This is the permanent semantic matrix for MoonCompiler RTL fixes and
optimizations. It checks the exact product profile: Win64 or Linux x86-64,
Delphi mode, UnicodeString, the pinned bundled MM, and Debug/O2/O3 modes.

From the repository root:

```text
python RTL-test/run.py
```

If Python is installed through `uv` on Windows:

```text
uv run python RTL-test/run.py
```

For focused development, select individual modes and tests:

```text
python RTL-test/run.py --modes o2 o3 --only "collections|streams"
```

The runner enumerates every `semantic/*.dpr`, creates separate `-FU/-FE`
directories for each, runs the executable, and requires exactly one `PASS/OK`
marker. Temporary files are removed even on failure. `collections_codegen.dpr`
also checks the O3 assembly: concrete `TList/TQueue/TStack for-in` loops must
contain no remaining `MoveNext/GetCurrent` calls.
`string_empty_compare_semantic.dpr` prohibits O3 from retaining a full
Ansi/Short/Wide -> Unicode conversion for one comparison with an empty string.

`runtime_prefix_bare_semantic.dpr` and `runtime_prefix_semantic.dpr`
intentionally contain no service runtime units: they prove compiler-level
injection for a bare program and for `TThread`/`TMonitor`. Legacy semantic
sources with an explicit prefix simultaneously check backward compatibility
without double loading.

Linux-only `linux_stack_contract_semantic.dpr` reads the actual pthread
attributes of four thread types. The strict product oracle requires exactly
1 MiB and a guard page for `TThread` and default `BeginThread`; main/raw
pthread are recorded only diagnostically because they are governed by
`RLIMIT_STACK` and glibc.

`oracles/` contains separate sources for comparisons with Delphi 12.2 that
cannot honestly be replaced by a MoonCompiler self-check. In particular,
`float_text_dump.dpr` prints the exact `FloatToStr` for a deterministic set of
Double bit patterns; rows with the same first `bits` column are compared.
Compiled executables and dump files are not committed to the repository.

`deferred/` holds reproducible differential sets that are outside the green
release matrix. `rtlobjpas_core_deferred.dpr` is retained as an upstream
RTL-ObjPas RTTI differential: the extended RTTI from dvl-0037/dvl-0040 is
already covered by a separate exact runtime gate, and the raw Boolean ABI from
dvl-0049 is accepted as an exact boundary in `KNOWN_ISSUES.md`. These legacy
entries are no longer active TODO items.

Boundaries:

- this is semantic/codegen qualification, not a benchmark;
- the number of reviewed RTL files is not method coverage;
- undeclared external runtime dependencies and Wine are not allowed in the
  gate; Linux `libffi` is an explicit package dependency of RTTI Invoke;
- performance after changes is remeasured separately by Pulse.

The map of changed methods, adjacent areas, and the honest boundary of
executable coverage is in [COVERAGE.md](COVERAGE.md).
