# The fields of a local record a loop keeps in temps

```text
python qualification/optimizer-core/record-fields/run_record_fields_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

At -O3 the fields of a local record which a loop reads and writes live in
temps while the loop runs: they are loaded in front of the loop and stored
back behind it (`compiler/optloop.pas`, `optimize_record_writes`). A field in
a temp is a store put off until the loop is left by its end. Until 2026-09-29
nobody asked who looks at the record before that:

- the handlers and the `finally` blocks of the `try` statements the loop
  stands in, and the code a `try..except` goes on with, when an exception
  leaves the loop; a `finally` block as well when `Exit` leaves it. They found
  the values from in front of the loop;
- a `finally` block inside the loop on Win64, where it is a routine of its
  own which reads and writes the frame. It found the old values with no
  exception at all, and what it wrote was lost;
- the code behind the target of a `goto` which leaves the loop;
- a custom `Finalize` of a local record when an exception or `Exit` skips
  the store behind the loop.

Such a field stays in the record now (`drop_observed_fields`). Explicit `try`
observers use the rule for a local variable in a routine with `try`
(`mark_seh_memory_syms`), narrowed to the fields the handler or continuation
reads. A custom `Finalize` may read any written field. Both are relevant only
if the loop can raise an exception or has an `Exit`. A handler or a `finally`
block inside the loop on Linux is part of the loop and reads the temps.

`record_fields.dpr` is both halves of the proof.

Its `Check` calls are the semantic matrix. Around the loop: a handler which
reads the record, the code behind a `try..except`, a `finally` block, with an
exception and with `Exit`; a `finally` block and a handler around it, a
handler which raises again and one further out, the loop in a handler; a call
which raises and a read through nil; `for`, `while` and `repeat`; integer and
floating point fields; two records. Inside the loop: a `finally` block which
reads the record and one which writes it, left by its end, by an exception, by
`Break`, by `Continue` and by `Exit`; a handler, with a call which raises and
with a read through nil; an assembler block which names a field (FPC only). A
`goto` which leaves the loop and one which stays in it. The record as the
result of the function. A custom `Finalize` after an exception and after
`Exit`, and a normal loop in the same managed record. The gate builds the file
at `-O1`, `-O2`, `-O3` and `-O4` without checks, and at `-O3` with range and
overflow checks, and runs
each program. Delphi 12.2 compiles the same file and prints the same line.

Its shapes are counted in the `-O3` object, so that the repair takes the
registers from no loop which may have them:

- the innermost loop stores nothing to the frame in `ShapePlain` (no `try`),
  `ShapeGuardedUnread` (the handler reads nothing of the record, the record is
  read behind the loop inside the guarded block), `ShapeBeforeGuardRead` (a
  read before the `try` is not an exception continuation), `ShapeCleanupUnread` (the
  `finally` block does not read it), `ShapeOtherField` (the handler reads a
  field the loop does not write), `ShapeNoTrap` (the handler reads the fields,
  the loop raises nothing) and `GotoInside` (the `goto` stays in the loop);
- the loop of `TwoRecords` stores to the frame twice, the two fields of the
  record its handler reads, and keeps the other record in registers;
- `ShapeManagedNoTrap` keeps the fields of a record with a custom `Finalize`
  in registers when the loop has no abrupt exit;
- `ShapeCallsBudget`, the loop of fcl-xml's `ParseMarkupDecl`, is counted
  only: a loop with calls writes the two fields of a local record in a rare
  branch and never reads them, so they stay in the record, and the
  accumulator of the loop keeps the register a call saves which the fields
  took before (52 instructions against 59 on Win64 and Linux);
- instructions without padding, calls and the length of the loop of every
  counted routine, together with its outlined finalizers, against
  `reference.json` of the target: a routine that grew is red; one that shrank
  is reported, and `--record` writes the new counts on purpose.

Negative controls, shown on 2026-09-29:

- the compiler before the repair fails 21 values at `-O3` on Win64 and 14 on
  Linux, where a `finally` block inside the loop is part of the loop and is
  wrong only when its exception reaches a handler around the loop; release
  `ccaa5fbaf` fails the same 14 on Linux;
- the compiler before the write-only rule counts 59 instructions for
  `ShapeCallsBudget` against the reference 52 on Win64 and Linux;
- a compiler which keeps every field in the record in a routine with a `try`
  statement fails the shapes of five routines.
