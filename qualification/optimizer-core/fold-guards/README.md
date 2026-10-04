# A fold asks what it does with the evaluation

```text
python qualification/optimizer-core/fold-guards/run_fold_guards_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

`might_have_sideeffects` (`compiler/nutils.pas`) answers three questions, and
each fold asks the one that fits what it does with an evaluation:

- one evaluation where the source has two, or two where it has one (`x*x`,
  `x and x`, `(x >= a) and (x <= b)`, a rotate, `n - n mod c`): only real
  effects matter - a call, an assignment, a volatile access; the first
  evaluation raises whatever the source raises;
- no evaluation where the source has one (`x*0`, `x - x`, `F and False`):
  effects and the exceptions the program asked for - an enabled range or
  overflow check, a checked cast, heaptrc pointer checking, an integer division,
  a floating-point operation - but not the fault of a read whose value is not
  used;
- an evaluation where the source has none (a short-circuit operand made
  unconditional): the fault of a read through memory as well.

`fold_guards.dpr` is run at -O2 and -O3: values, no fault where a
short-circuit guards a read through a nil pointer, `ERangeError` of checked
operands whose evaluation is merged or dropped, `0*x` of a NaN element still
NaN. In the -O3 object the gate requires the folds on operands read through
memory - one unsigned compare for a digit test of an element (also under
`$R+`, with its range checks), `rol` for a rotate of fields, one read for
`x - x mod 8`, the constant alone for `x*0 + 7`, no read for `x - x`, no
dead arm of a generic routine that tests its type after a field - and a
multiplication kept for `0*x` of an element. The compiler before the repair
runs the program right and fails each of the seven folds (one guard refused
every read through memory); the multiplication it keeps as well.

The repair of 20.09 these folds refine guarded the case of enabled range and
overflow checks, so the file sets no check switch of its own: the gate
builds it without checks, as the product profile does, and again at -O3
with `-Cr -Co`, runs it, and requires the checked object to carry more
calls of the range and overflow check routines than the plain one (a
`{$R-}{$Q-}` in the file makes both builds one code and the gate red) and
the digit test of an element, now checked, to keep its one unsigned compare
with its checks. The regressions of that repair
(`tests/test/cg/tobservablesimplify1.pp`, `trangefoldobservable1.pp`,
`trotatefold1.pp`, `tshortboolprune1.pp`, `tinlinecheckedruntime1.pp`),
which set their own checks, run at -O2 and -O3 on both targets: before this
gate the release ran the first three only in the Linux upstream suite.
