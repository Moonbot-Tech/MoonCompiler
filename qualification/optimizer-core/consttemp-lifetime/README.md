# Persistent constant and address lifetime

Run with an explicit compiler and its matching complete RTL configuration:

```text
python qualification/optimizer-core/consttemp-lifetime/run_consttemp_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

The gate checks O-/O2/O3, including PIC on Linux, against independent integer
and exact binary-fraction expectations. Manual goto enters the middle of the
loop, has a backedge, and includes zero/negative bounds and early exits.
It also compiles an inline unit and physically hides its private source copy
before compiling the consumer from its PPU. The output directory must be new.

Before the repair, a persistent GOT address could share a register with the
last payload load. The next backedge used the overwritten address and crashed.
Both address and real-constant temporaries now receive their normal delete node
at function exit. No optimization is disabled for the whole function.
