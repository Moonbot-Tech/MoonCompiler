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
marker. The work directory is created in Python's temporary directory
(`TMPDIR`, otherwise `TEMP`/`TMP`), and each row's directory is removed as soon
as the row passes, so a run needs the space of its largest row, not of the
whole matrix; the rest is removed even on failure. On Linux the runner first
requires the unversioned `libffi.so` that RTTI Invoke links (`libffi-dev` on
Debian/Ubuntu). `collections_codegen.dpr`
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
cannot honestly be replaced by a MoonCompiler self-check: the same program is
built by `dcc64` and by MoonCompiler and the two outputs are diffed. In
particular, `float_text_dump.dpr` prints the exact `FloatToStr` for a
deterministic set of Double bit patterns; rows with the same first `bits`
column are compared. `masks_oracle.dpr` enumerates every mask of up to three
atoms over letters, `*`, `?` and sets against short texts (plus non-ASCII
and NUL) and prints the match bits or the error position;
`zlib_oracle.dpr` covers the `System.ZLib` buffer/string/stream helpers,
seeks in every direction and the errors on damaged input (Delphi 12.2 links
zlib 1.3.1 objects as well - its unit declares `ZLIB_VERSION` '1.2.13', its
`deflate.o` identifies itself as "deflate 1.3.1" - so the compressed bytes are
the same and the digests are compared directly); `zlib_exchange.dpr` writes
zlib, raw and gzip files and a ZIP archive with one build and reads them with
the other (and with Python's zlib/zipfile), in both directions;
`buffered_stream_oracle.dpr` drives
`TBufferedFileStream` and a plain `TFileStream` through one random sequence
of reads, writes, seeks and resizes. The differences the oracles found are
recorded in the semantic tests' headers (`masks_semantic.dpr`,
`zlib_semantic.dpr`, `buffered_file_stream_semantic.dpr`). Compiled
executables and dump files are not committed to the repository.

The semantic tests also cover missing preset dictionaries in high-level
ZLib calls, draining pending raw-deflate output after input EOF, empty
`uncompress`, and buffered file writes flushed by seeks from the end or
outside the buffer window. Masks include a repeated-star rejection case
that must complete without recursive backtracking.

`deferred/` holds reproducible differential sets that are outside the green
release matrix. `uint64_shl_const_compare_deferred.dpr` is an open compiler
differential (2026-09-21): a constant built from `UInt64` casts with
`shl`/`or` folds as a signed `Int64`, and a comparison of a `UInt64`
variable with it is folded to "always false"; Delphi compares `True`. `rtlobjpas_core_deferred.dpr` is retained as an upstream
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
