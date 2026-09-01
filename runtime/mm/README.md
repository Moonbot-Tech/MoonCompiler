# Bundled x86-64 memory manager

`mormot.core.fpcx64mm.pas` is MoonCompiler's sole product allocator for Win64
and Linux x86-64. The build driver pins this source with `--pinned-unit`, and
the compiler injects it before the user's `uses`; a unit or PPU with the same
name from an external mORMot cannot replace the process allocator.

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

The original unit was written by Arnaud Bouchez of Synopse, based on Pierre le
Riche's FastMM4. Its original disjunctive MPL 1.1 / GPL 2.0+ / LGPL 2.1+
license with the FPC static-linking exception is retained; the full notice is
in [LICENSE.md](LICENSE.md).
