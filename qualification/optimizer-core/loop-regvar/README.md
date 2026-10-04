# Spilled values across call-free loops and loop compare orientation

```text
python qualification/optimizer-core/loop-regvar/run_loop_regvar_gate.py
python qualification/optimizer-core/loop-regvar/run_loop_regvar_gate.py --compiler /path/to/ppcx64 --rtl /path/to/rtl/units
```

Fast native x86-64 gate for two code generator rules. The sources are
`tests/test/cg/tloopregvarpromote1.pp` and `tests/test/cg/tloopcompareorient1.pp`;
both are built at `-O-`, `-O2` and `-O3` and must return 0 against digests
from an independent model. The assembler checks read the `-O3` listing.

The register allocator keeps a spilled integer value which the outermost
call-free loop accesses in a register of its own across that loop, loaded
before the loop and stored after it (`rgobj`, loop regions marked by `ncgflw`).
The test is compiled with `-dWP4_LOOPSPILL_STATS`, which makes the compiler
print one `LOOPSPILL` line per routine (loop regions, region registers given,
values refused one for the register pressure, values accessed only on the way
out of the loop). The gate requires that fourteen
call-free loops access no frame slot at all - the heartbeat request loop, tested
at its beginning against a bound read from the record like the heartbeat, whose
hash and pointer are spilled, break and continue with zero trips, a nested
loop, Byte and Word carriers, a value parameter, a value dead after the loop,
two loops which end the enclosing body, `repeat .. until False`, two for-step
loops, a loop whose recurrences the allocator keeps in registers, a loop
whose invariant bound is spilled and a loop which writes a spilled value on
every iteration - and at least two region registers in the
heartbeat loop and one for the spilled bound. A loop region without spilled
values - recurrences already in registers, a loop without an enclosing loop -
gets no region register and no copies at its entry; a loop with a string
assignment and a loop with `Exit` are no loop regions. A spilled value written
only just before `break` gets no region register: the write runs at most once
per entry, and the load and the store would cost more than it.

A compare of two memory operands inside a loop loads the operand which does
not depend on a variable the loop writes and keeps the loop-dependent one as
the memory operand of `cmp` (`nx86add`). The gate checks this orientation
for every relation, signed and unsigned, at 8, 16, 32 and 64 bits, and in a
loop condition. The mirrored condition is proven by the digests.

The gate runs natively on Win64 and Linux x86-64; `--compiler-option`
passes additional options, for example `-FD` for a compiler without the
toolchain's `as` beside it.
