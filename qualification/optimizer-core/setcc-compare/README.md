# Materialized conditions compared with one

`SETcc` produces exactly 0 or 1. A following byte comparison with 1 and an
equality/inequality consumer can use the original flags directly. The peephole
retains a live materialized value, preserves intervening flag dependencies,
and requires the comparison's flags to be dead after the consumer. Wider
comparisons and other predicates retain their original comparison.

`run_gate.py --compiler <ppcx64> --rtl <rtl-units> --output <directory>` runs
signed boundary values at three optimization levels and inspects generated
Pascal routines. A live enum result must retain its SETcc while losing the
redundant CMP; an enum with values 1/2 must retain its comparison. The frozen
compiler fails this positive code-shape assertion. The semantic source also
builds with Delphi 12.2.

Intervening arithmetic may become LEA only when no later instruction reads
its flags. IMUL additionally requires a supported width, immediate multiplier
2/3/4/5/8/9 and a register source/destination. Its replacement has two operands
and preserves the original destination. The Pascal multiply-by-seven Boolean
case fails to assemble on the frozen compiler even through the old TEST path;
the repaired path retains IMUL. Multiply-by-three keeps its useful LEA and
direct condition. Runtime checks also cover an independent zero condition
produced by an intervening ADD.

The assembler routines in the semantic program are ISA oracles only: user ASM
bypasses the peephole and cannot prove its rejection paths. `setcc_ir.pas`
instead calls the real `OptPass2SETcc` on instruction lists with register
lifetime markers. It covers both branch and SETcc consumers, a live result,
intervening ADD/IMUL, distinct IMUL source/destination, every supported scale,
unsupported width/multiplier, intermediate SETcc/CMOVcc flag readers,
width/value/predicate rejection, and flags live on a taken
branch even though the fallthrough overwrites them. The earlier draft using
`RegUsedAfterInstruction` fails that last negative control. The same lifetime
requirement applies to the existing TEST path: its fixed CF/SF values cannot
be replaced with the original flags while another consumer still needs them.

`run_ir_gate.py --output <directory>` builds this driver and its compiler
dependencies from the checkout, using the ordinary-string IDE compiler/RTL.
Each invocation uses a fresh unit directory, so stale product compiler PPUs
cannot satisfy the test. `--compiler` and `--config` override the bootstrap
paths. This source gate retains argv, source/backend/executable hashes and
elapsed time; it is separate from the installed-toolchain runtime gate.
It invokes the actual local peephole, not the whole compiler pipeline. Its
minimal procinfo supplies the frame pointer needed by lifetime bookkeeping.

The lifetime contract comes from code generation: `g_flags2reg` consumes the
allocated comparison flags, `nx86cnv` releases them after materialization, and
`a_cmp_*_label` encloses its comparison/branch with allocation and release.
The peephole uses those markers; it must not infer death from an instruction
on the fallthrough alone. Inline ASM remains a barrier outside this path.

A release followed by a new allocation starts a different flags lifetime.
After a SETcc consumer, flag-neutral instructions may precede the release;
the scan stops at control flow, flag reads/writes and opaque markers. It never
walks the fallthrough of a Jcc to justify changing flags on its taken path.
The IR controls retain these barriers, including calls and an opaque flag reader.

`BuildLabelTableAndFixRegAlloc` used to move an explicit arithmetic-flags
release past a call because `InstructionLoadsFromReg` inherited the conservative
all-register CALL read. Arithmetic flags are not x86-64 ABI arguments, so that
lifetime query now leaves the release in place; direction-flag subregisters
and the conservative instruction-motion query are unchanged. The runtime
callback-index form guards the complete producer/optimizer path and must not
gain an extra byte TEST before its indirect call.
