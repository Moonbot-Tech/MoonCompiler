# x86-64 `shl` + `lea`/`add` merge gate

The peephole optimizer merges `shl $y,%r` with a following `lea`, `add`,
`sub`, `inc` or `dec` on the same register into one `lea`.  The merged `lea`
reads the *unshifted* register and scales it, so it must not use the shifted
register as its base: `shl $1,%r; lea (%r,%r,2),%r` is `6*r`, but the merge
produced `lea (%r,%r,4),%r`, which is `5*r`.  The same held for
`shl $1,%r; add %r,%r` (`4*r`, merged to `3*r`).  Found on 2026-09-14 by the
branch pad gate (`../placement/run_branch_pad_gate.py`): its `-O2` and `-O3`
digests differed.

`run_shl_lea_gate.py` compiles `shl_lea_scale.dpr` at `-O2`, `-O3` and
`-O3 -OoNOCODEALIGN`, runs it and requires the same success line from every
build; the program itself checks both products against an oracle that
multiplies by a runtime factor, so the optimizer cannot fold it.

```powershell
python qualification/optimizer-core/shl-lea/run_shl_lea_gate.py
python qualification/optimizer-core/shl-lea/run_shl_lea_gate.py `
  --compiler <ppcx64.exe> --rtl <units/x86_64-win64/rtl>
```
