# x*x of a real operand: sqr(x), squared in place

```text
python qualification/optimizer-core/sqr-fold/run_sqr_fold_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

`x*x` of a real `x` without real effects (calls, assignments, volatile reads)
is folded into `sqr(x)`: `x` is evaluated once and squared in the register it
was loaded into. An exception of `x` - a range check, a nil dereference, a
floating-point trap - is raised by its first evaluation in both forms, so it is
no reason to keep two evaluations. When the fold refused every operand that can
raise, `Sum := Sum + A[I] * A[I]` loaded the element once through CSE and
multiplied a copy of it (`movapd`, one more uop per iteration; the variance loop
of `heartbeat/correlation-32x256`). The gate runs the program at -O2 and -O3
(value, `ERangeError` of the checked operand, two calls of an effectful operand,
a `Volatile` operand) and requires at -O3 `mulsd xmmN,xmmN` without a copy in
the loop of `Variance` and two reads of the volatile operand in `VolatileSquare`
(on SysV the mean arrives in `xmm0`, the result register, and is moved out once
in front of the loop - no copy of the square).
