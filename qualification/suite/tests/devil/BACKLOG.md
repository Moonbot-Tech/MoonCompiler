# Devil — coverage-axis registry

A working list, not documentation. Acceptance criterion: while even one line
remains in “Open,” the work is not complete. A line moves to “Closed” only when
the axis is actually generated, checked by an oracle, and run by a gate.

Numeric axes are closed permanently and must not be extended—see “Arithmetic
ban” in `STATUS.md`. Lines that previously stood here for real edges,
`div`/`mod`, and shifts were removed by that rule, not completed.

> This document was restored after loss of the working directory; facts were
> checked against code and the wording is new.

## Closed

### Values and types

- integers: 8 types × 10 binary operators × boundaries and random values
  (`expr`)
- unary: `-`, `not`, `Abs`, `Sqr`, `Succ`, `Pred`, `Odd` (`unary`)
- folding against runtime, including mixed types (`fold`)
- comparisons, including mixed signed/unsigned (`cmp`)
- reals: Single/Double/Currency, conversions, comparisons, intrinsics (`float`)
- 128-bit arithmetic (`i128`); the layer is closed from the arbiter because
  Delphi has no such type
- value source: literal, typed const, local, opaque value, field, property,
  function result, array element, `var` and `const` parameter
- consumer: assignment, field, array element, result, `var` parameter,
  property, index, `case` selector, loop bound
- `{$Q+}`/`{$R+}`: overflow and out-of-range as mandatory exceptions in both
  directions—an extra exception is also a defect (`chk`)

### Memory, layout, lifetime

- managed lifetime: balance, destruction order, exceptions, `out`/`var`,
  closures, arrays, nested records, string COW (`life`)
- record layout: sizes, offsets, packed/align, by-value passing (`abi`)
- arrays and pointers: static, dynamic, ragged, `Slice`, open arrays, pointer
  traversals, negative bases (`arr`)
- dynamic arrays in depth: buffer sharing, `Copy` as detachment,
  `Insert`/`Delete`, release on shrink, concatenation, nested levels,
  `VarArray` with arbitrary bounds (`dyn`)
- interfaces beyond one call: per-scope count, interface casts,
  `QueryInterface`, `Supports`, `implements` delegation, an interface in a
  record, array, and closure (`intf`)
- what carries a literal-originated value: 12 storage sites × refcount, buffer
  writability, shared memory of two occurrences; plus 8 literal-writing forms
  (`lit`)—hence dvl-0031

### Strings and Unicode

- strings: 4 types, COW, `Copy`/`Delete`/`Insert`/`Pos`/`SetLength`/
  comparisons (`str`)
- Unicode contract: element width, surrogates, conversions and casts between
  byte types, typed code page, `PChar` step, `array of const`, layout of
  string fields, generic with a string argument (`uni`)

### Dispatch, generics, RTTI

- virtual, inherited, metaclasses, method pointers, closures, `is`/`as`,
  `InheritsFrom`, `ClassParent`, `ClassType` (`disp`)
- generics: specializations, generic methods, class var per specialization,
  `constructor` constraint, `TArray<T>` (`gen`)
- RTTI: `TypeInfo`, kind, enum-name tables, published properties,
  `GetOrdProp`/`SetOrdProp`, `GetTypes` catalog, `TValue`, `TRttiField`,
  published methods, `MethodAddress`/`MethodName`, invocation through
  `TMethod` (`rtti`)
- attributes as a readback axis: 10 targets × “does the tag reach the tables”
  (`attr`)—hence dvl-0037 and dvl-0040

### Control flow, exceptions, initialization

- recursively nested contexts to depth 4: `if`, `for`, `while`, `repeat`,
  `try/finally`, `try/except`, `raise/catch`, `case`, `with`, nested
  procedure, closure, managed scope
- `case` with ranges and an `Int64` selector, forward/backward `goto` and
  from a loop, `Exit`/`Break`/`Continue` through `try`, short and complete
  Boolean evaluation (`flow`)
- exceptions and unwinding: nested `finally` order, typed branches and
  `else`, re-raise, exceptions in a constructor and during unwinding,
  managed release by frames, `Exit` from a handler, RTL hierarchy (`exc`)
- unit initialization: dependency order, class constructor before its unit body,
  reverse finalization, global managed values and typed constants with managed
  fields (`init`)

### Compilation, code generation, boundaries

- cross-unit: inline, generics, records, aliases, constants through PPU (`unit`)
- optimizer correctness: legacy individual alias/reload/dead-store forms and the
  closed memory-effects matrix (`opt`)—12 mutation routes × 7 optimizer
  consumers × 6 mutation points, all 504 critical triples and all 414 pairs
  with loop form and integer ABI. Arithmetic here is bait for
  LICM/CSE/GVN/strength reduction, not a repeated numeric corpus
- calling convention: arguments beyond the fourth position, alternating integer
  and real values, narrow and wide by-value records, aggregate result,
  `var`/`out`/`const`, open arrays, method pointer, callback,
  `stdcall`/`cdecl`, narrow types in wide slots (`call`)
- inline as its own axis: `var`/`out`/`const` parameters, managed result,
  nested inline, `inline var`, recursive candidate, inline in `finally`
  (`inl`)—hence dvl-0018
- assembler subroutines: argument positions, result in RAX, callee-saved
  registers, opacity to the optimizer (`asm`)
- file types: typed file and element size, positioning, truncation, untyped
  blocks, text files, and `Append` (`io`)
- declarations, directives, DLL import (`decl`)
- Delphi language surface: record operators, record/class/type helpers,
  `absolute`, `array of const`, Variant, default and indexed properties,
  nested types, writable const, `resourcestring`, enumerators, Delphi 12
  syntax (digit separators, binary literals, `align`, `^` literals),
  `OleVariant`, Variant comparison (`lang`)
- threads: independent worker slots, join as a barrier, managed transfer,
  atomic operations, `threadvar`, exception from `Execute` (`thr`)
- sets and enums: operations, membership over the whole universe, iteration,
  sparse enums and `$Z1`/`$Z4`, sizes as observation (`set`)
- compilation as source: 82 mandatory rejections and acceptances (`reject`),
  including attributes (6 locations × with and without a constructor), record
  control operators, `const [ref]`, and overload resolution at the ambiguity
  boundary
- ICE and hangs: depth, width, length, inline chains, a separate guard for
  dvl-0017 (`stress`)
- code-generation gate: machine-code properties rather than values (17 probes)
- `{$O-}` islands inside an optimized module

### Compiler decisions

- overload resolution: 13 candidate families × argument forms, including the
  literal-writing form (`pick`)—hence dvl-0027…0030
- the same questions **after a transfer**: 19 ways to deliver an argument,
  including provenance reset by parentheses, cast, and identity; PPU boundary,
  specialization, closure, thread (`deliver`)—hence dvl-0039 and the
  dvl-0028/0029 survivability map
- name resolution: 19 forms where one name is declared twice—`with` against a
  local, field against local and global, shadowed loop and `for-in` variables,
  helper against a native method, two helpers for one type, nested type, order
  in `uses`, qualified name, `inherited` with overloads (`scope`)
- closure capture: 18 forms—classic and inline loop variable, `for-in`,
  local after mutation, returned-call frame, `with` scope, field through
  `Self`, exception handler, thread, recursive capture (`capture`)

### Systematic expansions and composition

- passenger × transfer matrix: 19 passengers × 27 boundaries, 382 meaningful
  pairs, all covered; edge values as the third dimension; coverage and
  exclusions recorded in the manifest (`matrix`)
- boundary composition: a passenger over two consecutive boundaries, 1954
  triples, seed slice, before/between/after passport, every third case gets a
  third boundary (`composite`)
- paths on which narrowing has already been lost: 8 generic forms (`genpath`)
  and 12 routes before narrowing (`narrowpath`), each across all narrowings and
  all edge values

### Oracles and instrument design

- generator model, second computation in the program, profile differential
  `debug`/`o1`/`o2`/`release`, rebuilding over PPU, Delphi 12.2 arbitration
- observations without absolute truth (`DEVIL_NOTE`/`DEVIL_TRAIL`) and their
  cross-build comparison
- circulation: every floor feeds a passport into the end-to-end digest through a
  bijective step; subtotal is computed per layer; known results and streamed
  thread output are included
- mirrors: folding against opacity, inline against noinline, specialization here
  against specialization from PPU, one compiler invocation against a separate
  invocation per unit, **rebuilding the same source** (determinism)
- leaking bait: code that appears removable, with a thread into circulation
  through a pointer, field, closure, or module boundary
- declaration order as an axis; a second program for the same seed as oracle;
  a whole-program invariant of births and deaths
- build strictly under the build-driver contract (`devil_toolchain.py`)
- automatic minimization of a red check into a separate program
  (`devil_minimize.py`)
- **reverse minimization**: the case is fixed and the environment is cut
  (`run_devil_bisect.py`)—hence dvl-0040
- registry of analyzed defects so new ones do not drown in known ones

- register-allocator pressure as a matrix dimension: every third case runs with
  an occupied bank (12 live integers, managed string, interface, exception
  frame); every value lives across the transfer and is consumed afterward; a
  pressured case has the `-p` suffix
- ordered channel: events whose ordering is fixed by the language feed a
  noncommutative numbered step (`DevilStep`) around every matrix transfer and
  at every case in layers with fixed tables; it is not placed beneath threaded
  branching
- instrument counters themselves (feeds and steps) are compared across builds:
  a build that measured less is visible even when digests agree

- allocator load: 48 threads contend for one block class across the full size
  grid; an owner canary catches double issue; every heavy case requires at least
  one real wait, but does not compare an exact scheduler-dependent wait count
  across builds (`load`)
- environment gate: code must depend on nothing except source—ten directory
  perturbations, byte-for-byte artifact comparison
  (`run_devil_env_gate.py`)

- standard-library contract: lists, streams, dynamic arrays, generic
  collections, string functions, UTF-8, paths—with Delphi as oracle (`rtllib`)
- what a declaration carries across a separate-compilation boundary: aliases,
  layout, method table, overloads, defaults, calling convention, generics on
  both sides, attributes (`ppu`)—hence dvl-0045
- structure of protected regions: how many times a `finally` body ran in
  eighteen forms, including an inlined call and managed body (`region`)
- machine-encoding boundaries: constants beyond an immediate, large offsets,
  excess arguments, wide set, `case` labels at edges, by-value aggregate
  (stress gate)
- build-mode matrix: eight knobs forbidden to change behavior
  (`run_devil_modes_gate.py`)—hence dvl-0044

## Open

### Strength meter (deferred until the end by explicit instruction)

- run the mutant inventory and obtain `killed/total`; this closes criterion 2;
  run only on a clean tree, the bench is ready
- report “which family kills what,” reject families with zero kill rate
- targeted mutations for fixes whose revert conflicts

### Infrastructure

- CI run, seed accumulation, timing report
