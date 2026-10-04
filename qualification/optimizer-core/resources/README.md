# Compiler-process resources

A correct executable does not prove that the compiler released its own working
objects. This focused gate checks all jump-tracking lists allocated by the x86
MOV optimizer while compiling the compiler itself at `-O3`.

The script instruments a disposable source copy, builds it with a native
x86-64 bootstrap, and counts list creation/destruction during a self-build.
Success requires a nonempty workload and exact balance. It checks the whole
allocation family, not just the three early exits that originally leaked.
The original compiler tree and installed toolchain are unchanged.

```powershell
python qualification/optimizer-core/resources/run_jump_tracking_gate.py `
  --bootstrap toolchain/bin/x86_64-win64/ppcx64.exe `
  --config toolchain/ide/bin/x86_64-win64/fpc.cfg `
  --output <new-directory>
```

On Linux the same with `--bootstrap toolchain/bin/ppcx64 --config
toolchain/ide/etc/fpc.cfg`. The source compiler must have been built once so
`msgidx.inc` and `msgtxt.inc` exist. Logs, source snapshot, instrumented
compiler and counters are retained in the output directory (without
`--output`, in the printed temporary directory).

The release matrix runs it at the medium stage on both targets (job
`jump_resources`), as the public CI does. It is red when a release comes
back: with the three releases of the repair (c9b2c3731) taken out of a source
copy, 7 of the 107124 lists the self-build creates stay unreleased
(Win64, 28.09).

It is not a proof that all compiler allocations are leak-free. The
instrumented build is diagnostic-only; no counters enter product code.
