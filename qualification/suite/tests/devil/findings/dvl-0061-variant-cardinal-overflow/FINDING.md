# dvl-0061 — `Cardinal` did not survive a round trip through `Variant`

Status: **fixed**.

## Observed error

`Variant(Cardinal($FFFFFFF0))` retained the correct `VarType=varLongWord`, but
assignment back to `Cardinal` raised `EVariantOverflowError`. Debug/O1/O2/O3
failed identically. Delphi 12.2 returns the original value.

The cause was not in the compiler frontend: the `Variant -> dword` operator in
`System` unconditionally called signed `VarToInt`, so the upper half of the
`Cardinal` domain first had to fit in `Integer`.

## Fix

- narrow integer carriers retain the previous allocation-free `VarToInt` path;
- exact `varLongWord` is read directly;
- the Variant manager converts all other carriers directly to `varLongWord`;
- string carriers follow the measured Delphi semantics: parse as a number,
  round, and perform the normal modulo conversion to `Cardinal` under
  `{$Q-}{$R-}`.

The same contract is implemented for `Variant` and `OleVariant`. The changes
do not affect assignment *to* Variant and do not change the carrying `VarType`.

## Evidence

The Delphi 12.2 oracle and permanent regression
[`variant_cardinal_semantic.dpr`](../../../../../../RTL-test/semantic/variant_cardinal_semantic.dpr)
cover the `$7fffffff/$80000000/$ffffffff` boundaries, signed/unsigned 64-bit,
rounded Double, negative and above-32-bit string values, and both Variant
kinds. O-/O2/O3 must print `VARIANT_CARDINAL_OK`.
