# dvl-0057 — value-parameter copy of an Assign record: finalization ownership and inlining

Found during the fifth audit (journal 5, section A2) while attempting to
falsify our own cd179770/115f3918 fix: the question “why is inlining forbidden
at all?” first exposed a performance regression and then a live behavioural
mismatch.

## Axis 1: the copy leaks when the body raises an exception

```pascal
procedure SinkRaise(V: TRes);   { V is a record with Initialize/Finalize/Assign }
begin
  Trace := Trace + 'v' + IntToStr(V.Slot);
  raise Exception.Create('x');
end;
```

| | trace |
|---|---|
| DCC64 | `i\|iav6f6f5X` — the copy is finalized during unwinding (`f6`), then the local (`f5`) |
| ours | `i\|iav6f5X` — the copy **leaks**; only the local is finalized |

The DCC model is: **the caller creates the copy (Initialize+Assign), the callee
finalizes it** — parameter finalization belongs to the callee and runs both in
the epilogue (the normal path, so it was indistinguishable from our caller-side
finalization in every earlier matrix) and in the unwind funclet (the exception
path, where we diverged). Our finalization was in the caller's done block, which
is skipped on exception. Notably, our **open-array** path already follows the
Delphi design (the existing callee-side `fpc_finalize_array`); the scalar path
was less correct than the array path.

## Axis 2: DCC inlines these calls; we prohibit them

For an `inline` function with such a record as a value parameter, DCC expands
the body (the map contains no `SinkInline`/`MakeInline` symbols — their bodies
are absent), while preserving the complete copy operator trace
`i|iav506f506|5|f5`, byte-for-byte equal to the non-inlined call. We exclude
such calls from inlining altogether (gate cd179770): observable behaviour
matches, but a hot RAII pattern — precisely the target scenario for these
records — loses an expansion that Delphi performs.

## Why this is costly

Axis 1 is an observable mismatch: an RAII record whose Finalize returns a
resource (lock, handle, counter) fails to return it when the callee body raises
an exception. Axis 2 imposes a systematic performance cost on every small call
with such a record on a hot path.

## Reproduction

`probe/inlrec.dpr` (inline traces and Result), `probe/inlrec2.dpr` (exception
from the body: inline and ordinary calls). The target traces are in the DCC64
column above.

## Axis 1 status: fixed

The callee now owns finalization of the copy: `final_paras` no longer excludes
Delphi records, and dereferences the parameter slot as in the open-array branch
(the copy lives in caller memory; the slot carries its address). The first attempt
crashed at precisely that point (it finalized the pointer itself as a record,
yielding a garbage Slot). Caller-side finalization was removed from the done
block. The copy's user `Finalize` now runs in the epilogue (the normal path is
indistinguishable from the old behaviour) and in the unwind funclet —
`i|iav6f6f5X`, byte-for-byte equal to DCC64. The under-call leak (Assign of a
second copy raises before the call — `ii|iaiA!f20f10X`, leaving all constructed
state leaked) matches DCC64 and is pinned.

Deliberate scope boundary: the finalization order of **multiple** parameter
copies in the epilogue is forward in our compiler (`f11f21`) and reverse in
DCC64 (`f21f11`); values and the 1:1 Initialize↔Finalize balance agree. We did
not change the shared managed-parameter traversal order in `final_paras` merely
for this; it also applies to strings/interfaces and was not measured separately.

## Axis 2 status: fixed

The explanation for the first attempt's “expansion bypasses the temp” was not a
single gate but a **desynchronization of three**. Early `check_inlining` set
`cnf_do_inline` (my narrowed variant) → the caller-copy path, gated by
`not(cnf_do_inline)`, was disabled → the late `doinlining` gate (“managed value
parameter requiring a temp”) cancelled expansion → the call was emitted as a
real call **without a copy at all**: aliasing plus double finalization of the
original. The former broad prohibition in `check_inlining` duplicated the
`doinlining` gate; it was installed because of this same breakage without
understanding the mechanism.

The fix materializes the operator copy in `createinlineparas` using the same
pattern as a real call: a raw byte temporary outside managed slot machinery (no
prologue init and no second funclet pass over zeroed memory — user `Finalize` is
not a no-op on zeros), `Initialize` + user `Assign` at the call site, and
`Finalize` in `inlinemanagedcleanupblock`, whose implicit try..finally finalizes
the copy on return **and** during unwinding. Copies are finalized after callee
locals, in reverse order. Slots are freed by `create_normal_temp`; finalization lives in the
finally funclet generated after the main pass (the established funcret precedent
one line above; the full `tempdelete` caused IE 200108231). `doinlining` no
longer filters out Delphi records — the new path owns their copies.

Expansion is real: the caller body has no `call`, instead containing
`fpc_initialize` + `FPC_COPY` (user Assign) and the expanded body; the traces
`i|iav506f506|5|f5` and `i|iav6f6f5X` are byte-for-byte equal to DCC64 in
O1–O3 and pinned.

## Custom-Initialize locals status: inlining allowed

The psub gate for “custom managed local initialization” was removed: such a
local is materialized in `createlocaltemps` using the same raw byte temporary
pattern — user `Initialize` runs in the frame Init phase at the call site (the
gate's rationale, “prologue init is observable before the call”, is eliminated
by construction), while `Finalize` runs with the other locals in
`inlinemanagedcleanupblock`. The frame follows the measured DCC64 model: Init
all copies, Init all locals, then user Assigns; finalization is locals in reverse
order, then copies in reverse order (the paranode chain is stored last-to-first,
so a forward traversal yields reverse declaration order).

A side lesson from the same attempt was the **fifth gate**: after removing the
psub gate, callers with such locals began auto-inlining themselves, and the call
inside their `inlininginfo` copy hit the late optcall gate “a void procedure may
require a managed temp” → again a call without a caller copy (the same class of
“late rejection after early flag”). This was bypassed by the root property: a
call with a Delphi value parameter itself brings a cleanup frame (the copy is
finalized in implicit finally), so the gate's concern does not apply.

The `inline_managed_locals_semantic` ASM oracle was reversed: tracked-record
functions must be **expanded** (the former requirement to “preserve a call”
pinned the gate itself rather than user behaviour); their lifecycle traces are
invariant under expansion. The pin now covers the inlined custom-init-local axis
(`i|iiav56f56f6|f5`) and inlined frame phases
(`ii|iiiaav32f32f21f11|f20f10`), byte-for-byte under DCC64.

## Remaining boundaries (values and 1:1 balance agree everywhere)

- finalization order of **multiple** parameter copies in a flat call's epilogue:
  ours is forward (`f11f21`), DCC64 is reverse (`f21f11`);
- in a flat callee, DCC64 destroys locals before parameter copies and phases
  frame Initialize before Assign (probe/inlrec3, flat part), while ours uses the
  reverse, unphased order.
