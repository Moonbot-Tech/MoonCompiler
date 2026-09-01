# Chimera — code forms from Arbitrage and MoonBot

> **Quidquid latet apparebit, nil inultum remanebit.**
> **Festina lente.**

The third major Devil programme. Resident tests computation under load; the
factory tests application structure. This one tests the **forms that make up
two live projects**.

Nothing is invented. Every Chimera organ is sewn from a real piece of real
code: not “something like a ring buffer”, but that exact tape traversal with
the same accumulator types, the same way of asking for trade direction, and
the same early exit. The trading purpose itself is not needed; the data and the
work on it are needed exactly as the compiler encounters them.

We have no more Pascal projects, so the list of forms is finite. The work is
done not when it becomes “enough”, but when the
[executable manual inventory](INVENTORY.md) has no uncovered rows left.

## Whole, split, and an independent answer

Every piece of work retains its complete live form and has an independent
oracle. The large `tape` organ additionally lives in four equivalent bodies:
this deliberately tests method size, register pressure, and the different
AUTOINLINE paths. There is no need to multiply the other organs artificially
when the work has no second genuinely different composition.

Splitting in place of the whole would be a substitution. A huge method is not
the same code, only longer: it has different register pressure (the allocator
starts spilling values to the stack, and it is precisely the spills that go
wrong), different value live ranges, and different optimizer paths—expensive
passes are disabled beyond a threshold, so a large body takes **a different
path**. The monolith therefore remains a monolith, and splitting is added to
it.

| body | what it is | inlining |
|---|---|---|
| monolith | as in the live code, more than forty live local values | — |
| record-split | state travels between pieces in a `var` record | compiler declines |
| pure steps from a leaf unit | arithmetic is moved behind calls | succeeds |
| the same steps from a unit in a cycle | **the same text**, included through the same file | dead |
| oracle | written independently | — |

The four working `tape` bodies are identical in actions and order; they are
compared **bit for bit**. The fifth is written differently: exact quantities
to the unit, floating-point quantities with a tolerance. Any divergence
between two proves a defect by itself, without a second build for comparison.

The “third body versus fourth body” pair has separate value: one source file,
two machine-code outputs. The only difference is where the steps came from.

## Inventory

[`INVENTORY.md`](INVENTORY.md) is the manual list of work Chimera must carry;
`inventory.json` is its machine-readable half. They are not two documents but
one: the gate cross-checks them with each other and with what actually ran.

A row is closed not when code has been written for it, but when that code
**ran**. On every run the program prints which rows executed and which branches
inside them fired:

```
CHI_COVER CHI-MB-TAPE-001 break-early=1 bucket=1 inline-leaf=1 ...
```

The difference is not theoretical. The first run of this check showed that the
early-exit branch in the `tape` organ had never executed: the tape fitted
entirely into the farthest window, so the traversal always reached the start.
The program still printed OK.

## What the gate checks beyond the program itself

`scripts/run_chimera_gate.py` is one production build, about eight seconds.
With `--profiles`, it uses four optimization levels; with `--switches`, it also
uses every optimization individually.

* **inventory against execution** — a row without execution is unfinished
  work, execution without a row is an unknown identifier, and a branch at zero
  is code that exists but does not work. All of these stop the run;
* **unclosed rows** — `open` fails the gate by default: an inventory with a
  hole is not an inventory. `--allow-open` is only for intermediate work;
* **profiles and each switch individually** — a combined profile might not
  activate the transformation that breaks the form;
* **answer across builds** — the value must be identical;
* **inlining map**. The compiler reports which bodies it declined to inline.
  Chimera deliberately keeps the same text where inlining works and where it
  is dead. If the map diverges, the “inlined versus not inlined” axis has
  ceased to exist, while the program still prints OK and tests half of what was
  intended. The gate does not stay silent about it.

Modes: without options, one release build; `--profiles`, four profiles;
`--switches`, profiles plus the matrix of individual optimizations; `--focus
<organ or ID>`, only one organ. Every covered ID is mapped to its organ, so a
focus cannot turn green formally without executing anything.

## Organs

| organ | source | subject |
|---|---|---|
| `body` | `TradeTypes.TTrade` | 16-byte tape record, direction in the sign of quantity, requested by reading the same field as an integer; leaf unit outside dependency cycles |
| `tape` | `MarketsU.JoinHOrders` | reverse tape traversal: windows, buckets, minute ring, moving average, early exit. Five bodies |
| `ring` | `EngineBase.AddTmpHOrder` + `JoinHOrders` ring | lock-free trade transfer between threads: publication after the fact, writing more into an occupied slot, ring split, splicing with a non-transitive comparator |
| `agg` | `TTrade.TryAggregate` | two `var` parameters of its own type, `-0.0`, two early exits |
| `sort` | `MarketsU.QuickSortOrders` | exchange through an owner field, tolerance in comparison, bailout past decrement |
| `book` | `HandleGlass`, `HandleBookChain` | wall folding with nested loops, extending distant levels while subtracting what is already accounted for |
| `strat` | `CalculateMoonHookDetectionL` | five early exits, two search paths, a window formed by triple clamping |
| `buf` | `TReusableMemStream`, `TPacketCache` | memory is never returned downward; linear cache with overlap eviction |
| `proto` | string framing and stream primitives | length in BYTES, mandatory write versus best-effort read, a cut at every point |
| `json` | `JsonHelpers` and engine parsers | production chain from raw body to string and search within it |
| `sign` | exchange-engine `BuildHMAC` | different signature-string construction rules, external vectors |
| `code` | `nethelpers` | base64 tables and triplet encoding, RFC 4648 vectors, byte strings |
| `task` | order-state canon | nested packed sections, modifying one while neighbouring ones remain untouched |
| `hl` | `HLSigs` | action schema through an open array, precomputed indexes, field order |
| `wire` | `ArbProto` | block padding, in-place encryption, self-delimiting parsing, NIST vector |
| `pairs` | `BuildComboPairs` | list snapshot, identity filter, price multiplier, naïve oracle |
| `name` | `TaggedName` | minimal distinguishing prefix, hash bytes inside a managed string |
| `hold` | `TThreadSafeBuffer`, `TSlowSafeList` | single-writer ring, copy on write, deferred collection |
| `hands` | `AssetTransferU`, `SafeDict` | capture through two frames, loop variable versus a copy, dictionary under a lock |
| `stream` | `StreamProto` | checksum with carries and rotations, reconstruction with repeats and out-of-order delivery |
| `group` | `GroupManager`, `CanonMapper` | five conditions for counting a series, compound registry key |
| `users` | `MoonBotUsers.TryGetUsersList` | two-stage signature, CBC, and address masking |
| `pack` | MoonBot candle package | SynLZ + zlib, format versions, shadow-buffer publication, and retry after an exception |
| `text` | reports and WebSocket scratch strings | writer over a stack buffer and a managed string with reusable capacity |
| `shake` | WebSocket handshake | circular header reading, SHA-1/base64, UTF-8 at every split |
| `state` | `MoonProtoOrderState` | dense canon, mask-selected sections, ULEB128, checksum, and time |
| `field` | MoonProto serializers | self-describing stream versus a flat field record |
| `life` | `MyListHelper`, large `Bworks` exception paths | managed lifetime, deep unwinding, and element replacement |
| `crew` | — | harness: allocating work through a shared counter, closure as a unit of work |

For the complete work list with oracles and branches, see [INVENTORY.md](INVENTORY.md).

## Build prerequisite

The Arbitrage wire depends on real AES-GCM from the pinned product mORMot line.
The required Win64 Intel object files are included with the sources in the
pinned vendor; the gate checks that they exist before linking. No files from a
local Delphi/mORMot installation or manual directory preparation are required.
