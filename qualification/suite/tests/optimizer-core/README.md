# Optimizer Core PPU Gate

This is a narrow cross-unit contract for optimized Pascal units. It checks that
the current compiler can reuse an O3 PPU without changing semantics or
artifacts, that independent cold builds are deterministic, and that a PPU from
an incompatible compiler is rejected explicitly.

The fixture crosses an inline function, a generic record, a managed record,
`UnicodeString`, and a dynamic array through a unit boundary. Every executable
must print the exact line `PPU_GATE_OK 877`.

## Run

On Linux, after building the current toolchain, run from the repository root:

```text
python qualification/suite/scripts/run_optimizer_core_ppu_gate.py --output .qualification/optimizer-core-ppu
```

The output directory must not already exist. The Linux default uses the
installed product compiler and configuration plus `/usr/bin/fpc` for the
incompatible-PPU negative control. On Windows the same runner requires an
explicit `--legacy-compiler PATH`; omitting the negative control is not a
complete run.

## Verdict

The runner performs:

1. a forced cold build and execution;
2. a warm build in the same directory, where the unit PPU must keep its bytes
   and modification time and the unit object must keep its modification time;
3. a second forced cold build whose PPU, objects, and executable must be
   byte-identical to the first cold build;
4. an O2 unit build with the legacy compiler, followed by a required rejection
   from the current compiler with an explicit PPU version or validity
   diagnostic.

Success prints `PPU_GATE_PASS` and writes `result.json` with source, compiler,
configuration, and artifact hashes plus the compile/run logs. This gate does
not claim general optimizer correctness; Devil, Mega/Omni, and focused codegen
gates cover those wider semantics.
