# A local declared in a block lives in a register

```text
python qualification/optimizer-core/block-locals/run_block_locals_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

A variable declared where it is used - `for var I := ...`, `for var V in ...`,
`var T := ...` in the body of a loop or of a branch - is a local of its
routine, kept in a symbol table of the block. Until 2026-09-29 the register
was given to the symbols of the table of locals and of the table of parameters
only (`compiler/symsym.pas`, `tabstractvarsym.setregable`), so such a variable
lived in the frame: the counter of a `for var` loop was `add DWORD PTR
[rsp],1 ... cmp ecx,DWORD PTR [rsp]` in every iteration, a sum declared in the
block was read, added to and written back. A variable declared in place at the
top level of the body goes to the table of locals and had its register. A
trading program written in this style, where `for var` is the usual loop,
paid that in every loop.

Everything that keeps a local out of a register asks the symbol, not its
table, and holds for a local of a block as it stands: a taken address, a
nested routine or an anonymous function which reaches it, a handler or a
`finally` block which reads it (`mark_seh_memory_syms`), a type which does not
fit a register.

`block_locals.dpr` is both halves of the proof.

Its `Check` calls are the semantic matrix: counters and sums declared where
they are used, in nested blocks, in the body of a loop, in the branches of a
`case`, with the same name in two blocks; a value an anonymous function
captures, a value whose address is taken, a value a handler or a cleanup
reads, around the loop and inside it, a value declared in a handler and in a
cleanup, a value assigned in a `try` block and read behind it; integer values
of every width, floating point, Boolean, character, enumeration, set, pointer,
record and string values; twelve locals at once; `for`-`in` over an array and
a string; `Exit`, `Break` and `Continue`, `Exit` through a cleanup; methods, a
nested routine, a generic routine, a routine the compiler puts into its caller
and its actual by reference, recursion; the pointer of a `with` statement.
Every callee overwrites all volatile registers of the target. The gate builds
the file at `-O1`, `-O2`, `-O3` and `-O4` without checks and at `-O3` with
range and overflow checks, and runs each program. Delphi 12.2 compiles the
same file and prints the same line.

Its shapes are counted in the `-O3` object:

- the innermost loop of `ShapeBlockLoop`, `ShapeBlockDouble`, `TBook.Sum` and
  `TBook.Levels` (bodies of routines of a trading program) reads and writes no
  frame slot;
- `ShapeBlockLoop` and `ShapeBlockDouble`, with their locals declared in the
  block, have the instruction counts of `ShapeTopLoop` and `ShapeTopDouble`,
  with the same locals declared in front of the body: the routine and its
  loop;
- instructions without padding, calls and the length of the loop of every
  counted routine against `reference.json` of the target: a routine that grew
  is red; one that shrank is reported, and `--record` writes the new counts on
  purpose.

Negative control, shown on 2026-09-29 on Win64 and on Linux: the compiler
before the change fails the shapes (the loops go through the frame 5 to 10
times, `ShapeBlockLoop` has 26 instructions against 21).
