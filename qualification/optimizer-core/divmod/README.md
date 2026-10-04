# Paired `div`/`mod` gate

On x86-64, one `DIV` or `IDIV` instruction produces both the quotient and the
remainder. This gate proves that MoonCompiler reuses the complementary result
for adjacent expressions with unchanged register operands.

The semantic matrix covers signed and unsigned 32-bit and 64-bit operands,
both expression orders, boundary values, division traps, aliased destinations,
and side-effecting operands. The assembly check requires one hardware division
for exact pairs and two for the alias and side-effect controls.

Run it against an installed toolchain:

```sh
python qualification/optimizer-core/divmod/run_divmod_pair_gate.py
```

For an isolated developer backend, pass its compiler and matching configuration
explicitly:

```powershell
python qualification/optimizer-core/divmod/run_divmod_pair_gate.py `
  --compiler dev-backend/bin/x86_64-win64/ppcx64.exe `
  --config toolchain/ide/bin/x86_64-win64/fpc.cfg
```

The release matrix runs it at the medium stage on both targets (job
`divmod_pair`), as the public CI does. The compiler of the release before the
repair fails it: two divisions in each of the eight exact pairs, at -O2 and at -O3
(Win64, 28.09).
