# The `resident` layer — Devil's full-scale program

All other Devil layers are single-pass: a case is born, evaluated, checked, and
dies in a single breath. This one is different — it is **one large program**
that lives for a long time, performs real computation, and ages.

## Structure

**Carriers** are live objects that rotate through a ring of stages. Each carries
a managed record with canaries, three string kinds, a dynamic array, a
dictionary, a reference-counted interface, a closure, thirty-two numeric slots,
eight string slots, and an ownership-bearing dictionary of object slots.

**The ring** is a registry of stages, each with its own queue and workers. Its
exact ordered membership is printed by `--list-stages`; an independent lock
checks it in every profile, so the count is not duplicated in this document.
A carrier's route is a personal stage permutation, so it visits every stage
exactly once per lap; the permutation is rebuilt every eight laps. Ownership is
transferred physically: once the carrier is published to a queue, its producer
does not touch it.

**State survives between laps**: slots accumulate across hundreds of laps, grow
to a ceiling, are cleared, and occupy memory again.

## Oracles

| oracle | what it detects |
|---|---|
| per-carrier digest | the route is seed-defined, so the sequence of its events is deterministic and bit-for-bit comparable across builds |
| root: commutative sum | does not depend on the order in which threads happen to finish |
| per-stage contribution | identifies the failing stage, not merely that a divergence occurred |
| lap passport | what a carrier showed on its first lap, it must also show on its thousandth |
| census balance | births exactly equal deaths |
| canaries | memory corruption identifies the seeding location |
| processing count | the route is a permutation, so processing count is exactly `carriers × laps × stages` |
| initialization order | compiler property, folded independently |
| `Claim` | a mathematical invariant or external reference is wrong on its own, without comparison to anything |

## Families

| family | subject |
|---|---|
| `own` | ownership and lifetime: reference counts, closures, stack unwinding |
| `text` | strings, encodings, shared buffers |
| `mem` | memory movement, every allocator block class, fragmentation |
| `gen` | generics and specializations |
| `flow` | control flow, exceptions, block order |
| `coll` | runtime collections |
| `shape` | representation: sets, enumerations, overlays, variants |
| `cls` | object model: virtual dispatch, metaclasses, operators |
| `codec` | reversible buffer transformations |
| `rtl` | runtime library |
| `thr` | stage-internal multithreading |
| `bignum` | long arithmetic, long division, modular exponentiation |
| `hash` | SHA-256 and CRC-32 with specification vectors |
| `calc` | many-digit π, transform-based reduction, system solving, geometry |
| `float` | series, dot products, matrices — with a derived tolerance |
| `fluid` | Navier–Stokes equations on a grid |
| `fft` | fast Fourier transform |
| `cipher` | AES and ChaCha20 |
| `pack` | Huffman coding, reference-based compression, printable re-encoding |
| `eth` | Keccak-256 and secp256k1 curve arithmetic |
| `numeric` | matrix decompositions, sieve, primality witnesses, factorization |
| `ode` | equations of motion: exact solution, time reversibility, energy and momentum conservation |
| `algo` | graphs and sorting: three shortest-path methods, two spanning-tree methods, four sorts |
| `poly` | polynomials and exact fractions: division with remainder, roots, product-rule derivative |
| `vm` | virtual machine: an expression is evaluated by a tree and by executing compiled code |
| `pred` | long predicates: scalar enumeration against truth-table bit masks |
| `opaque` | values hidden from the optimizer: a foreign unit, inlined body, pointer, alias, parent frame |
| `fault` | exception as part of a calculation: a value travels through stack unwinding |
| `edge` | edges of machine arithmetic and inlined code: shifts, narrowing, loop tail, effectful `inline` |
| `form` | one operation expressed with different constructs: six traversal kinds, block move, slicing, search, reversal |
| `live` | value liveness and register pressure: survival through a call, branch, loop, unwinding |
| `param` | parameter passing and return: record sizes, four passing methods, long lists, ABI |
| `select` | value selection: dense and sparse labels, ranges, wide selector, type edges |
| `recur` | recursion and frames: tail, mutual, deep, branching, with unwinding |
| `convert` | type conversions: rounding, exact fractions, text, characters, sign under truncation |
| `hoist` | loop-invariant code motion: what may and may not be hoisted — empty loop, guard, early exit |
| `matrix` | nested loops and index arithmetic: transpose, three multiplication orders, blocks, strides |
| `bits` | bit operations: population count, least and most significant bit, masks, reversal, parity, fields |
| `const` | what the compiler computes itself: folding against runtime, constant arrays, records, sets |
| `intdiv` | division and remainder: replacement with magic multiplication, powers of two, sign, narrow types |
| `ptr` | pointers: traversal, type stride, two names for one location, byte view, record fields |
| `strops` | string operations: search, slice, insert, delete, compare — against a manual loop |
| `sideorder` | side effects in expressions: not order, but completeness — every operand exactly once |
| `floatorder` | what may not be done to floating-point arithmetic: reorder summands, replace division with multiplication by the reciprocal |
| `align` | record layout: sizes, offsets, packing, array stride, nesting |
| `arraydyn` | dynamic arrays: reference versus copy, resize, empty array, strings of different kinds |
| `overflow` | modular arithmetic with checks disabled: narrow result versus wide result truncated afterwards |
| `enumord` | enumerations: ordinals, explicit values, iteration, set, index, storage |
| `mesh` | machine on a network of nodes: virtual step, virtual transition, throw as part of the route |
| `pipe` | pipeline of eight successive calling mechanisms; link order is a seed-derived permutation |
| `weave` | a value whose residence changes at every step: field, cell, dictionary, slot, capture |
| `siege` | long dependency chain and barriers across it; independent lanes interleaved |
| `maze` | backtracking search against wavefront: recursion, marks, and an outward throw — plus an ordinary loop |

### How this differs from Omni

Testing separately whether a virtual call, closure, interface, and exception
handler work is the job of the code-form corpus, and it has already been done
elsewhere. Each of those things works. What fails is the **combination**: when a
virtual call chooses the next step, a closure prepares its value, a handler
applies an adjustment, and object ownership transfers along the way. There is
nothing the optimizer can prove for certain there — and that is where it makes
mistakes.

Thus a stage here is not “let us check that `is` answers correctly”, but a
machine that cannot be calculated without executing it in full, with an answer
known independently. Enumerating forms catches a missing capability;
intertwining catches an incorrect answer when every capability exists. The
latter is costlier to write and costlier to get wrong, but it is what produces
findings.

### Families that ask about optimization rather than liveness

The other families check whether the program reaches the end of a lap intact.
These three ask something else: whether the compiler lied while **simplifying**
what was written. Every optimization rests on a proof: “this did not change”,
“execution cannot reach here”, “the same value was already calculated”. The
error lies in the proof, and can be seen only by code that provokes that proof.

`pred` evaluates one Boolean expression twice: scalarly, across all 32
combinations of five inputs, with the answers accumulated into the bits of a
number; and once as a whole, over truth-table column masks. Boolean algebra
requires them to agree, so a difference proves a defect by itself, without a
reference run. It also derives the number of times an operand was allowed to be
evaluated: it is calculated from the masks, not observed.

`opaque` builds “suspect form — mirror” pairs. In the first, a value is read
directly in a loop expression, but is changed from where that direct view cannot
reach: a neighbouring unit, an inlined body, a pointer, a second name for the
same buffer, a nested procedure into its parent frame, or a virtual or
interface call. In the second, the same calculation is assembled step by step,
so there is nothing to hoist. Any honest optimization preserves both.

`fault` tests an exception not as a path (that is `flow`'s job), but as
arithmetic: a number physically travels through stack unwinding. Each stage
calculates the same result twice — through `raise` and through ordinary
branching. This catches not only “we took the wrong path”, but also “we arrived
correctly but carried the wrong value”: a lost assignment before a throw, or a
value from a register that no one is required to preserve across a handler
boundary.

`edge` gathers boundaries where replacing what was written with something
cheaper stops being harmless: a shift for multiplication, a conditional
assignment for a branch with a side effect, an unrolled tail for a loop, an
inlined body for a call. It draws a strict boundary between what the language
**guarantees** and what it leaves unspecified. The former is checked by an
assertion: the `div`/`mod` contract for all signs, reversibility of narrowing,
an arithmetic-progression sum, and an operand evaluation count. The latter —
operand evaluation order, a shift wider than the bit width,
`Abs(Low(Integer))` — never enters assertions and only contributes to the
digest: its judge is a comparison of builds with each other, not our opinion of
the correct answer. Where a sum depends on operand order, the stage presents not
the sum but its invariant: how many times each operand was evaluated.

`form` presents the same operation written with different constructs: a
reduction with six traversal kinds, an overlapping block move against a
bytewise loop, a library slice against a manual one, an early-exit search
against a flag-based search, an in-place reversal against construction of a new
buffer. If two forms diverge, at least one is wrong — a fact, not a suspicion.
The forms are chosen to differ in mechanics, not presentation: the compiler
reduces a pair of “the same thing with different parentheses” to one tree before
optimization, leaving nothing to test.

The remaining five use the same technique: present two renderings of one
calculation that differ only in what the compiler is allowed to change. `live`
places an obstacle between creating a value and reading it (a foreign call,
branch, loop, stack unwinding, nested procedure), and requires twenty-four live
values to survive it. `param` enumerates the boundaries where the passing rule
changes: record sizes around powers of two, four passing methods, a long
argument list, and a mix of integers and floating-point values. `select`
enumerates the **entire** selector domain, including everything outside the
labels, because a jump-table error lives at the edge of its range. `recur`
compares recursion with a loop that has no frame at all. `convert`, `hoist`,
`matrix`, `bits`, and `const` do the same for rounding rules, loop-invariant
code motion, index arithmetic, bit replacements, and what the compiler
calculates for us at build time.

`hoist` deserves separate mention: every stage presents a pair — a loop from
which work **may** be hoisted, and an almost identical loop from which it **may
not**. Not everything independent of the lap may be hoisted: a loop may execute
zero times, an expression may be meaningful only inside its branch, and a value
may be invariant while its action is not.

`floatorder` stands apart: other floating-point families calculate and compare
with a tolerance, whereas this one asks whether the compiler rewrote what was
written. Floating-point addition is not associative, division is not
multiplication by the reciprocal, and a reordering legal for integers changes
the result. There are no tolerances here, and that is not carelessness: values
are chosen around the boundary of exact integer representation, where any order
shift costs a whole unit and every participating number is exactly
representable.

And `sideorder`: it never asserts operand evaluation order — the language does
not specify it, and requiring it would create a false alarm on an honest build.
It asserts completeness: every operand is evaluated, and exactly once. That
property is independent of order, and can therefore be asserted. Where the
result nevertheless depends on order, the stage presents not the result but an
invariant: the sum of counters, visit count, or set of affected cells.

Global variables of a neighbouring unit exist in one instance in the program,
and the ring is multithreaded, so a stage that touches them owns them for its
entire duration — the lock is acquired outside the calculation, not for an
individual access.

## Fairness rule

**The program must be impeccable.** One owner at a time, zero undefined
behaviour of its own, no sleep-based interleaving. Only then can every divergence
be attributed unambiguously to the compiler, library, or memory manager.

This leads to several deliberate prohibitions:

* addresses, readings from the global census, and raw fractional values do not
  enter the digest — they are properties of a run, not of the program;
* floating-point comparisons are either strict (where the result is exact by
  construction) or use a tolerance **derived** from the number of operations,
  not fitted to the answer;
* all string content is ASCII; otherwise machine settings would be tested.

## How to run it

```
resident.exe --seed 1 --carriers 6 --laps 12 --workers 2
resident.exe --only bignum          # one family or one stage
resident.exe --list-stages          # registry membership
```

The full release gate with all locked profiles and the default shape:

```
python scripts/run_devil_resident_gate.py
```

It builds four profiles and requires equal answers from all of them, checks that
worker count does not affect the result, that a repeat run and a rebuild produce
the same result, and runs the lap ladder. The ladder itself is stored in
`runner_manifest.json`, checked as an increasing set of positive unique values,
and included in the inventory lock: it cannot be weakened without the contract
gate noticing.

`--handoff` runs a reduced locked shape, while arbitrary
`--profiles/--carriers/--laps` are allowed only together with explicit
`--diagnostic-subset`. Such runs print `RESIDENT_DIAGNOSTIC OK`, not the release
marker `RESIDENT_GATE OK`, and are not qualification evidence.
