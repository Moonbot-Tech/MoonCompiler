# Product mORMot line for tests

This holds the mORMot 2.3.8832 source line actually used by MoonBot Delphi
projects. It is needed only by the complete compiler corpus: the compiler and
user projects do not receive these units automatically.

- Source: a pinned, verified snapshot of the mORMot 2.3.8832 product line.
- Imported snapshot: `8a524ccd381615d740f5d2d437b6a9205e02b9b4`.
- `mormot.crypt.core.pas` contains the product Keccak-256 patch from the
  current local tree; its shared Delphi/FPC gate is described in TESTS.md.
- Only sources and static libraries for x86-64 Linux/Win64 are retained.
- `src/core/mormot.core.fpcx64mm.pas` is intentionally absent: the entire
  system has one canonical MM, `runtime/mm/mormot.core.fpcx64mm.pas`.
- The mORMot license is retained in [LICENCE.md](LICENCE.md).

Tests for this line are in `qualification/suite/fixtures/mormot-2.3.8832/test`.
The runner pins the MM name to the canonical source through the
`--pinned-unit` compiler option, so an old or accidental unit of the same name
does not participate.
