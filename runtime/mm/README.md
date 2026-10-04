# Bundled x86-64 memory manager

`mormot.core.fpcx64mm.pas` is MoonCompiler's sole product allocator for Win64
and Linux x86-64. The toolchain's `moon-base.cfg` pins this source with
`--pinned-unit`, and the compiler injects it before the user's `uses`; a unit
or PPU with the same name from an external mORMot cannot replace the process
allocator.

The product configuration requires:

```text
MOONBOT_MM_PROFILE_REQUIRED
FPCMM_BOOSTER
FPCMM_MOONSHARD
```

The rest of mORMot is not included here. Its provenance, architecture,
diagnostic mode, differences from the current upstream, and qualification are
described in
[Memory Manager](../../doc/MEMORY_MANAGER.md).

The source is a copy of `core/mormot.core.fpcx64mm.pas` from
[`Moonbot-Tech/MoonORMot`](https://github.com/Moonbot-Tech/MoonORMot) at the
commit pinned for qualification (`mormot.sources.current.commit` in
`qualification/suite/runner_manifest.json`, always the tip of MoonORMot
`main`). The qualification runner rejects a run unless the copy equals the
pinned file (line-ending differences are ignored), and
`scripts/sync-moonormot.py` moves the pin, this copy and the runtime units'
version floor together; it refuses to overwrite a copy that was edited here
and not carried to MoonORMot. Updating either side can therefore not silently
leave the other behind. See "MoonORMot records" in
[Testing](../../doc/TESTING.md).

The allocation-failure/unwind and small-pool handoff repairs described in
[Memory Manager](../../doc/MEMORY_MANAGER.md) are mirrored in the pinned
MoonORMot source. Source equality is checked separately from whole-product
qualification; the addressed repair checks do not claim that qualification.

The original unit was written by Arnaud Bouchez of Synopse, based on Pierre le
Riche's FastMM4. Its original disjunctive MPL 1.1 / GPL 2.0+ / LGPL 2.1+
license with the FPC static-linking exception is retained; the full notice is
in [LICENSE.md](LICENSE.md).
