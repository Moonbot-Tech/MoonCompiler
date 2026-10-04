# Read-only loop address hoist

```text
python qualification/optimizer-core/loop-address/run_loop_address_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --objdump /path/to/objdump --output /new/directory
```

Run against a matching compiler and complete RTL configuration. The output
directory must be new. O-/O2/O3 and Linux default/PIC cover all 17 ordinary
forms and 10 negative control-flow/dataflow forms, with independent integer
oracles and an exact inventory of every expected result. A missing result is
a failure. GNU objdump and llvm-objdump are supported.

The O3 positive check reads the linked internal-emitter code and requires the
single static-address LEA to precede the inner backedge. Win64 checks the four
FP accumulators; Linux PIC checks anonymous static data because ordinary Linux
globals already use direct addressing or a hoisted GOT base.

Calls, side entrances, ASM, exception regions, modified bases, one-use addresses,
memory writes and register pressure are neighboring controls. These semantic
checks supplement the measured placement matrix; they do not claim whole-product
qualification or a universal performance guarantee.
