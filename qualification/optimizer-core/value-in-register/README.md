# A value in a register is not read back from memory

```text
python qualification/optimizer-core/value-in-register/run_value_in_register_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

Three producers made the compiled code read from memory a value the program
had just put into a register, or had in one anyway:

- a zero extension of a 32-bit register whose upper half is already clear
  (`movl %edx,%edx`) stayed between the store of an element and the read of
  the same element. The proof that the upper half is clear
  (`CanDrop32BitZeroExtend`, `compiler/x86/aoptx86.pas`) stopped at the notes
  of the register allocator between two instructions, and the rule which gives
  a load the register just stored needs the two next to each other (Pulse
  `loops/aliased-update` and `loops/nonaliased-update`: `StoreReload`,
  `StoreOther`);
- that rule, and the one which gives a second load the register of the
  first, look at the next instruction only: an instruction in between that
  touches neither the memory nor the registers - an argument loaded with a
  constant - kept the read. `ForwardMemoryValue` looks past such instructions
  (`StoreThenAdd`: the element just written is an operand of the next
  statement's arithmetic; `ContainsMiss`: a global object read for the call
  and for its table of methods, Pulse `hot-rtl/list-int-contains-miss`);
- the inliner copied the actual of every `const` parameter into a temp before
  a body that writes anything outside its frame - also a constant, and the
  caller's own local, which nothing the body does can change
  (`inline_actual_is_callers_own`, `compiler/ncal.pas`). A string temp lives
  in the frame: `StringReplace(Name, '_', '', [])` stored and copied its three
  strings through two inlined wrappers before the call of the worker (Pulse
  `product-forms/market-by-int-name`: `CleanName`), and the inlined assertion
  of `TSynTestCase` stored its constant empty message in the frame and read it
  back on every turn (`CheckAll`).

The comparison of the corpus with main `e3017da29` found a form the forwarding
had made one instruction longer: `Assigned(Value) and (Value is TClass)` over a
local of the frame compares it with nil twice, the second time behind the
conditional jump of the first. The first compare went to the register and the
repeat did not, so `CMP/Jcc/CMP` no longer saw a repeat. The forwarding now
passes the conditional jump, and `TEST/Jcc/TEST` removes the repeat whatever
reads the flags (`KidAt`, fcl-pdf's `TPDFDocument.GetPageNode`).

It found two forms the inliner's repair had made longer, now counted as well:
`ToByte` (the `VariantTo*` of varutils), where the inlined
`VariantTypeMismatch(vType, varByte)` reads neither parameter and the move of
the constant was what the peephole put over the dead read of `vType` - a
constant for a formal the body never reads keeps its register copy; and
`FlipSheet` (fcl-report's `TFPReportExportPDF.DoExecute`), where the real
constant of an inlined setter, read in the body, stood between the address of
the field and the store - a real constant keeps its register copy.

`value_in_register.dpr` is run at -O-, -O2 and -O3; every value is the one of
the text. In the -O3 object the gate counts every routine - instructions
without padding and memory accesses (an operand in memory, `lea` apart; `push`
and `pop`) - against `reference.json` of the target: a routine with more of
either is red; one with fewer is reported, and `--record` writes the new counts
on purpose. Apart from the counts: `StoreReload` and `StoreOther` extend no
32-bit register into itself, `CheckAll` touches no cell of its frame, and
`CleanName` calls no `StringReplace` wrapper (the form stays the product's).

The values of the inliner's side - the forms where the body can change the
actual and the temp must stay: the same local as a `var` and a `const`
actual, its `absolute` twin, a field of the record `Self`, the result assigned
to the actual, a local behind a pointer, a global the body writes, a temp of an
outer inline - are in
[RTL-test/semantic/inline_const_alias_semantic.dpr](../../../RTL-test/semantic/inline_const_alias_semantic.dpr).

## What is red

Counts are instructions / memory accesses of the -O3 object against the
reference.

| Compiler | Win64 | Linux |
|---|---|---|
| main `637933feb` | `StoreReload`, `StoreOther`: `mov edx,edx`; `CheckAll` stores and reads its frame; every routine but `ContainsMiss` above the reference (`ContainsMiss` reads the global twice as main does, next to each other) | the same |
| with the extension proof only | `StoreThenAdd` 34/11 against 34/10; `CleanName` 38/21 against 32/14; `CheckAll` 38/14 against 17/4 and its frame | `StoreThenAdd` 25/5 against 25/4; `CleanName` 45/21 against 39/13; `CheckAll` 37/13 against 16/4 and its frame |
| with the look past the next instruction as well | `CleanName` 38/21; `CheckAll` 38/14 and its frame | `CleanName` 45/20; `CheckAll` 37/13 and its frame |
| the inliner's repair without the look past the next instruction | `StoreThenAdd` 34/11; `ContainsMiss` 23/8 against 22/7: the constant argument now stands between the two reads of the global | `StoreThenAdd` 25/5; `ContainsMiss` 23/8 against 22/8; `CleanName` 39/14 against 39/13 |
| the merge with main `e3017da29`, before the forwarding passed a conditional jump | `KidAt` 42/13 against 41/12 | `KidAt` 42/14 against 41/13 |
| the forwarding passing a conditional jump, before the two constant rules | `ToByte` 39/9 against 39/8; `FlipSheet` 18/10 against 17/10 | `FlipSheet` 16/9 against 15/9 (`ToByte` is the same: the dead read does not appear on Linux in this form) |

## Composition of addresses and register copies

The current `StoreThenAdd` also needs two general facts before the existing
memory forwarding rule can recognize the stored value. An absolute symbol
address can fold into a base-plus-index operand within the existing byte-growth
budget; an indexed operand already has its SIB byte. RIP-relative addresses
cannot contain an index, and PIC, volatile, segmented, overflowing or still-live
address producers retain their previous barriers.

`Upper32ZeroBefore` shares the backward proof used by `CanDrop32BitZeroExtend`.
A previous unconditional 32-bit write makes a subsequent 32-bit register copy
an equality of the complete registers. The existing `DoZeroUpper32Opt` handles
read replacement, allocation and changes to either register. A future write
cannot establish this equality at the copy. Source/target mutations, calls,
unknown markers and incoming branches retain their barriers. The shared
replacement helper also preserves the encoding restrictions of AH/BH/CH/DH.
Those hostile high-byte cases are IR contracts, not a claim that ordinary
Delphi arithmetic currently emits them.

The runtime gate additionally runs `value_forward_semantic.dpr` at all three
levels and in Linux PIC mode: dirty upper halves, truncation, source mutation, indexed shifts and
byte division with independent arithmetic answers. Its separate assembler
witnesses observe all 256 shift counts, including zero and masked-zero counts.
They check the ISA producer, not peephole reachability. The width rule is in
[Intel SDM Volume 1, section 3.4.1.1](https://cdrdv2-public.intel.com/843820/325462-sdm-vol-1-2abcd-3abcd-4-1.pdf);
the shift instruction's zero count preserves flags, while the 32-bit register
result remains zero-extended.

The actual compiler-unit IR gate is separate from installed-runtime checks:

```text
python qualification/optimizer-core/value-in-register/run_ir_gate.py --compiler /path/to/ordinary/ppcx64 --config /path/to/ordinary/fpc.cfg --output /new/directory
```

It builds fresh dependencies and covers known/unknown widths, partial and
conditional writes, both sides of copy lifetime, branch entries, metadata,
legal and illegal high-byte substitutions, absolute/RIP/PIC indexed addresses,
growth limits and observable accesses. Success is `VALUE FORWARD IR GATE: PASS`.
The installed gate's `StoreThenAdd` bounds are now Linux24/4 and Win64 34/10;
the earlier current compiler produces28/5 and39/12 respectively.

On Win64 an indexed global operand retains its RIP address in a register.
Equivalent global references are compared by symbol, displacement, scale and
the defining write of the index, including a proven zero-extended 32-bit copy.
Repeated RIP address producers reuse a live address register. A copy left by
memory forwarding is removed only after a bounded walk proves no reader on
either branch or a loop backedge. Calls, partial writes with later readers,
opaque code, nonlocal and exception edges keep the copy. The IR gate covers
these boundaries and changes of the base to another global symbol.
