# Child-process output contracts

Run the real-process corpus against a complete installed SDK:

```sh
python3 qualification/process-output/run_gate.py --codepage-api --compiler /path/toolchain/bin/fpc --output /tmp/process-output
```

On Windows use `python` and `toolchain\bin\x86_64-win64\fpc.exe`. The output
directory must be new. Debug and Release are both tested; packaged unit names are
`Process` on Linux and `Process`/`ProcessUnicode` on Windows.

The executable launches itself as a child, without a shell or network. It covers
all `RunCommand` wrappers, stdout/stderr separation and merging, simultaneous pipe
pressure, binary bytes, NULs, Unicode, code pages, byte boundaries forced by an
acknowledgement, partial reads/writes, virtual overrides, callbacks, failed launches,
nonzero exit status and process reuse. See [the API contract](../../doc/PROCESS_OUTPUT.md).

Every case requires exit code zero and exactly one matching success marker. A
timeout terminates only that invocation and its child process tree. Commands,
timings and results are written to `results.json`, with a separate log per case.

`--source` optionally compiles a source overlay instead of using packaged PPUs;
`--support` supplies unchanged package includes for a partial candidate. This
mode also checks the two dotted source wrappers, without claiming they are
shipped SDK units. It never edits the SDK or source tree. Qualification and archive
checks use packaged PPUs and must include `--codepage-api`. Omit that flag only
when testing an old baseline without the `OutputCodePage` property.
