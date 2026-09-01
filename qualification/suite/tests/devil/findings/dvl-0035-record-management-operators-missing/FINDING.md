# dvl-0035 — record management operators: `Initialize` and `Assign` are unsupported

Found while building the record-lifetime layer with custom operators. Delphi
12.2 builds and executes it; our compiler rejects it.

## What happens

```pascal
type
  TRec = record
    Slot: Integer;
    class operator Initialize(out Dest: TRec);
    class operator Finalize(var Dest: TRec);
    class operator Assign(var Dest: TRec; const [ref] Src: TRec);
  end;
```

| operator | ours | Delphi 12.2 |
|---|---|---|
| `Initialize` | `Error: Impossible operator overload` | works |
| `Finalize` | works | works |
| `Assign` | `Error: It is not possible to overload this operator` | works |

The complete program (`repro-standalone.dpr`) prints the `iia|ff` trace in
Delphi: two initializations for two local values, one operator-based assignment,
and two finalizations on scope exit. Ours does not compile at all.

`Assign` fails to compile in either the `const [ref] Src` form or the `var Src`
form, so the operator itself is unsupported rather than there being an objection
to its signature. (Delphi accepts both forms; it rejects the `const Src` form
without `[ref]` with the meaningful E2618 message—we agree with it there, but
for another reason: we reject all forms.)

## Why this is costly

Management operators are RAII on records: resource acquisition and release, a
reference counter for an external handle, a lock guard, or automatic closing of
a file or socket. Exactly what they were added to the language for, and exactly
what lives in the hot paths of trading code—where introducing a class with
`try/finally` is costly or awkward.

The rejection is hard: the module does not compile. There is no source
workaround—either rewrite the record as a class or scatter manual calls at every
copy point, which the compiler does not show.

`Finalize` alone does not salvage the situation: without `Initialize`, a field
has no defined initial state; without `Assign`, a record copy cannot adjust the
counter, and finalization will release the same resource twice.

## Reproduction

`repro-standalone.dpr` is self-contained.

Through the suite: verdict-gate cases `record-operator-initialize`,
`record-operator-assign`, `record-operator-finalize` (the last must compile and
does compile).

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: the declaration is rejected
in all profiles. Adjacent: `const [ref]` as a parameter modifier does not parse
on its own either—dvl-0036.

## Status: Delphi forms accepted; local lifecycle matches

- `Initialize(out Dest)` is accepted alongside the `var` form; the operator body
  receives raw memory: its own `out` parameter is excluded from callee
  managed-out initialization (otherwise `Initialize` would recurse into itself;
  this produced a stack overflow in our first build, while Delphi has no such
  call).
- `Assign` is the Delphi name for the copy slot: `(var Dest; const [ref]/var Src)`
  is accepted, and the parameters of the Delphi form are **reordered** so the
  physical convention matches the runtime `(source, destination)`, while the
  user body continues to use its own names. The FPC form `Copy(constref Src; var
  Dst)` continues to work as before. `const Src` without `[ref]` is rejected as
  in Delphi (E2618).
- The DCC64 trace (`iia|6|f6f5` and the fuller one): locals assigned through an
  operator, finalization while unwinding an exception, and a nested record
  copied through `Assign` are byte-for-byte identical; copy values in static
  and dynamic arrays match.

Pin: `RTL-test/semantic/record_management_operators_semantic.dpr` (green under
DCC64 too). Both verdict-gate registry entries were removed.

## Status of value parameters: fixed

A value-parameter copy follows the Delphi `i[iav4f4]` model: the caller builds a
stepwise temporary copy—`Initialize`, user `Assign`, then an immediate
`Finalize` after the call—both in a loop and for an aggregate whose field carries
operators (a recursive predicate: a container of such a record is copied the
same way; the walk visits instance fields only and skips `class var`—a
self-typed record field such as `TTimeSpan.FMinValue` would otherwise recurse in
the predicate forever). Mechanics:

- Records with Delphi copy semantics (and their aggregates) pass by reference
  regardless of size (`cpupara`), with no callee-local copy (`pparautl`) and no
  callee-side addref or finalization (`ncgutil`/`hlcg`);
- The temporary copy is a **bytewise** temp outside the managed slot-tracking:
  an explicit `initialize_data_node` + `finalize_data_node` pair in the call's
  init/done blocks owns the entire lifecycle (`ncal.copy_value_by_ref_para`);
  therefore prologue initialization, slot-reuse finalization, and a funclet do
  not duplicate user calls—the loop trace is byte-for-byte DCC;
- Inlining calls with such value parameters is forbidden: the inline path
  copies bytewise and would bypass `Assign` (`release=debug` after the gate);
- Reuse of a managed temp slot reinitializes records with an `Initialize`
  operator (`ncgbas`): the contract that `Copy` receives an initialized
  destination holds even on slot reuse.

Deliberate deviations (traces, not values; the Initialize↔Finalize balance is
strictly 1:1 on both sides): our `L := MakeRes` uses temp+move—honestly
finalizing the overwritten value and carrying two extra housekeeping
init/finalize calls; DCC writes `Result` in place and silently loses the old
value's `Finalize`—we do not reproduce that leak. The order in which local
arrays are finalized on scope exit differs (values match).

## Open-array and static-array status: fixed

The final remainder is closed. An **open array** of such records passed by value
copies element-by-element and in phases, as in DCC64: first `Initialize` all
copy elements, then user `Assign` all of them (`iii|iiiaaa…`); the receiving
side finalizes the copy in forward order before return. Mechanics:
`g_copyvaluepara_openarray` for such elements calls the `fpc_delphi_copy_array`
runtime loop (two phases using the existing `int_InitializeArray` + `int_copy`,
whose record-op is the user `Assign`) instead of bytewise `Move`; no
`fpc_addref_array` runs on top of it. A **static array** of such records (and a
parameter of that type) is covered by extending the predicate: static-array
wrappers are unwrapped on entry, and the parameter array goes through the
existing caller-side record path.

An exception midway through a copy follows the measured DCC leak model: a
raising `Assign` leaves the entire copy unfinalized; a raising `Initialize`
finalizes only the initialized prefix (that is already the `int_InitializeArray`
contract); finalization balance is not checked on those paths, while exact
traces are. An empty array calls nothing; `SetLength` of a dynamic array
initializes new elements through the operator in both. Inlining calls with such
open-array parameters is forbidden by the same gate as records (DCC does not
accept such `inline` at all—dvl-0020).
