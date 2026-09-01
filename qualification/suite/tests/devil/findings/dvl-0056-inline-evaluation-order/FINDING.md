# dvl-0056 — side-effect order of two inline expansions in one expression

Found by the first full `run_devil_gate.py --layers all` run with DCC64 (the
`inl` layer with its oracle had not run before): loose notes
`dvl-inl-*-total` for the `inline-result-used-twice` shape, seeds 1–2 — 31
cases, all with the same mismatch.

## What happens

```pascal
function F: Integer; inline;
begin
  Inc(Counter);
  Result := Counter * 10;
end;

Total := F + F;
```

Both compilers execute the body twice (the hard `-calls` = 2 check agrees). We
evaluate the expansions sequentially: the first sees `Counter=1` and returns
10, the second returns 20, for a total of 30. DCC hoists both `Inc` operations
above the multiplications: both reads see `Counter=2`, for a total of 40. Our
result is the same in every O0–O3 profile — it is the inliner's model, not an
optimization effect.

## Verdict: the mismatch is in our favour

Sequential evaluation is the only order in which an expansion behaves like a
non-inlined call: `F + F` without `inline` returns 30 under DCC as well. DCC's
hoisting therefore changes the program's observable behaviour solely because
of inlining — its “inline does not change semantics” rule is broken, while ours
holds. The language does not prescribe operand evaluation order, so both are
formally legal, but ours is consistent and code with this pattern (a
side-effecting function twice in one expression) can at least rely on it.

No fix is needed. The registry entry closes the `dvl-inl-*-total` notes; the
layer's hard checks continue to guard the number of calls.

## Related results from the same run

Derived issues without their own cluster: the digest split between our profiles
came from a different number of known dvl-0014 language failures in the digest;
`dvl-load-handoff-2600-balance` was a timing flake in an MM load with 48
threads, unrelated to inlining.
