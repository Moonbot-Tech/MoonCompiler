# x86-64 hot-code alignment gate

`run_code_alignment_gate.py` proves the current `-OoCODEALIGN` contract on
x86-64:

- `-O3` aligns procedure entries, natural loop headers and explicit Pascal
  labels to 32 bytes;
- `-O2 -OoCODEALIGN` proves that the switch remains independently usable;
- `-O2`, `-OoNOCODEALIGN` and size optimization preserve the old layout;
- an explicit wider `{$CODEALIGN ...=64}` contract is not narrowed;
- all variants execute the same semantic digest;
- the focused executable stays inside a coarse test-specific code-size guard.

Procedure alignment covers hot routines called by an outer loop, event loop or
network callback.  Natural loop alignment covers compiler-lowered
`for`/`while`/`repeat`; explicit labels cover hand-written `goto` loops.  The
compiler deliberately does not align every internal branch target: without
profile data it cannot distinguish a hot destination from cold error and exit
paths, so doing so would only trade instruction-cache space for speculation.

Referenced explicit Pascal labels are different: the current policy aligns
every one of them.  Therefore the focused 10% guard is not a global size bound;
a label-heavy state machine may accumulate padding roughly in proportion to
its referenced labels.  This is an accepted release trade-off, not a hidden
invariant.  A future bounded/PGO policy needs a real buyer and runtime A/B.

Pulse remains the performance and aggregate code-size oracle.  This gate is a
structural contract and does not treat one favourable benchmark address as a
compiler invariant.
