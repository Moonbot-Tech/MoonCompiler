# A call and the locals a nested routine writes

```text
python qualification/optimizer-core/nested-local/run_nested_local_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

A loop over a local dynamic array or string walks a pointer taken from the
variable once, in front of the loop. That holds while nothing in the body gives
the variable a new value (`compiler/optloop.pas`,
`implicit_array_base_is_loop_invariant`). Until 2026-09-29 a call was taken to
be harmless for every local whose address is not taken and which no anonymous
function captures. A routine nested in the owner of the local names it without
either: `L := B` or `SetLength(L, N)` in a nested procedure called from the
loop left the loop reading the old array, a character written by a nested
procedure was not seen in the string.

A local changes during a call only if code runs which names it: a routine
nested in the routine whose local it is, on the frame of the same activation.
What each routine writes, which routines of a nesting level it calls and which
it knows by address is read from its tree as parsed, before the first routine
of the family is compiled (`collect_nested_access`). A call is a barrier when
it calls by name a routine which writes the local or calls one that does; any
call is a barrier if such a routine is known by its address. The question is
asked from the owner of the local, so the loop of a nested routine over the
array of the routine around it gets the same answer as the loop of the owner.
An outlined `finally` body is read when it comes to life. A routine with an
assembler block, or one whose tree was not read, makes every call a barrier.
An anonymous function cannot call a nested routine: the compiler refuses the
program, as Delphi 12.2 does.

`nested_local.dpr` is both halves of the proof.

Its `Check` calls are the semantic matrix. The write: the array assigned, its
length set, passed by reference; the string replaced, a character written,
`Delete`, `Insert`, `SetLength`. The way to it: the nested routine called from
the loop, through another nested routine, two levels deep, through its address
(FPC only: Delphi has no procedural type for a nested routine), from the
cleanup of a nested routine with and without an exception, from a cleanup and
from a handler inside the loop. The loop: of the owner; of a nested routine
which calls a routine beside it, its own nested routine, itself. Elements of
four bytes and records of forty. The gate builds the file at `-O1`, `-O2`,
`-O3` and `-O4` without checks and at `-O3` with range and overflow checks,
and runs each program. Delphi 12.2 compiles the same file and prints the same
line.

Its shapes are counted in the `-O3` object, so that the repair takes the
pointer from no loop which may have it:

- the array is walked by a pointer in the loops of `NestedReads` (the nested
  routine called from the loop only reads the array), `NestedWritesOther` (it
  writes another array), `ShapeNestedReads`, `ShapeNestedWritesElsewhere` (a
  nested routine writes the array and is not called from the loop),
  `ShapeAddressOfReader` (the address of a nested routine which only reads is
  known, another one writes), `WalkOfNested` and `WalkOfNestedPlain` (the loop
  of a nested routine over the array of the routine around it);
- the loops of the routines with nested ones have the instruction count of
  the loop of `ShapePlain`, the loop of `WalkOfNested` that of
  `WalkOfNestedPlain`;
- instructions without padding, calls and the length of the loop of every
  counted routine, together with its outlined finalizers, against
  `reference.json` of the target: a routine that grew is red; one that shrank
  is reported, and `--record` writes the new counts on purpose.

Negative controls, shown on 2026-09-29 on Win64 and on Linux:

- the compiler before the repair fails 17 values at `-O3`: every form where a
  nested routine is on the way to the write;
- a compiler which makes every call a barrier for the local of a routine
  around (the first version of the repair) fails the shapes: the loops of
  `WalkOfNested`, `WalkOfNestedPlain` and `ShapeAddressOfReader` multiply the
  index again. Six nested routines of the RTL and packages and four of mORMot
  lost the pointer the same way;
- a compiler which makes every call a barrier for a local a nested routine
  names fails the shapes of six routines.
