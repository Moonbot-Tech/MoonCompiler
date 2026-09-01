# dvl-0062 — O3 preserved a global after an autoinlined mutation

Status: **fixed**.

## Observed error

The full Devil optimizer-effects matrix uses a global from an external unit in
loop arithmetic and, after the first iteration, calls a small procedure from the
same unit that changes the global. Debug/O1/O2 and Delphi 12.2 produce `127`,
whereas O3 with AUTOINLINE produced `142`: subsequent iterations continued to
read the old value. `-OoNOAUTOINLINE` returned the correct result.

A short handwritten form does not reproduce the defect: it depends on the
complete compilation unit and AUTOINLINE decisions. Therefore the permanent
regression is the full Devil case `dvl-opt-effect-00501`, not an artificial
green mini-test.

## Cause

The former strength-reduction legality check combined two incompatible views:
the DFA built before the tree's final form, and its own list of “opaque”
call/ASM/pointer writes. After AUTOINLINE, the call disappeared, while its direct
write to the global did not always reach the old DFA decision. The global was
therefore incorrectly considered unchanged.

## Fix

A static scalar is now checked by the shared `opteffect` model on the **final
tree**. It sees both the remaining opaque call and a direct write introduced by
AUTOINLINE. The separate local alias/effect scan was removed: strength reduction
does not own a second, diverging memory model.

The boundary is deliberately conservative: until `opteffect` distinguishes the
identity of different globals, a write to any global prohibits such hoisting.
This may forgo a rare optimization, but it does not create wrong code; global
identity should be refined once in the shared effect model, not here.

## Evidence

- full pre-fix release repro: `dvl-opt-effect-00501 actual=8E expected=7F`;
- the same source with `-OoNOAUTOINLINE`: correct result;
- the full post-fix release repro must eliminate this divergence;
- [`tloopopaqueeffects1.pp`](../../../../../../tests/test/cg/tloopopaqueeffects1.pp)
  retains focused call/procvar/nested/pointer and safe-control boundaries.
