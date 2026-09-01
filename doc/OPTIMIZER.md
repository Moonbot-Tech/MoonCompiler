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

Integer/address arithmetic with a proven range is allowed. Floating-point
expressions are not speculatively hoisted: changing the number of operations,
an exception point, or extended precision may change the result. After the
transformation, the tree goes through normal firstpass again so no stale
register or type information remains.

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

## Register allocation and exception regions

The old defensive scheme could demote registers for an entire function when it
contained `try`. MoonCompiler keeps registers in ordinary code and creates a
memory home only for values that actually live across an exception boundary or
are needed by an exception handler or `finally`.

The solution is checked at two levels:

- frontend/mid-end marks values that cross the boundary;
- backend checks liveness, clobbers, and ABI before final assignment.

For FP loops, live ranges are shortened only in proven forms. A managed value is
not retained for CSE if retaining it adds a refcount, spill, or extends its
lifetime. A dynamic-array base after LICM is reused only while the array
variable, length/data pointer, and reachable alias chain remain unchanged.

## Code placement

`CODEALIGN` aligns proven hot loop labels without padding in an executed
fall-through path. The solution is limited to x86-64, accounts for loop size,
and does not turn every label into an aligned target: additional code size and
crossing a cache/uop boundary can cost more than the misalignment itself.

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

Several more aggressive variants were rejected: unconditional hoisting of cheap
arithmetic increased register pressure, a broad FP fallback slowed mixed loops,
and caching an address without precise clobber/alias knowledge caused
wrong-code. These results define the conservative boundaries of the current
implementation.

Further architectural improvements are listed in [Backlog](BACKLOG.md); they
are not known defects in the current optimizer.
