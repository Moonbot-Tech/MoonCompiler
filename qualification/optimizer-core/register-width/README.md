# x86-64 register width gate

`run_gate.py` checks three native compiler modes (`O-`, `O2`, `O3`) against
Python value oracles. It writes the generated Pascal source, expected values,
per-function output, compiler logs, and compiler SHA-256 to a new output
directory. A run fails on the first difference.

The original matrix has 720 functions and four inputs (2,880 values per mode).
The structural matrix has 480 functions and 14 inputs (6,720 values per mode).
It crosses eight signed/unsigned 8/16/32/64-bit types with comparisons,
conditional increments, source order, and five consumer shapes: selection,
Boolean flag, array address, typed noinline call, and typed store/reload.
Every generated function prints its identity and result separately. The Python
oracle models casts and signed 64-bit modular arithmetic without using the
output of another compiler as its expected value.

The 22-row `flags_fixture.py` executes inline assembly for ADC and SETcc with
the original MOV, a 32-bit self-MOV, and a deliberately wrong AND. The negative
rows show that AND changes live flags. This fixture bypasses the optimizer and
does not establish that a Pascal source reaches a particular peephole rewrite.
Four further rows verify that 32-bit shifts with counts 0 and 32 clear the
upper half, while 16-bit shift and MOV preserve it.
The structural call and store/reload rows are useful consumer controls; they
also do not prove reachability of every optimizer rewrite.

For a native toolchain build:

```text
python qualification/optimizer-core/register-width/run_gate.py --compiler <installed-ppcx64> --output <new-output-directory>
```

Use the compiler inside the installed toolchain so `$FPCBINDIR` in the base
config resolves to its units. The Linux executable and config are selected
automatically; pass `--config` when testing a different installation.
