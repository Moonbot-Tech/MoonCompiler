# F3a: x86-64 machine facts

This gate qualifies the read-only machine-layer foundation used by later
address-GVN and register-allocation work.

It checks that:

- the target-owned x86 decoder reports explicit and implicit register USE/DEF;
- every generated unsigned DIV records exact USE+DEF facts for both RAX and RDX,
  rather than merely increasing an aggregate counter;
- definition versions reach later uses inside an extended basic block;
- opaque calls become the target decoder's conservative all-register barrier;
- facts use an explicit generation and invalidation protocol, never a stable
  assembler-node identity across transformations;
- repeated observation is deterministic;
- enabling observation changes neither generated assembly nor runtime output.

`run_f3_scaling.py` separately generates large straight-line procedures and
checks that ADDRESSGVN machine-fact construction scales linearly enough for
production use and leaves their assembly byte-identical.  The generous timing
limits reject the former quadratic implementation without turning normal host
noise into a failure.

Run on the host target with:

```text
python qualification/optimizer-core/f3/run_f3_gate.py
python qualification/optimizer-core/f3/run_f3_scaling.py
```
