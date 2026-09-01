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

## Why it is not fixed now

Object Pascal does not promise an argument evaluation order. Therefore both
sequences preserve the language semantics when source does not hide dependent
side effects in adjacent arguments. A search in MoonBot and Arbitrage found no
proven live call that relies on this order; the finding arose in a synthetic
Pascal-vs-ASM component, retained as the separate Devil `asm-oracle`, not in a
product Chimera composition.

Changing the order would affect lowering of all calls, hidden parameters,
managed temporaries, and both ABIs. Without a live need, that is a
disproportionate pre-release risk. The boundary remains explicit: dependent
state reads/mutations must be evaluated in separate statements. If a real
product call appears, this decision is reconsidered against its exact form, not
against a general promise of parity.
