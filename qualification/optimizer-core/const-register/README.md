# Float constants and the registers of a loop

```text
python qualification/optimizer-core/const-register/run_const_register_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

A float constant which a procedure reads more than once lives in a register
temp from the entry (`do_consttovar`, `compiler/optcse.pas`). The register
allocator (`compiler/rgobj.pas`) knows that the temp holds its constant:
spilled, the register reads the constant's memory - no stack slot, no store,
no load at the entry - and a value the colouring leaves without a register
takes the colour of constants, which go to their memory, where their reads
cost less than its loads and stores and the colouring stays complete
([Optimizer](../../../doc/OPTIMIZER.md#float-constants-in-registers)).

`const_register.dpr` is run at -O2 and -O3; each routine is checked against the
same arithmetic on writable typed constants, and a store into the read-only
memory of a literal constant would fault. In the -O3 object a loop is a
backward jump inside a routine:

- `HourDeltas` - the hour deltas over 5-minute candles, `Max` and `Min`
  expanded in a loop of 15 xmm values, constants 0, 1 and 100 needed only after
  it: no xmm value stored to the stack inside the loop;
- `PressureLoop` - fifteen values of a loop with `Max` and `Min` expanded, 0.25
  three times a turn: no scalar float value stored to the stack;
- `Witness14` - the same without any call: no scalar float value stored to the
  stack;
- `InLoop2` - no call, 0.125 twice a turn, accumulators read and written on
  every turn: no scalar float value stored to the stack;
- `BranchLoop` - no call, 0.5 in both branches of a loop with few variables:
  the constant is loaded into a register before the loop and the loop reads at
  most one constant from memory (the compare) - where the register pays, it
  stays;
- `Reverse` - 0.75 four times a turn of a loop which needs every register, a
  value written before the loop and read after it: the loop reads no constant
  from memory - the value goes to the stack, the constant keeps its register;
- `Deltas` - the hour deltas with the maxima and minima written out, the
  constant 1 read twice after the loop: no register which Win64 saves and
  restores (xmm6-xmm15) is written only by loads of constants.

Every routine is counted - instructions without padding - against
`reference.json` of the target: a routine that grew is red; one that shrank is
reported, and `--record` writes the new counts on purpose. The compiler before
the allocator knew its constants fails `HourDeltas` (a variable of the loop in
the stack, 1 and 100 in registers), `PressureLoop`, `Witness14` and `InLoop2`
(the constant's register stored to the stack at the entry and read from there
on every turn), and on Win64 `Deltas` (xmm8 and xmm15 saved and restored for
the constants 1 and 100 alone).
