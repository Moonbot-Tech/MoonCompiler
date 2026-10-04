# The operand of an instruction is what the statement names

```text
python qualification/optimizer-core/operand-forms/run_operand_forms_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

A statement names memory: a field behind a pointer, an element at an index, a
variable of the unit. An x86 instruction takes such memory as its operand, so
the statement needs no instruction of its own to fetch it. Where the code
generator fetches it all the same - the value into a register, the address
into a register, the scaled index into a register - the peephole optimizer
folds the fetch back into the instruction, and whether it can depends on the
registers the allocator happened to give. The shapes of this gate are
statements whose code does not depend on that, and loops whose pointer is
read once.

`operand_forms.dpr` holds the statements and their values; the gate builds it
at `-O1`, `-O2`, `-O3` and `-O4` without checks and at `-O3` with range and
overflow checks and runs each program. In the `-O3` object every routine
whose name begins with `Shape` is counted - instructions without padding,
calls, and the instructions of its innermost loop - against `reference.json`
of the target: a count which grew is red; one which shrank is reported, and
`--record` writes the new counts on purpose.

## A subtraction whose operands lie in memory

`A^.B64 - B^.Inner^.B64`: the subtrahend stands behind more pointers than the
minuend, so the operands change their places for the evaluation and the
address of the subtrahend is computed first. The code generator
(`tx86addnode.second_addordinal`) loaded the operand which stood left - the
subtrahend after the change -, loaded the minuend into a second register and
subtracted the registers. The peephole optimizer folded the first load into
the subtraction where the register of the address lived up to it; the minuend
took that register where it was the first free one:

```text
before                          now
mov rax,[rdx+0x18]              mov rdx,[rdx+0x18]
mov rdx,[rax+0x10]              mov rax,[rcx+0x8]
mov rax,[rcx+0x8]               sub rax,[rdx+0x10]
sub rax,rdx
```

The operands go back to their places before the instruction is chosen. The
form with both operands in memory only: a minuend which is a register
variable or a constant goes the way of the three-operand form.

Shapes: `ShapeSubPointers`, `ShapeSubPointers32` (5 instructions before, 4
now, on both targets); `ShapeSubNested`, `ShapeSubReference`,
`ShapeSubStored` had the fold by their registers and keep their counts.

## The element at a scaled index

`Marks[Top].Removed`, an element of 40 bytes: the index is multiplied by a LEA
and a shift, and the shift goes into the scale of the address of the load
which follows (x86 peephole, `ShlOp2Op`). The rule asked whether the register
of the index is used behind the load and took it for used where the load
itself writes it: `lea (%rax,%rax,4),%rax; shl $3,%rax; mov 40(%rcx,%rax),%eax`
kept its shift. A load which writes the whole register of the index leaves no
reader of the shifted value; and the register may be the base of the address
as well as its index.

Shapes: `ShapeIndexField` (5 instructions before, 4 now), `ShapeIndexFields`
(16 before, 14 now); `ShapeIndexNested` reads its fields into other registers
and keeps its count.

## The address of a variable of the unit

`State.A := State.B + State.C`: the address of the variable in a register, the
register the base of the operands which follow, `lea State(%rip),%rax;
mov 584(%rax),%rdx; add 592(%rax),%rdx; mov %rdx,576(%rax)`. The operands name
the variable themselves and the register is free (`SymOps2Ops` for the
operands of several instructions, `LeaOp2Op` for one). An operand which took
the symbol of the LEA takes the kind of its reference with it; without it the
operand was not told from another name of the same memory and the memory
rules stopped at it: `ShapeOtherName` reads `Cell` into a register and does
not fold the read into the multiplication, 4 instructions as before.

Shapes: `ShapeSumFields` (5 instructions before, 4 now); `ShapeCopyField`,
`ShapeStepField`, `ShapeOtherName` keep their counts.

## An address which is a pointer and a constant

`PHeader(Nx - HeaderSize)^.SizeFlags := ... or 2`: the address in a register
of its own, `lea -12(%rax),%rax; orl $2,4(%rax)`. A LEA which adds a constant
to its own register was made an addition first, and an addition the
instruction which follows does not take; the conversion waits for that
instruction now, which takes the address as its operand: `orl $2,-8(%rax)`. A
load which reads through the address and writes the whole register of the
LEA takes it as well.

Shapes: `ShapeLoopSkipNames` (11 instructions before, 9 now; the loop 7
before, 5 now); `ShapeHeaderFlag`, `ShapeStepBack`, `ShapeStepBackRead` had
their addresses folded before and keep their counts.

## The target and the value of an assignment

`fItems[Index] := fItems[Index] * 3 + fItems[Index + 1]`,
`P^.Next^.Value := P^.Next^.Value * 2 + P^.Next^.Other`: what the target and
the value have in common is computed once (the assignment is a domain of the
common subexpressions, `cseinvariant` in `optcse`).

Shapes: `ShapeStepAtIndex` (9 instructions before, 6 now), `ShapeStepItem` (12
before, 11 now), `ShapeStepNode` (7 before, 6 now), `ShapeStepField` (6
before, 5 now); `ShapeStepTotal`, `ShapeDecide`, `ShapeTwoNames` keep their
counts - the last one reads and writes one record through two pointers, and
its value is the order of the statements.

## A loop of a method over an array which is a field

`for K := Count - 1 downto 0 do ... Items[K].Price ...`: the pointer of the
array is read from the object once, behind the entry test of the loop, and
the loop walks it, where nothing in the body can give the field another
array (`field_vector_base_is_stable` in `optloop`).

Shapes: `ShapeLoopMaxPrice` (26 instructions before, 23 now; the loop 20
before, 12 now), `ShapeLoopBuySell` (the loop 26 before, 24 now),
`ShapeLoopSumWide` (23 before, 19 now; the loop 14 before, 9 now),
`ShapeLoopBumpCells` (the element read and written in one statement: the
loop 6 before, 5 now, one pointer for both and the statement one
instruction), `ShapeLoopClearItems` (the element read in the condition and
written under it: the loop 15 before, 10 now). `ShapeLoopSumCells` (an element
of 8 bytes at a counter as wide as an address, read in one place) keeps its
count: the address is the operand, a pointer of its own takes nothing off the
iteration. `ShapeLoopCallInside` and `ShapeLoopSwapInside` keep their counts:
a called method or the body itself replaces the array.
