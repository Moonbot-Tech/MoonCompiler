# Pinned unit

`--pinned-unit=<name>=<source-file>` makes the compiler take the specified unit
from exactly that source file. For a pinned unit, PPU files, packages, and
normal search paths are ignored, and `uses ... in 'another file'` is an error.

The mechanism pins the source, not its hash: the file can be changed together
with the compiler and will then be rebuilt. Other units continue to resolve in
the usual way.

`run.ps1` checks the following on Win64:

- the pinned source takes precedence over an external source or PPU of the
  same name;
- explicit bypass through `uses ... in` is rejected;
- a missing pinned file makes the build fail;
- unpinned units still resolve through `-Fu`;
- `--required-first-unit=<name[,name...]>` checks the ordered prefix of units
  actually included after conditional compilation and rejects an absence,
  a different order, or a hidden `{$IFDEF}` name.

`run.sh` checks the same contract on Linux through the installed product driver
`.moonbot/toolchain/bin/fpc` and its exact `.moonbot/toolchain/etc/fpc.cfg`.
A bare `ppcx64 -n` must not be used here: the configuration supplies system
linker paths, including `libgcc_s`, required by the built-in x86-64 PSABIEH.
