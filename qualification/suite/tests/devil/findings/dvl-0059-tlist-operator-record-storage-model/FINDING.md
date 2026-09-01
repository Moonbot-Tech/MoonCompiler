# dvl-0059 — TList and operator records: two storage models in one container

Found during the seventh audit pass (journal 5). A targeted measurement of
TList with a record carrying Initialize/Finalize/Assign was checked against the
balance “every birth is paired with one burial; a live resource is copied only
by its operator”.

Important methodological caveat (a lesson from an owner-retracted analytical
blunder): the **NUMBER** of user Assign calls is **NOT** the contract — a proper
Assign copies, and the final result is the same regardless of how many
intermediate copies carry the value (precedent: C++ explicitly permits copy
elision). Comparison with Delphi must cover **DATA** and **BALANCE**, not copy
counters; the trace pattern of another container is not a language contract.

## Root cause: conflicting models

List storage is a dynamic array that follows the “all capacity slots are live”
model: our SetLength births every slot through its operator, and array release
buries every one (Delphi follows the same model — its traces show Init for all
slots on growth and Finalize for all on release). Yet the list **OPERATIONS**
were written for the model “beyond Count are dead bytes”: Move shifts and
FillChar holes (Delete, Insert, InsertRange, Pack, DeleteRange — search for
FillChar(FItems)).

## Observed violations (probe/tlist_min.dpr, probe/tlist_ops.dpr)

- FillChar on a live operator slot destroys its value without burial (a resource
  leak) and leaves a zero hole;
- the zero holes are then honestly buried (user Finalize receives zeros —
  releasing what was not acquired; trace f0, with burials outnumbering births);
- the LDirect branch of InsertRange inserts operator records by bytes
  (Move + addref, which is empty for them) — a live resource copied without its
  operator means double ownership (code inspection; the branch did not run in
  the measurement — its reachability had to be clarified during repair);
- split storage: on minimal Add+Add, the internal write goes through a
  copy-on-write array clone (something holds a second reference; the owner was
  not found — RTL refcount debugging required), leaving **TWO** data versions:
  one visible through L[i], and another, a ghost with old values, buried by
  Clear. Invisible for strings, but for RAII records it meant extra user-code
  calls on stale values.

## Repair plan (one model: “slots are live”)

- Delete/DeleteRange: bury the removed items → Move shift (ownership moves) →
  **birth** of the freed tail slots (instead of FillChar) — exactly the Delphi
  trace pattern “f-removed, i-tail”;
- Insert/InsertRange: Move shift → birth of the hole (instead of FillChar) →
  operator writes of values into live holes;
- Pack: the same replacement of final FillChar with birth;
- LDirect insertion: gate operator carriers (compile-time GetTypeKind(T)=tkRecord
  selects the element-by-element path; records with string fields lose a little
  on cold paths, correctness is more important);
- COW split: find and eliminate the holder of the second FItems reference
  (RTL debugging): container storage must have exactly one owner;
- acceptance: balance probes (the set of buried values == the set of
  born+copied values), **DATA** comparison with DCC64 under a normal copying
  Assign, the complete dvl-0035 pin, and the test battery.

## Status: fixed (on the next pass, as planned)

Re-excavation before repair dismissed half the original finding as trace-decoding
errors: “three Assigns” = one Add plus two copies from reads (the getter returns
a record by value), “the second Init at start” = caller prologue temporary, the
“ghost” = honest capacity values; there is **NO** COW split (storage refcount is
1 throughout — proven by an instrumented run), and the balances of all repros
converge. The trace-decoding lesson is in the journal.

The genuine remainder was fixed with the one model “every capacity slot is live”
using standard System.Finalize/System.Initialize (user operators for operator
records, decref/nil for strings, calls eliminated by the compiler for plain
types; no type-specific branching):

- DoRemove and fast Delete: bury the removed item → Move shift (ownership
  moves) → birth of the freed tail slot; fast Delete was extended to managed
  types — without the “copy for Notify + its burial” pair that DCC does not have.
  Hooks byte-for-byte with DCC64: `f6 i`;
- InternalInsert: the post-shift hole is born (instead of zeroed), and Assign
  writes to a live fresh receiver. Byte-for-byte with DCC64: `i a`;
- InsertRange: holes are born element by element; bytewise LDirect insertion is
  gated away from managed records (GetTypeKind=tkRecord — a record copy must go
  through its operator); strings/interfaces retain the direct branch;
- DeleteRange: the direct path was extended to managed types (finalize range,
  Move tail, birth freed slots) — the LDeleted snapshot is needed only by
  subscribers, and its own births from SetLength are no longer overwritten by
  Move without burial (the leak is closed by finalization before ownership
  transfer).

The tlist_operator_records_semantic pin: insert hooks are byte-for-byte (one
expectation for both compilers); after the meta-audit below, delete hooks are
also byte-for-byte (the prologue temporary pair turned out not to be a trace
pattern, but the cost of the discarded DoRemove result — removed); the mixed
lifecycle uses a balance invariant with canonical delta 3 (DCC64 itself shows
the same number of Move overwrites of empty initialized slots).

Boundaries: capacity-growth cadence, read temporary copies, and the shrink trace
pattern deliberately differ from Delphi RTL internals (a library trace pattern
is not a language contract, lesson A5); data agree under a normal copying
Assign.

## Meta-audit of the repair (same day): tkArray hole and removed trace pair

Self-audit of the repair series uncovered two more flaws in this same repair and
closed both.

**Gate hole: static array of operator records.** The InsertRange LDirect gate
excluded only `tkRecord`, while `T = array[0..N] of operator record` (tkArray,
managed) fell through into the bytewise Move+addref branch — bypassing operators
one level deeper in the same defect: Delphi Assign lives in RTTI as mop Copy,
while addref calls only mop AddRef, so it does **NOTHING** for such elements
(probe/arrpair_wide.dpr: the insertion segment is empty; values land in storage
by bytes). The gate was extended to `[tkRecord, tkArray]`; after the repair, the
complete `TList<array[0..3] of TRes>` axis matched DCC64 byte-for-byte — growth,
`iiiiaaaa` insertion, teardown (the array-pair-hooks axis in the pin, one
expectation for both compilers).

**The oracle for this type class is partially dead.** DCC64 on
`TList<array[0..1] of TRes>` (a **POINTER-SIZED** managed array) crashes with an
AV on the first Add: its TListHelper classifies a pointer-sized managed element
as a reference type and dereferences its data bytes as a pointer
(probe/arrpair_ptrsize.dpr; the AV address is the concatenation of Slot values).
This is a Delphi RTL defect, not canon: we do not reproduce it (precedent:
DCC's own leaks), and the pinned axis uses a size greater than a pointer so the
oracle remains live.

**The prologue temporary pair of inline Delete was not a trace pattern but
self-inflicted.** Disassembly exposed the root: the else branch of inline Delete
called DoRemove — a **FUNCTION** returning the removed item — and discarded the
result; the compiler births a function-result record temporary in the caller
frame prologue and buries it in the unwind funclet, even when the branch did not
run. The slow branch was moved into DeleteFallback — the temporary moved into
its frame and is paid for only when DoRemove actually runs. A further trap: a
**GENERIC** method body is compiled in the user's module with user switches,
and at -O3 autoinline silently consumed the helper again (the battery caught it
in the O3 pin mode); the real prohibition is only the `noinline` directive
(po_noinline, respected by both autoinline psub and the explicit inliner). Delete
hooks became byte-for-byte DCC64 at every optimization level
(`i|iiiia|f6i|f100f100f100f100f5`), and the ifdef pair of expectations was
removed from the pin.

**Third flaw: Move (permutation) was absent from the five operations.** The old
Move used a typed temporary (copy through the operator), reset a slot through
assignment of Default(T), and used FillChar+Assign into dead zeros. DCC64
measurement (probe/mvprobe.dpr): its Move segment is **EMPTY** — permutation is
an ownership transfer, with no user calls and no refcount motion. Fix: three
System.Move calls through a raw byte buffer — the value moves in transit, every
slot stays live throughout, one form for all types. The move-hooks pin axis:
empty trace as contract + data order through pairwise differences (read trace
pattern cancels by subtraction).

Neighboring containers (TQueue.MoveToFront zeroes a managed tail; TStack and
dictionaries were not audited) are the same defect class outside TList scope;
a separate PENDING item with a plan and acceptance criteria was opened.

## PENDING 10 closed (same day): neighboring containers

By owner instruction, the remaining tail was investigated immediately. The
contract-class reconnaissance (“all who touch slots”) over the package's other
containers established every site as fact on both compilers:

- **TQueue.MoveToFront — the only real hole, fixed.** FillChar on the tail after
  a shift left zeros in live slots — the measurement (probe/qprobe2.dpr) showed
  `f0f0` in the TrimExcess segment: user Finalize received dead zeros; DCC64 has
  no zeros anywhere. The tail is now born again (Initialize loop, dvl-0059
  model); the trim segment is pinned exactly: `iif100f100f100f100f100`.
- **TStack, TDictionary — clean** (probe/sdprobe.dpr): neither has a zero burial,
  and the dictionary value reads byte-for-byte identically (22). Resetting a
  slot by assigning `Default(T)` is native DCC64 form (Assign from an
  operator-initialized Default variable into a live slot), so it remains
  untouched.
- **AVL tree is clean by code**: nodes are born through AllocMem+Initialize and
  die through Dispose/Finalize+FreeMem — the model is respected without a fix.

The queue_stack_dict_operator_records_semantic pin has a semantic, not
trace-pattern, contract — the queues differ internally by construction (DCC64
ring versus our linear buffer; their copy traces differ **EVEN PER ELEMENT**).
It pins that user Finalize never sees a zero (IntToStr without leading zeros ⇒
`f0` in a trace is unambiguous), FIFO/LIFO identity by decades (trace-pattern
resilient when hops < 10), and the exact trim segment on our side. Two
trace-pattern traps were removed while constructing the pin: “the value does not
change before/after repack” and “pairwise differences” — both are false for the
DCC64 ring; only the identity framework survived.
