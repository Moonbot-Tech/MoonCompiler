# F2 minimal LICM gate

`run_f2_gate.py` compiles `licm_semantic.dpr` at `-O-`, `-O2` and `-O3`
with F1 observation enabled, first without and then with the independent
`-OoLICM` switch, and a third time with `-dOPTCORE_VERIFY`.  It proves three
different properties:

- both binaries produce the same fixed semantic digest;
- the post-transform F1 observer sees a new compiler temp in the three intended
  positive routines, while thirteen negative routines receive no temp delta at
  all.  This deliberately proves the resulting tree shape; it is not presented
  as an independent proof that every motion decision was legal.
- the compiler-injected per-iteration verifier accepts every hoisted value.

For the native x86-64 backend the gate also proves that product `-O3`
matches explicit `-OoLICM`; `-OoNOLICM` remains the independent opt-out.

Legality is covered independently by the fixed runtime digest, the injected
per-iteration verifier, the negative matrix and the destructive model/pass
sabotages.  Moving the observer before LICM would destroy its intended temp-
delta proof without making the shared effect model independent of itself.

The negative matrix covers a mutated exact local, by-ref call clobber, global,
threadvar, pointer storage, checked zero-trip multiplication, zero-trip
division, the lowered `for..step` latch, managed function results and calls,
changing dynamic-array length, real arithmetic, and a routine containing a
label/goto.  The positive matrix covers a plain while loop, a compound
invariant in the nearest preheader of nested runtime loops, and
break/continue paths.  The test therefore fails both when the pass does
nothing and when it crosses one of its explicit safety boundaries.

`run_f2_perf.py` is a short pinned-thread ABBA proof for the exact consumer:
the same executable source is compiled at `-O2` with the phase switch off and
on, both semantic digests must match, and the median TSC cost per inner-loop
iteration must fall by at least ten percent.  It is intentionally a focused
phase gate, not a replacement for Pulse or Heartbeat.  On Linux the runner
resolves `libgcc_s` through the host GCC driver, so isolated `-n` linking does
not depend on an ambient machine-specific `-Fl` option.

`run_f2_sabotage.py` is the destructive mutation proof and requires a clean
compiler-source tree.  It rebuilds three deliberately broken compilers: one
ignores loop mutations, one treats trapping arithmetic as movable, and one
omits the lowered loop latch.  The semantic/verifier gate must kill all three,
then the script restores and rebuilds the pristine compiler.

`run_f2_ppu.py` freezes the generic replay contract.  Two repeated cold builds
prove deterministic PPUs both with LICM off and on.  A full producer off/on x
consumer off/on matrix then compiles with only the producer PPU visible.  The
current consumer build owns the codegen decision: either producer must allow
an enabled consumer to hoist, and neither producer may force a disabled
consumer to hoist.  All four executables return the same semantic digest.
