# A routine with try and a nested routine keeps its registers

```text
python qualification/optimizer-core/try-nested/run_try_nested_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

A routine with a `try` gives a frame home to what its exception paths read -
the `finally` block, a handler, the code behind a `try..except` - and keeps
everything else in registers (`compiler/psub.pas`, `mark_seh_memory_syms`).
Until 2026-09-29 a routine which had a nested routine of its own, a nested
procedure or an anonymous function, was left out of that: all its locals and
parameters lived in the frame. The body of such a routine is what a trading
program runs most: a `try..except` around the work and an anonymous comparer
for a sort some calls make.

A nested routine changes nothing in what the exception paths of its parent
read. What it reads or writes of the parent is known when it is parsed and has
its home in the frame (the static link reaches the frame) or in the capturer,
before the parent gets its locations. What it raises reaches the handlers of
the parent as the exception of any other callee does. So the parent is
analysed as every other routine (`tcgprocinfo.generate_code`).

`try_nested.dpr` is both halves of the proof.

Its `Check` calls are the semantic matrix: the exception raised by the nested
routine, by another callee and by the processor (a read through nil, a
division by zero); the parent's values read in the handler, in the `finally`
block, in a cleanup inside a cleanup, behind the `try..except`; the nested
routine called from the cleanup and from the handler, writing a local of the
parent, having a `try` of its own, two levels deep, calling its parent; an
anonymous function which captures nothing, a value, a value the try block
writes, and one made in the handler; `Exit`, `Break` and `Continue` through
the cleanup; integer and floating point values, the function result, methods.
Every callee overwrites all volatile registers of the target. The gate builds
the file at `-O1`, `-O2`, `-O3` and `-O4` without checks and at `-O3` with
range and overflow checks, and runs each program. Delphi 12.2 compiles the
same file and prints the same line.

Its `Shape` routines and `TBook.Join` are counted in the `-O3` object:

- the innermost loop of each `Shape` routine (found by its conditional
  backward jump) reads and writes no frame slot;
- the loop of the routine with a nested procedure and the loop of the routine
  with an anonymous function have the instruction count of the loop of the
  routine without them;
- the loop of `TBook.Join` goes through the frame once, for `Self`, which the
  anonymous function of a method captures (Win64; on Linux its floating point
  sums live across the call of `raise`, and no vector register survives a
  call there);
- instructions without padding, calls and the length of the loop of every
  counted routine, together with its outlined finalizers, against
  `reference.json` of the target: a routine that grew is red; one that shrank
  is reported, and `--record` writes the new counts on purpose.

Negative controls, shown on 2026-09-29:

- the compiler before the change fails the shapes on Win64 and on Linux (the
  loops of `ShapeNestedLoop` and `ShapeAnonymousLoop` go through the frame 8
  times, the loop of `TBook.Join` 20 times);
- a compiler which sets no frame home in a routine with a nested routine
  fails the values at `-O3` on Win64: what an outlined `finally` reads
  (`nested-finally`, `nested-exit`, `cleanup-in-cleanup`, `from-finally`). On
  Linux that compiler passes the matrix: the cleanup is part of the routine
  there and reads the registers, and the unwinder brings the nonvolatile
  registers of the raising call to the handler. The values on Linux are
  guarded by the matrix itself, not by a shown failure.
