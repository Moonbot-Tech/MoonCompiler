# MoonCompiler Optimizer

MoonCompiler extends the existing FPC optimizer rather than replacing it with a
new IR and backend. The adopted architecture adds the missing facts about
effects, memory, loops, and exception regions exactly where the tree optimizer
and x86-64 backend use them.

The goal is not the maximum number of transformations, but faster machine code
with fail-closed semantics: if an alias, trap, or lifetime cannot be ruled out
with proof, the transformation is not performed.

## Semantic contract

An optimization must preserve:

- values, the order of observable side effects, and the number of calls;
- exception points, access/range/overflow checks, and unwind lifetime;
- aliasing through `var/out/constref`, pointers, captures, and parent frames;
- refcount and `Initialize`/`Finalize`/`Copy`/`Assign` of managed values;
- volatile, atomic, threadvar, and shared state;
- IEEE signed zero, NaN/unordered comparison, and the active floating
  environment;
- Win64 and SysV x86-64 ABI, including nonvolatile registers and exception
  frames.

A call, inline ASM, an unknown write, and a managed operation are barriers
until precise analysis proves otherwise. Globals, heap, and address-taken locals
are not treated as pure merely because the current tree shows no direct write.

## Empty inherited constructors

With empty-procedure elimination enabled, a direct, unused inherited class
constructor call may be removed when the compiler proves that its non-allocating
entry has no work. For example, `inherited Create` in a field-writing constructor
no longer calls an empty `TObject.Create` wrapper. The proof uses the constructor
body and its implicit work, not its name.

Allocation, `NewInstance`, construction hooks, failure cleanup and VMT entries
retain their behavior. Allocating calls and explicit constructor calls on existing
objects are not covered. Unknown bodies, old-style objects, property defaults,
managed local/formal lifetime, `out` formals and instrumented entries remain
conservative. Actual arguments retain the existing effect checks; the common
O2/O3 benefit is a parameterless inherited constructor.

The proof uses existing PPU node-tree metadata without requesting inlining or
changing the PPU format. Previous compilers can read these PPUs and retain the
call; the new compiler also accepts older PPUs, retaining the call when proof is
absent. New metadata changes unit checksums, so rebuild the RTL and dependent
packages together. System.ppu grows by 808 bytes in the qualified Win64/Linux
builds; there is no new runtime decision or allocation.

Qualification checks the source-free PPU boundary, O-/O2/O3 and mixed modes,
constructor hooks, exceptions, implicit initialization and unchanged object paths.
The permanent gate is `qualification/optimizer-core/constructors/run_gate.py`.
Shrinking executable code can change placement; the performance stand therefore
also compares the original call with equal-size NOPs and identical-code controls.

## Forwarding calls

In Release, an x86-64 routine that only prepares register arguments, calls a
target and forwards its result can use a tail jump. The target is still invoked
exactly once. The wrapper needs no local stack storage, outgoing stack arguments,
nonvolatile-register saves or cleanup; any work after the call must be an
identity result move. The target's volatile set participates in the wrapper's
register-save proof, including calls with a different calling convention.

The transformation runs after register allocation and before frame/unwind
generation. It preserves faults in argument setup or virtual dispatch, target
exceptions and caller handlers. It does not enable the older late CALL/RET
peepholes more broadly. Debug preserves the forwarding frame. Release stack
traces can omit that frame, as they can omit an inlined frame; `noinline` controls
inlining, whereas `STACKFRAMES` explicitly requests a frame. Profiling, stack
checks, frame introspection, assembler, managed cleanup and meaningful result
conversions retain their existing paths.

`qualification/optimizer-core/tail-forwarding/run_gate.py` checks the actual
installed profiles, positive tail jumps, retained frame/result contracts and
exceptions both inside the wrapper and in its target.

## Effect model

The shared `opteffect` layer classifies reads and writes by storage location:

- an exact registerable local or compiler temporary;
- a parent-frame/captured local;
- global/static/threadvar;
- a field, array element, or indirect memory;
- managed storage;
- unknown memory.

Exact locals may receive narrow non-interference proof. Heap, global, and
indirect state conservatively intersect an opaque call or unknown write. Loop
passes and CSE use the same model, so the two optimizers cannot interpret the
same call barrier differently.

## LICM

Loop-invariant code motion hoists only expressions that:

- do not depend on storage modified by the loop;
- do not throw or contain an observable side effect;
- remain correct for a zero-trip loop;
- do not materialize a managed value before its original point;
- provide a measurable gain without excess register pressure.

Integer/address arithmetic with a proven range is allowed. Native x86-64
integer-to-Single/Double conversions are also allowed when the complete
storage range fits the destination precision. Signed widenings introduced by
lowering are followed; declared subrange bounds are not a proof. Such a
conversion neither rounds nor changes FP exception flags. Inexact conversions,
x87/Extended and floating-point arithmetic retain their effect barriers.

A candidate must read only exact current-frame symbols and contain no compiler
temps. Private temps elsewhere in the loop (for example, pointer walking or an
inlined enum getter) do not invalidate those symbols. Indirect/reference temp
writes still block motion. This is a separate LICM query; the general effect
conflict query keeps its conservative temp barrier.

Profitability counts integer and vector-FP values separately, including
registerable loop temps. Integer hoists retain the existing input-count
heuristic: their temporaries may replace input registers. Each planned exact
conversion adds a value to the FP budget because its input is an integer.
The four-hoist bound remains. After transformation, normal firstpass refreshes
register and type information. The runtime, FP-state and emitted-loop checks
are in `qualification/optimizer-core/f2/run_exact_gate.py`.

## Materialized x86 conditions

SETcc produces a byte equal to zero or one. Comparing that byte with one and
testing equality can reuse the original condition, just as the existing
TEST-zero form does. Both forms require the comparison flags to be dead after
the consumer, including a taken branch. An explicit release ends that lifetime;
a later allocation begins another. A SETcc consumer may have flag-neutral
instructions before the release, but calls, branches and opaque blocks remain
barriers. Arithmetic flags already released by the producer are not call
arguments in either x86-64 ABI; lifetime metadata must not extend them to CALL.

Intervening arithmetic can become LEA only while preserving all observed flag
values. A SETcc or CMOVcc reading a later arithmetic result prevents the rewrite.
An IMUL replacement requires an encodable width and scale, and preserves its
source and destination in a two-operand LEA. Other multiplies remain IMUL.
Runtime and emitted-code checks are in
`qualification/optimizer-core/setcc-compare/run_gate.py`; `run_ir_gate.py`
rebuilds the actual compiler peephole and tests its lifetime/operand contract.

## ADDRESSGVN

Tree CSE knows expression values, but the physical address `Data[I]` often arises
only in codegen. ADDRESSGVN operates on the x86-64 instruction stream within an
extended basic block:

1. constructs the identity base + index + scale + displacement;
2. tracks the reaching definitions of every address component;
3. reuses an already computed address only across a safe region;
4. invalidates the fact on a call, ASM, clobber, unknown write, or component
   modification;
5. enables materialization only with enough repetitions.

A write to one element does not automatically make another element's address
stable: the identity of the address and aliasing of data at that address are
distinct. This is what prevents an FFT/array-loop speedup from becoming
stale-address wrong-code.

## Memory in the x86 peephole

The peephole works on instructions, where the types and the names of the
program are gone: an operand is registers, a symbol and an offset. A rule
which moves a read of memory past another instruction, takes a second read
from the register of the first or merges two moves asks one question about
what stands in between: may it write this memory. The answer is "no" only
where that is certain:

- a cell of the frame against data a symbol addresses, and the data of two
  symbols;
- two operands with the same registers and symbol whose offsets and sizes do
  not meet;
- a cell of the frame against anything addressed without the registers of the
  frame, in a routine whose frame no pointer can look at: it takes the address
  of no cell, gives the registers of the frame to nobody, has no handler, no
  implicit `finally`, no assembler block and no allocation on the stack.

Two pointers, a pointer and a variable of the unit, a pointer and a field
behind another pointer are one memory until proven otherwise; a call, a string
instruction and a push write memory nobody names. The moves of one assignment
of a record or a set carry the number of their copy and may be merged among
themselves: the language gives them no order. The moves of two statements are
merged only over memory which is certainly different.

What the order of the statements costs is a read which stays in front of a
store instead of joining the instruction behind it. Two forms show it in
ordinary code: `A^.B^.X := ...; A^.B^.Y := ...` reads `A^.B` again behind the
first store, and an unrolled loop which copies a variable of the unit into a
field cell by cell keeps its moves of 8 bytes. A local copy of the pointer or
one assignment of the whole array gives the shorter code back.

The permanent gate is
`qualification/optimizer-core/memory-order/run_memory_order_gate.py`: generated
programs in which one memory has two names, and the routines in which the
optimization must stay, counted in the -O3 object.

## The operand which the statement names

An x86 instruction takes memory as its operand; a statement which names a
field, an element or a variable of the unit needs no instruction of its own
to fetch it. Where the code generator fetches it all the same, the peephole
optimizer folds the fetch back into the instruction, and whether it can
depends on the registers the allocator happened to give: the fold needs the
register of the address alive up to the instruction and the register of the
value free behind it. These forms do not wait for the fold:

- A subtraction whose operands both lie in memory, the subtrahend behind more
  pointers than the minuend. The operands change their places for the
  evaluation, and the code generator loaded the operand which stood left -
  the subtrahend - into a register of its own. `tx86addnode.second_addordinal`
  puts the operands back: the subtrahend is the operand of the instruction,
  the register takes the minuend. A minuend which is a register variable or
  a constant keeps its three-operand form.
- The element of an array of records whose size is 3, 5 or 9 times 2, 4 or 8:
  the index is multiplied by a LEA and a shift, and the shift goes into the
  scale of the address of the load which follows (`ShlOp2Op`). The rule asked
  whether the register of the index is used behind the load and took it for
  used where the load itself writes it; a load which writes the whole
  register of the index leaves no reader of the shifted value. The register
  may be the base of the address as well as its index, beside no index or an
  index without a scale: the register with the scale is the index then.
- The address of a variable of the unit in a register, the register the base
  of the operands which follow: `lea State(%rip),%rax; mov 584(%rax),%rdx;
  mov %rdx,576(%rax)`. The operands name the variable themselves and the
  register is free (`SymOps2Ops`, for up to eight operands, while none of
  them grows by more than the instruction which loaded the address had; on
  Linux the same for the `movabs` of an absolute address, into operands with
  the absolute address, as the code generator itself addresses a thread
  variable there). An operand which took the symbol of a LEA takes the kind
  of its reference with it (`LeaOp2Op`); without it the operand was not told
  from another name of the same memory, and the memory rules stopped at it.
- An address which is a pointer and a constant, in a register of its own:
  `lea -12(%rax),%rax; orl $2,4(%rax)`. A LEA which adds a constant to its own
  register was made an addition first, and an addition the instruction which
  follows does not take; now it waits for that instruction, which takes the
  address as its operand: `orl $2,-8(%rax)`. A load which reads through the
  address and writes the whole register of the LEA takes it as well.

The permanent gate is
`qualification/optimizer-core/operand-forms/run_operand_forms_gate.py`: the
statements with their values, and the instructions of their routines counted
in the -O3 object.

## The target and the value of an assignment

An assignment is a domain of the common subexpressions: what its target and
its value have in common - the object, the pointer, the index, the address of
the element - is computed once for both sides (`cseinvariant` in `optcse`).
`fItems[Index] := fItems[Index] * 3 + fItems[Index + 1]` computes the address
of the element once; `P^.Next^.Value := P^.Next^.Value * 2 + P^.Next^.Other`
reads `P^.Next` once. The assignment was taken out of the domains on 05.08
because a value read too early met a write through another name; that was
the peephole optimizer moving a read across a write, repaired since (the
memory rules above), and `tests/test/cg/tautoinline3.pp` passes with the
assignment in the domain.

Two pointers to frames are not candidates. The pointer to the frame of the
routine itself is its frame pointer: a copy is a register for nothing. The
pointer to the frame of the routine around comes in a parameter, a register
variable, and the peephole optimizer takes a copy of a register back where
the statement is straight code; a statement with overflow or range checks has
the calls of the checks inside, and a copy alive across them costs a register
the routine has to save. There the parameter is no candidate while it is
expected in a register (a nested routine with exception handling keeps it in
its frame).

What it costs: a temp which lives across a call takes a callee-saved
register, and on the SysV side of x86-64, with five of them, a routine whose
loops hold many values may spill a loop counter or a parameter which was in
a register before. Of the RTL and packages 23 routines on Linux got longer
this way (numlib with `Extended`, `chm`, `graph`) against 250 which got
shorter; on Win64 4 against 243.

## A loop of a method over an array which is a field

The loop over a local dynamic array or a parameter walks a pointer taken
from the variable in front of the loop. The loop over a dynamic array which
is a field of the object (`for k := OrdersHCount - 1 downto 0 do ...
OrdersH[k].Price ...`) read the pointer from the object again before every
element and scaled the index for it. It walks a pointer too now
(`field_vector_base_is_stable` in `optloop`), when

- the object is held by `Self`, a local or a value parameter which the loop
  does not assign and whose address is taken nowhere;
- the body calls nothing, runs no managed helper, and what it writes are
  locals and elements of dynamic arrays (the effect model keeps them apart
  from the fields of an object): nothing in the body can give the field
  another array;
- every iteration evaluates the access before the body has done anything
  which can be told from the outside, and no different operation in its
  expression can raise first: the read of the pointer stands behind the entry test
  of the loop, where the first iteration would do it (an object which is
  `nil` and a loop which does not run reads nothing);
- the pointer pays: the counter is narrower than an address, or the address
  of the element is computed in more than one place. An element of 1, 2, 4
  or 8 bytes at a counter as wide as an address, read in one place, has the
  address as the operand of its instruction and a pointer of its own takes
  nothing off the iteration.

The facts about the body - is it quiet, which accesses come first - are
collected before any access is rewritten: to the effect model an access which
walks a pointer is a store through a pointer, and it would hide the answer
from the accesses behind it. An access equal to one which walks a pointer
already joins that pointer, whatever the other questions say: `Cells[I] :=
Cells[I] + K` stays one instruction, `if Items[I].Time < Limit then
Items[I].Time := 0` writes through the pointer of the read.

The routine gets longer by the read of the pointer and the address of the
first element in front of the loop, and the iteration loses a load of the
pointer and the scaling of the index per access: `ShapeLoopMaxPrice` of the
operand-forms gate goes from 26 instructions with 20 in the loop to 23 with
12. For a loop of one or two iterations that is a loss, for a longer one a
gain; so it is for the local arrays which walked a pointer before. A loop in
a routine with `try` is not touched: the loop optimizations need the data
flow analysis, which such a routine does not build.

`qualification/optimizer-core/operand-forms` holds the shapes;
`RTL-test/semantic/field_walk_semantic.dpr` the values with the array
replaced by an assignment, by `SetLength`, by a called method, through a
second reference to the object and through a pointer to the field, and the
order of division by zero before a field read of a `nil` object.

## Register allocation and exception regions

The old defensive scheme could demote registers for an entire function when it
contained `try`. MoonCompiler keeps registers in ordinary code and creates a
memory home only for values that actually live across an exception boundary or
are needed by an exception handler or `finally`.

The solution is checked at two levels:

- frontend/mid-end marks values that cross the boundary;
- backend checks liveness, clobbers, and ABI before final assignment.

A routine with a nested routine of its own - a nested procedure or an
anonymous function - is analysed like any other. What the nested routine
reads or writes of its parent is known when it is parsed and has its home in
the frame or in the capturer; what it raises reaches the handlers of the
parent as the exception of any other callee does. Until 2026-09-29 such a
routine kept every local and parameter in the frame: the loop of a method with
a `try..except` around its body and an anonymous comparer for a sort loaded
and stored its counters and sums in every iteration.
`qualification/optimizer-core/try-nested` holds the values and the shapes.

A local declared where it is used - `for var I := ...`, `var T := ...` in the
body of a loop or of a branch - is a local of its routine and gets its
register like one declared in front of the body. Until 2026-09-29 only the
symbols of the routine's own tables of locals and parameters did; the local of
a block lived in the frame, the counter of every `for var` loop with it.
What keeps a local out of a register - a taken address, a nested routine or an
anonymous function which reaches it, a handler or a `finally` block which
reads it - asks the symbol and holds for it as it stands.
`qualification/optimizer-core/block-locals` holds the values and the shapes.

For FP loops, live ranges are shortened only in proven forms. A managed value is
not retained for CSE if retaining it adds a refcount, spill, or extends its
lifetime. A dynamic-array base after LICM is reused only while the array
variable, length/data pointer, and reachable alias chain remain unchanged.

## What a call does to a local

A local whose address is not taken and which no anonymous function captures
changes during a call only if code runs which names it: a routine nested in
the routine whose local it is, on the frame of the same activation. Such a
routine is entered by its name, from the routines which see it, or by its
address, from anywhere.

What every routine writes of the routines around it, which routines of a
nesting level it calls and which it knows by address is read from its tree as
parsed, before the first routine of the family is compiled
(`collect_nested_access` in `optloop`). The tree of a routine is released once
its code is generated, so the routines compiled behind it ask the summary; an
outlined `finally` body is read when it comes to life. A routine with an
assembler block makes every call a barrier.

The loop over a local dynamic array or string, which walks a pointer taken
from the variable in front of the loop, is the consumer: a call in the body is
a barrier if it calls by name a routine which writes the variable, or calls
one that does, and any call is a barrier if such a routine is known by its
address. The loop of a nested routine over the array of the routine around it
is answered from the owner of the array, the same way.
`qualification/optimizer-core/nested-local` holds the values and the shapes.

## The fields of a local record in a loop

The fields of a local record which a loop reads and writes live in temps, so
in registers, while the loop runs: they are loaded in front of the loop and
stored back behind it. A field in a temp is a store put off until the loop is
left by its end, so a field stays in the record if somebody looks at the
record before that (`drop_observed_fields` in `optloop`):

- a handler or a `finally` block of a `try` statement the loop stands in
  reads it, or the code a `try..except` goes on with does, and the loop can
  raise an exception (the effect model says whether it can) or, for a
  `finally` block, has an `Exit`;
- a `finally` block inside the loop which was outlined into a routine of its
  own (Win64) reads or writes it: that routine works on the frame;
- a `goto` leaves the loop, or a label of the loop is entered from outside.

It is the rule a local variable has in a routine with `try`, asked for every
field, for the `try` statements around the loop only, and only of a loop which
can be left that way. A handler, and on Linux a `finally` block, inside the
loop is part of the loop and reads the temps.
For a `try..except`, reads before the try do not observe a loop interrupted by
an exception. The continuation scan follows the tails of enclosing statement
lists; if an outer loop or `goto` can revisit earlier statements, it scans the
whole routine conservatively.
An implicit call to a local record's custom `Finalize` also observes its
fields if an exception or `Exit` skips the store after the loop. Only fields
written by such a loop stay in the record; a loop with no abrupt exit still
keeps them in registers.

A field the loop only writes stays in the record when the loop calls: in the
record every write is one store where it stands, in a temp the field holds a
register a call saves for the whole loop, which a variable of the loop or
`Self` would otherwise have. The loop of fcl-xml's `ParseMarkupDecl` writes a
location record in a rare branch and reads it behind the loop; with its two
fields in `r13` and `r14` for the whole loop, SysV's five callee-saved
registers were not enough and `Self` went to the frame, read back at every
call (196 instructions and 48 memory accesses became 214 and 90). The temps
of the inliner in that loop used to count against the budget of the fields
(`RECORD_TEMP_LIMIT` less the temp references of the loop) and hid the cost;
a budget of callee-saved registers instead of 7 was tried and took registers
from accumulators that fit (three shapes of the gate on Linux).
`ShapeCallsBudget` of the gate is that loop: 59 instructions before, 52 with
the rule, on Win64 and Linux.

`qualification/optimizer-core/record-fields` holds the values and the shapes.

## By-reference actuals of an inlined call

A `var`/`out`/`constref` actual that is more than a plain variable is
normally bound once: the inliner takes its address into a temp in front of
the body, so the body cannot move the location it writes to. That temp
lives across every call the body makes and takes a callee-saved register
for it. With `GetMem(Pointers[J], Size)` inlined (the RTL at `-O3`) the
SysV side of x86-64, which has five such registers against seven on Win64,
spilled the loop's accumulator to the stack: the allocation ring of Pulse
cost 46.3 ticks per pair on a Xeon W-2295 against 41.6 with the RTL at
`-O2`.

An element of a static array in the frame (or in a static variable),
selected by constants and by register variables of the calling routine,
cannot move: nothing the body can reach writes to a register variable of
the caller - its address was never taken and no nested routine sees it.
When the formal occurs exactly once, such an actual is substituted as it
stands (no range check in it, an element the addressing mode scales or a
constant index), the store comes out as one instruction after the call, and
the ring is back at 41.7. When the body uses the formal more than once, its
address is still materialized once: duplicating indexed address formation at
every use enlarged ChaCha's inlined quarter round and made its hot block 15%
slower. The
two ways in which the body itself could still assign such a variable are
excluded: the same variable as another assignable actual of the call, and
as the destination that receives the function result directly.
`qualification/suite/tests/smoke/inline_var_element_actual.pas` compares
both the one-use and repeated-use forms with twins that are really called.

## Reusing large integer constants

The x86-64 post-register-allocation pass can share a large constant between
nearby two-operand integer multiplications. It uses an otherwise free volatile
register across the entire interval. Calls, control-flow and exception
boundaries, inline assembly, conflicting uses, and register pressure stop the
transformation; no spills or nonvolatile saves are introduced. The rule does
not depend on a record size, function name, or a particular constant.

Two, three, or four repeated materializations save 10, 20, or 30 bytes in the
tested leaf producers. Fewer instructions do not guarantee that every caller
gets faster. A compiled batch producing four keys for each independent ID
improved by about 7% on Win64 and Linux. A Win64 dependent chain
`State := Combine(MakeKeys(State))` slowed by about 6–6.5%; the same Linux
consumer improved by about 5%. A one-result `State := Mix(State)` with only one
materialization is unchanged. The policy favors compact producers of multiple
independent results; the measured dependent-chain cost remains a trade-off.

Preserving the first multiply's old operand register, or adding padding to
imitate a favorable code shape, performed worse on those compiled consumers.
The pass therefore adds neither benchmark-specific padding nor call-site
rewrites. Interprocedural scheduling remains separate research.

`qualification/optimizer-core/imm64/run_gate.py` checks O-/O2/O3 against an
independent integer oracle, including overflow, aliasing, calls, branches,
exceptions, narrow writes, pressure, and inline assembly. Linked-code checks
require sharing in the positive cases and retain the inline-assembly barrier.

## Code placement

`CODEALIGN` aligns proven hot loop labels without padding in an executed
fall-through path. The solution is limited to x86-64, accounts for loop size,
and does not turn every label into an aligned target: additional code size and
crossing a cache/uop boundary can cost more than the misalignment itself.

The placement described below is a draft and is off by default: code keeps
the plain `CODEALIGN` alignment - procedure entries, loop heads and explicit
Pascal labels on 32 bytes (an explicit wider `{$CODEALIGN}` value is kept) -
and the jump sizes of the assembler's single sizing pass.  Hand-laid
routines carry what the draft used to give them - the entry on a 64-byte line
and the short forms of forward jumps across an alignment - in their own
source (`doc/ASM_LAYOUT_RULES.md`, rule 1 and "Short jumps forward are
decided once"), so their bytes are the same with the draft and without it.
On the placement stand of 2026-09-27 (38 code shapes, seven CPUs)
every rule tried that moves code away from that alignment was slower on some
shape on some CPU; the verdict is in
`doc-int/performance/ENGINE_PLAN_20260927.md`.
`MOONCOMPILER_PLACEMENT=1` in the environment switches the draft on;
`MOONCOMPILER_NO_PLACEMENT=1`, the earlier off switch of the stand series and
scripts, keeps it off in any case.

With `CODEALIGN` and the draft switched on the internal x86-64 assembler
places code by the sizes it measures in its own layout passes (the code
generator only marks what an alignment is for):

- every `jmp`, `jcc`, `call` and `ret` (and a macro-fused ALU+`jcc` pair)
  neither crosses nor ends on a 32-byte boundary. The pad bytes go as DS
  override prefixes (`3E`, ignored in long mode, no uop) onto the
  instructions of the branch's own basic block, nearest first and at most
  three per instruction; not onto branches, prefix opcodes, VEX/EVEX
  encodings or the F2/F3-mapped bit instructions. A call does not end
  the block: it returns to it, so the prefixes may go in front of the
  call as long as the call, moved by them, still keeps to the rule
  (`call; test; jcc` and the join after a call used to get nops). Only
  what the block cannot carry stays a nop, and pads in never-executed space (after an
  unconditional jump or return) or in front of a loop head (off the loop's
  path) stay nops on purpose. Every instruction remembers which pad put
  its prefixes there: a pad that shrinks in a later layout pass takes its
  own prefixes back wherever they sit, also behind a forward jump its
  smaller window no longer looks through (prefixes left there were code
  the loop executed and bytes it had to find room for: a 44-byte loop
  grew to 47, no longer fitted its line from its natural place and moved
  a line down behind 48 nops). Short jumps that the pads push out of range
  are re-encoded as near. `-vd` reports the split (`pad bytes as prefixes
  N, as nops M (dead D)`). Nothing is put inside a hand-written `asm`
  block, neither nops nor prefixes: such a block may be length-sensitive
  in ways the assembler cannot see (mORMot copies its replacement string
  routines over the RTL's with hard-coded lengths, and one pad behind a
  tail jump cut a return off the copy), so the author lays it out
  entirely; only the entry of the routine is placed, in front of it.
  Pads whose prefixes reach in front of other branches move each other,
  so a pad that has changed eight times is kept (every pad, once an
  object reaches 64 layout passes) - but what is kept is its prefixes,
  not the branch's fate: the code in front goes on settling, and a kept
  byte count left 25 branches of the Win64 RTL on a boundary (the first
  compare of UnicodeCompareStr's loop with one prefix of the four it
  needed).  A kept pad now corrects itself with nops directly in front
  of its pair: they move nothing in front of it, so every kept pad
  depends on the code before it only and one pass settles them all.  A
  kept loop alignment keeps the byte of the line its head stood on, not
  its fill size, for the same reason.  What a pad cannot put on the
  instructions of its block as prefixes is nops, and they stand in front
  of the jump target the block starts with, not between that target and
  the pair: there only the path that falls into the target executes them,
  every jump into the block skips them, and behind a jump or return
  nothing does.  Between the label and the pair every path paid for them:
  the back-edge block of the UTF-8 encoder's loop (`L: add; cmp; ja`, `L`
  reached from every case) executed six bytes of nops behind its `add` in
  every iteration.  In the Win64 Pulse program 139 nop pads stood behind
  a jump target this way, 47 of them inside loops.  Behind an aligned
  target - a loop head, an entry - the pad stays in front of the pair:
  the alignment would swallow it.  The fused pair is found through
  a label between the ALU instruction and the jump, and through the
  (empty) target pad node the assembler puts in front of such a label:
  the carry trick of a set test with ranges (`stc; je L; sub; cmp; L:
  jae`) has its jump target exactly there, and its `cmp`+`jae` used to
  be judged as a lone `jae` (TValue.AsSingle).  Compiled code of the RTL
  and of the Pulse program now has no branch on a boundary (38 before);
  the stand chain asserts it (`compiled code rule 4 gate`), the
  placement fixture carries sixteen such set tests;
- a loop (head label to the end of its farthest backward jump) is placed by
  its length, following the loop maps measured on Zen 3 and Cascade Lake
  (`doc-int/experiments/tiny-loop-map/`) and judged on the stand: at most
  64 bytes lies inside one 64-byte line with its back-edge not ending on
  byte 29-31 or 62-63 of the line (63/64-byte loops have no such position
  and stay inside the line); a longer loop starts on byte 0, 16 or 32 of
  a line (a 16-byte boundary in the first half: never in the tail of a
  line, where the end-of-line target of the old `CODEALIGN` put the head
  of a loop just over a line, and inside the fast head zones of both
  maps; the end zone measured on one 66-byte loop did not transfer to
  other lengths), on the one from which it touches the fewest 64-byte
  lines (from byte 32 a loop of 97..128 bytes touches three lines instead
  of two; Pos and UTF8Encode lost 6-8% that way) and, among those, with
  the least fill in front of the head, because that fill is executed on
  every entry (CompareText on one-character strings lost 9% to 55 bytes
  of fill).
  The fill of a short loop is chosen by simulating the loop body for every
  candidate, because the branch pads inside depend on where the loop lies;
  a loop that contains another loop keeps only its prefix inside a line;
- every procedure starts on a 64-byte line (a longer procedure used to
  start on 32 bytes, which left a hand-written routine on byte 0 or 32 of
  a line as the linker placed it, and its body, laid out by its author
  from the entry, moved by half a line between links); every section with
  placed code is therefore 64-byte aligned;
- every label a jump reaches is kept out of the last 12 bytes of its
  64-byte line (a taken branch into the tail of a line gets a shortened
  fetch block; the UTF-8, Format and Val loops lost 11-22% when the first
  rules dropped every target alignment): the assembler gives such a label
  a target pad of up to 12 bytes, decided every layout pass, but only
  when the basic block in front carries all of it as prefixes (three per
  ordinary instruction) or nothing executes the place (after a jump or
  return, where the pad is nops).  A target pad realized as nops in the
  path cost more than it gained (TList.Exchange and CompareText loops,
  whose blocks are a call and a test).  A label inside a loop that lies
  in one line, or inside a procedure whose own bytes fit one line, gets
  no target pad: the line is fetched whole anyway, and such a pad only
  pushed the loop or the leaf out of its line (48 bytes of nops in front
  of the incr_ref_many loop, a 61-byte leaf on two lines: managed
  copies 19% slower).  The code generator's jump-target
  alignments are taken over the same way, its empty 1-byte alignments in
  front of join labels are looked through; alignment directives inside
  hand-written `asm` blocks are kept as written.
  The target pad and the branch pad of the block behind the target decide
  together.  The nops of that branch pad stand in front of the label, so
  taken apart the two fought: the branch pad pushed the label into the
  last 12 bytes, the target pad moved label and branch to the next line,
  where the branch needed no pad, the label fell back, and after eight
  changes the limit froze both wherever they were (targets in the last 12
  bytes of a line in the Win64 Pulse program: 24 before the branch pads
  went in front of their labels, 54 after; the back-edge block of
  `UnicodeToUtf8Buffer`'s loop on byte 57, across its line, where the
  `-O2` RTL has it on bytes 0..12).  The target pad is therefore decided
  from the natural place of the label - without the nops of a branch pad
  in front of it - and for the whole short block the label starts (up to
  32 bytes, to its first branch, with the pad that branch needs from
  there): when the block would end behind the line, or the branch pad's
  nops would push the label into the last 12 bytes, the label goes to the
  start of the next line, under the same condition as before (prefixes on
  the block in front, or dead space).  `TEncoding.GetBytes` of 32
  characters: 239.6 -> 213.5 ticks on the Ryzen, faster than with the
  `-O2` RTL (219).
  Pads do not touch each other's prefixes: an instruction that carries
  the prefixes of one pad is not a carrier of another, and the window of
  a pad does not reach in front of a branch that has a pad of its own.
  The window of a target pad reaches through a forward jump into the block
  of that jump, and the jump's own pad - first in every pass, zero or not
  - set the prefixes of its block again and wiped the target pad's; the
  label fell back, the target pad asked for more each pass (5, 7, 9) until
  the block could not carry it, dropped to zero, and the cycle started
  over: 13 layout passes for `CompareText`, then a frozen pad with 3 of
  its 5 bytes and a target of the 16-bit loop on byte 62 - with every
  compiler of the stand before this one.  It settles in 6 passes now
  (Xeon: `sametext-mismatch-last-12` 23.5 -> 19.9 ns, `containstext-miss`
  171.6 -> 148.9).  A target pad in dead space is never kept by the change
  limit: it moves nothing in front of itself.  The whole Win64 Pulse
  program - compiled and hand-written code - has no jump target of a loop
  in the last 12 bytes of a line that the block in front could have moved
  (5 before the branch pads went in front of their labels, 18 after); the
  Linux program has two, one code shape in `TStringHelper.Split` for
  `UnicodeString` and `WideString`, whose pad reached the change limit in
  the state that leaves the label on byte 59 (7 and 35 before).  Both stand
  chains assert the rule next to rule 4, Linux with that ceiling.  Three
  ways to reach zero there were measured and none is worth its price: with
  no limit at all the RTL's biggest unit needs 63 of the 64 allowed
  relaxation passes instead of 15 (a pad's own prefixes move the code in
  front of it, whose branch pads correct themselves, which moves the pad's
  label again); keeping the decision without the block rule oscillates to
  the pass limit on the placement fixture; and not keeping a pad in that
  one state - eight more attempts for it - does reach zero on both systems,
  but the acceptance gate of the stand then flags cases on both machines
  (Win64 `stringbuilder-replace` 1.109, `object-create-free-plain` 1.060,
  `variant-vartostr-int` 1.061; Linux `random-double` 1.060) at a geomean
  of 1.0002 and 0.9983, and a cold routine's target is not worth that.  The
  placement fixture carries the `CompareText` loops.

Hand-written assembler is placed by its author under the same rules:
see `doc/ASM_LAYOUT_RULES.md` for the rules, the tools that check them
and the maps that place a new routine.

The rules live in the internal assembler only. When `-a<x>` (any listing
option except `-ap` and `-a-`), `-s` or `-A<external>` selects a
source-writing assembler, the compiler warns that the object is not the one
its internal assembler writes (message 11072); the gates that
inspect assembler listings use that mode on purpose, and the product
configuration is kept free of such options by
`qualification/build-driver/config_contract_gate.py`.

The gates of the draft are
`qualification/optimizer-core/placement/run_branch_pad_gate.py` and
`qualification/performance/tools/check_placement_rules.py` (they judge code
built with `MOONCOMPILER_PLACEMENT=1`); the reasons and measurements behind
its rules are in
`doc-int/history/rtl-profile-20260914_18/RTL_PROFILE_STAND_20260914.md`.

Peephole and machine facts additionally preserve exact register definitions,
integer-operation widths, flags, and memory clobbers. These facts are part of
correctness: an incorrect fact about `ADD/LEA`, `CMOV`, or a narrow load breaks
CSE and RA, rather than merely missing speed.

## Pass order

In simplified form, the pipeline is:

1. inlining, constant propagation, and loop canonicalization;
2. LICM and reuse of a stable array base;
3. effect-aware tree CSE and load/modify/store transforms;
4. lowering to target instructions;
5. ADDRESSGVN, machine facts, and register allocation;
6. peephole, code placement, and alignment.

The order matters: an early pass cannot rely on machine identity, and a late
one cannot recover a lost managed lifetime or exception edge.

## Measured impact

Each mechanism was accepted with its own buyer and negative controls:

| Mechanism | Demonstrating form | Result after the fix |
|---|---|---:|
| ADDRESSGVN | repeated addresses in `SweepBook` | about `1.8%` faster |
| EH register allocation | byte scan inside an exception region | about `6%` faster |
| FP loop liveness | `AggregateMarkets` | about `37%` faster |
| Managed CSE profitability | `CorrelationDigest` | about `3%` faster |
| Dynamic-array base reuse | `CorrelationDigest` | another `1.2%` faster |

This attributes performance locally to the mechanisms; it is not a sum of the
product's overall speedup. The final mixed compiler + RTL + MM result is in
[Performance](PERFORMANCE_QUALIFICATION.md).

## How correctness is proven

- focused tests for stale globals, nested captures, calls, ASM, aliases, and
  traps;
- Debug/O2/O3 equality and PPU replay;
- Win64 SEH and Linux PSABI exception/lifetime paths;
- Devil/Omni combinations and deterministic-artifact checks;
- disassembly gates that require the specific redundant work to disappear;
- Pulse buyers and neighbouring workloads, so a speedup is not bought with a
  broader regression.

On Win64, a small implicit cleanup runs its release helpers directly on the
normal return while the cold SEH `_fin$` helper remains for exceptions. This
duplicates some static instructions across the parent and finalizer but removes
an executed outlined call on the normal path. The affected shape gates check
both paths explicitly alongside their existing ownership, loop and memory
guards; their updated total counts do not justify restoring the extra call.

The current boundaries are deliberate: cheap arithmetic is hoisted only when it
does not increase register pressure, FP fallback stays local to the affected
operation, and addresses are cached only with precise clobber and alias
knowledge.

More aggressive optimizer ideas remain engineering research, not known defects
or promises of the current product.

## Static addresses in read-only inner loops

The x86-64 post-allocation pass can move one RIP-relative LEA before an inner
loop when its physical register is free throughout the complete extended
lifetime and serves at least two useful memory reads. It preserves every
consumer and memory-operation order. One entrance and one backedge are required;
calls, side entries, ASM, exception regions, memory writes and implicit stack
changes keep the previous schedule. No register spill, new frame, operand
rewrite or general placement-policy change is introduced.

Four independent FP accumulators improved by about 24–25% on the measured
Win64 placements. Two/four/eight/sixteen-trip neighbors were checked separately;
write, alias, histogram, matrix and pressure controls keep their old instruction
shapes. Ordinary Linux globals already use direct addressing or a hoisted GOT
base, so this rule leaves those paths unchanged. Native Linux PIC anonymous
static data provides a separate positive control.

The [focused gate](../qualification/optimizer-core/loop-address/README.md) checks
the emitted LEA and independent semantic oracles. The broader read/write rule
remains research: its interaction with loop padding introduced an alias-path
cost despite helping nonalias writes. See [Backlog](BACKLOG.md#address-hoisting-in-loops-with-writes).

## Spilled values across call-free loops

A value the register allocator spills goes through its frame slot at every
use. Inside a loop without calls a register can hold it across the whole loop:
nothing the loop runs clobbers the volatile registers. Code generation marks
the outermost call-free loop as a loop region - a loop without a call
(including the helpers pass 2 calls without a call node: runtime checks,
managed temps, threadvar access, heaptrc pointer checks), `Exit`, ASM or a goto
label; a call-free loop inside a region is part of it. When the allocator
spills an integer value which the region accesses, the spilling code loads it
into a register of its own before the region, the region accesses that
register, and a store after the region writes it back when the region writes
the value and the value is live after the region; a value the region only
reads is only loaded. Values the allocator keeps in registers are not touched,
so a region without spilled values keeps its code byte for byte.

The region registers take the usable registers the region leaves free where
the most values are live, but two, the most accessed values first; a value
refused one keeps the per-use spilling. Both registers left free are needed.
Filled to the full pressure, a region made the colouring spill another value
the old code kept in a register (numlib and pasjpeg routines of the packages).
With one left free, a region register, which lives over the whole region, got
a callee-saved register because the temporaries of the region use every
volatile one at some point, and a pointer living across a call of the routine
found no callee-saved register left (numlib `ortpol` on SysV).
An access counts only when it may run again: the load and the store are paid
on every entry into the region, and an access after which the path jumps
unconditionally past the last backward jump of the region, like a flag written
just before `break`, runs at most once per entry, so a value accessed only so
keeps its slot.
Only the spilling after the first colouring gives
region registers: a value spilled by a later colouring was spilled for the
pressure left after the first spilling, and a region register would bring that
pressure back, round after round. The load stands before the
synchronisation of the loop and before the jump to the condition of a loop
tested at its beginning, so a zero-trip entry runs it as well, like the read
of the slot the condition makes without the region. The store stands after the
break label, which every exit passes. A value observed on an exceptional path,
in a handler or after a `try`, is never a register variable on x86-64, so an
exception leaving the region finds no value only in a region register. In the
request loop of the heartbeat on SysV, with five callee-saved registers, the
byte pointer, the hash and the record pointer are spilled; its byte loop keeps
all three in volatile registers.

Debug information describes one location per variable: the register it has at
the end of code generation, without location lists. At `-O2`/`-O3` the location
of a register variable is exact only while the variable keeps one register for
the whole routine; after the SSA register change of an assignment the debugger
sees the last register, for a spilled variable a register it does not live in.
Inside a loop region the value of a spilled variable is in the region register
and its slot is stale until the store after the region. The debug profile
compiles at `-O-`, which keeps variables in memory.

When both operands of an ordinal compare inside a loop are in memory, the one
which does not depend on a variable the loop writes is loaded into the
register, and the loop-dependent one, whose address is known last, stays the
memory operand of `cmp`; `nf_swapped` mirrors the condition. Instructions and
widths are unchanged.

The [focused gate](../qualification/optimizer-core/loop-regvar/README.md) checks
both shapes against independent semantic digests.

## Float constants in registers

A float constant which a procedure reads more than once lives in a register
temp from the entry (`do_consttovar`): one load, then register operands. A
common subexpression temp holding a real constant is the same kind of value.
Code generation marks the register when it loads a real constant into an
immutable temp (`set_reg_constant_load`); the allocator keeps the mark when the
first instruction of the register, to which its allocation is bound, is that
load from an address without registers (rip-relative or absolute) and nothing
else writes the register, and gives it the constant's memory as its initial
location, like a parameter in the stack.

- Spilled, such a register takes no stack slot: the load goes and every use
  reads the constant's memory, as an operand of the instruction where x86
  allows one. The old spill stored the loaded constant to a slot and read the
  slot instead.
- When a colouring leaves values that are not constants without a register,
  each of them may take a colour which, among its neighbours, only constant
  loads hold; those go to their memory. It is done only when the reads of the
  constants, by execution weight, cost less than the loads and stores of the
  value (an instruction that reads and writes it counts twice: a spilled
  accumulator is loaded and stored on every turn), for every such value of the
  round or for none, and when the memory of every spilled constant replaces
  each of its uses without a helper register - checked with the target's own
  replacement on a copy of the instruction. The colouring then stays complete
  and no spilling round follows: a variable of a loop keeps its register
  rather than a constant needed only after the loop, and a constant read on
  every turn keeps its register against a value the loop barely touches.
- When a round spills constant loads only - by the colouring itself or after
  the substitution - and their memory replaces every use, the colouring of the
  round is complete for the code as it is then. The allocator colours that code
  three more ways - afresh, as the next round would; with the moves the
  colouring gave up under the pressure of the constants given back; and from
  the start, graph and coalescing rebuilt without them - and keeps the
  cheapest complete colouring: the register moves it leaves, by execution
  weight, and 200 for each callee-saved register it uses (xmm6-xmm15 on Win64:
  a save and a restore).
- A register which Win64 saves at the entry and restores at the exit
  (xmm6-xmm15) and which only constant loads hold in the final colouring is
  given up when the reads of those constants cost less than the save and the
  restore and their memory replaces every use: the constants are read from
  memory, the register is not used, and the other colours stay.
- Where registers suffice, nothing changes: no spill, no substitution, the
  colouring the allocator had before.

The memory of a constant is read-only. A register coalesced into a constant
register may be written, so the coalesced group loses the mark and is spilled
like any other; two spilled values may share a slot, but never a constant's
memory; a spilled constant register that an instruction writes stops the
compiler with an internal error.

The [focused gate](../qualification/optimizer-core/const-register/README.md)
checks the forms with and without expanded calls.

## A read of memory whose value a register holds

After `mov %reg1,mem` or `mov mem,%reg1` the register holds what the memory
holds, until something writes that memory, the register or a register of the
address. The peephole optimizer gave a later read of the memory the register
only when the two instructions stood next to each other (`MovMov2MovMov1`,
`MovMov2MovMov2`): any instruction in between kept the read - an argument
register loaded with a constant between the two reads of a global object that
a virtual call needs as `Self` and for its table of methods, or the address
arithmetic of the next statement between the store of an element and its use
as an operand.

`ForwardMemoryValue` (`compiler/x86/aoptx86.pas`) looks past the next
instruction, up to eight instructions, over plain integer instructions whose
memory operand, if they have one, is only read: `mov`, `movzx`, `movsx`,
`movsxd` into a register, `lea`, integer arithmetic and logic with a register
destination, `cmp`, `test`, `setcc`, `cmovcc` - and over conditional jumps:
the instruction behind one is reached from it only by falling through, with
the same memory and registers. None of them may change the register or a
register of the address; a store, a call, an unconditional jump, a label or
any other instruction ends the look. Volatile memory operands also end the look,
even when reading another address: the volatile view is a barrier, so a later
ordinary access must still execute. The read takes the register:
`mov mem,%reg2` becomes `mov %reg1,%reg2`, and `add`, `sub`, `adc`, `sbb`,
`and`, `or`, `xor`, two-operand `imul`, `cmp` and `test` read the register in
place of the memory. Only 32- and 64-bit operands are forwarded, and the next
instruction is left to the rules of a neighbouring pair.

No memory is reasoned about: nothing in between writes any memory, so no alias
question arises, and another thread sees the same as when the two accesses
stand next to each other.

After a load the register must be in use behind the second read anyway. Where
it dies earlier, the neighbouring rules fold the load into its only reader
(`add (mem),%reg`) and the second read into its own; forwarding would keep the
register alive for a value nobody else needs, and a load and two register
instructions would replace two instructions with a memory operand - one read
fewer, one instruction more. A read whose register the next instruction
stores back to the same memory is left to `MovMov2Mov 1` as well, which
removes the store and, where the register dies, the read: a parameter and the
local copy of it sharing one frame cell (`SDBM` of `generics.hashes`) got a
second store of the same value otherwise.

A compare and its repeat behind a conditional jump both read the register,
and the repeat goes. `CMP/Jcc/CMP` removed the repeat of a compare of memory;
once the first compare reads a register, `OptPass1Cmp` turns it into
`test %reg,%reg`, and `OptPass1Test` removed a repeated `test` only when a
conditional jump followed it. It now removes it whatever reads the flags
(`TEST/Jcc/TEST`, `cmp $0,%reg` behind `test %reg,%reg` included). The form is
`Assigned(Value) and (Value is TClass)` over a local of the frame - fcl-pdf's
`TPDFDocument.GetPageNode`, where the first compare went to the register and
the repeat did not: one instruction more than without the forwarding.

In the Win64 images of the 25 Pulse programs with two product analogues and of
`mormot2tests`, 1424 and 1764 functions change on `637933feb`, every one with
fewer memory accesses (49002 to 47351 and 161639 to 158820 over the changed
functions) and none longer; passing the conditional jump changes 380 and 764
more on the tree merged with main `e3017da29`, again every one with fewer
memory accesses (17212 to 16616, 81126 to 79249) and none longer.

The [focused gate](../qualification/optimizer-core/value-in-register/README.md)
counts `StoreThenAdd` in the -O3 object - the element stored is an operand of
the next statement's arithmetic - and `KidAt`, the compare and its repeat.
