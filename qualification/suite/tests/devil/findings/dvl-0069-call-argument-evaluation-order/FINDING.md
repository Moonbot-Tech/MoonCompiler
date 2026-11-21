# dvl-0069 — argument evaluation order differs from DCC64

Status: **accepted release boundary; not language wrong code**.

## Observation

For an ordinary call `P(F(1), F(2))`, DCC64 36.0 calls `F(1)` before `F(2)`,
whereas MoonCompiler calls `F(2)` before `F(1)`. The difference recurs for
procedures, functions, record methods, and nested expressions on Win64 in all
four profiles. Open-array construction takes a separate route and matches
DCC64: left to right.

[`probe/argorder.dpr`](probe/argorder.dpr) produces `12/123/12345` on DCC64 and
`21/321/54321` on Moon. [`probe/evalorder.dpr`](probe/evalorder.dpr) separates
arguments from binary operators: current Moon builds already match the measured
DCC64 behavior for operators. [`probe/inlineorder.dpr`](probe/inlineorder.dpr)
pins this boundary for stateful inline methods.

## Product example and decision

Consider a binary protocol that writes a mode byte followed by a Boolean.
Its reader evaluates `Apply(ReadByte, ReadBool)` on a shared stream cursor. For input `01 00`,
an independent Win64 probe returned mode 1 and False with Delphi 12.2,
and mode 0 and True with Moon 2.5.4. Reading the fields into two locals in
wire order returned mode 1 and False on both.

The protocol requires a read order. Express it with successive statements before
calling the handler. The [Delphi reference](https://docwiki.embarcadero.com/RADStudio/Athens/en/Procedures_and_Functions_%28Delphi%29#Calling_Conventions)
does not promise left-to-right evaluation for the default register convention.
The observed DCC64 order remains useful for compatibility testing. The portable
application repair works with the existing call lowering on both compilers.
