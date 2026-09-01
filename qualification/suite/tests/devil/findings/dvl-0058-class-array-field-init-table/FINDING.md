# dvl-0058 — the class init table was blind to array fields of operator records

Found during the sixth audit pass (journal 5) while completing the read-through
of the MOP-offset-table consumer: `TObject.InitZeroedInstance` — construction of
**EVERY** class object — reads the “offset → Initialize operator” table and
calls the field operators. `write_mop_offset_table` writes the table by walking
`do_get_managementoperator_offset_list`, which skipped fields that were static
arrays of records; the fast `has_fields_with_mop` gate was already blind to array
wrappers while aggregating in `addfield`.

## What happened

A class with the field `Arr: array[0..1] of TRes` (TRes carries
Initialize/Finalize/Assign):

| | Create | read | Free |
|---|---|---|---|
| DCC64 | `iii` — all three fields | `100:100:100` | `f100f100f100` |
| ours (before the fix) | `i` — direct field only | `100:0:0` | `f0f0f100` |

The array elements were born dead (the Initialize contract was violated — zeros
instead of operator values) yet were honestly buried: `CleanupInstance` performs
a full RTTI walk, which understands tkArray. The Initialize↔Finalize asymmetry
was 1:1 → 1:3; an RAII record in a class array field released what it had not
acquired.

## Fix

Symmetric with fix 115f3918 (the type property is calculated during
construction; array wrappers are unwrapped at entry):

- `addfield`: all three aggregates (`has_fields_with_mop` ×2 and
  `fields_delphi_assign`) are calculated from the field's element type, unwrapped
  through static arrays — one loop for all of them;
- `do_get_managementoperator_offset_list`: an array field yields one entry per
  element (offset = fieldoffset + i·elemsize), nested arrays multiply the count,
  and the sub-walk of the element fields receives the same per-element offset.

The RTL table reader was unchanged — the origin of offsets is irrelevant to it.
The pin gained the `class array field init` axis
(`|iii|100:100:100|f100f100f100|`, green under DCC64 as well).

## Incidental boundary

The first run of the Devil RTTI layer with a DCC oracle showed only the known
dvl-0008 behavior on the **DCC binary itself** (its GetTypes does not find types
without explicit RTTI — a divergence in our favor; the registry does not yet
mask aggregate failures of the Delphi profile); our profiles retain one digest —
the RTTI-table fix introduced no regressions.

## Related sites of the same class (found by systematic grep)

After the init-table fix, every compiler consumer of `mop_initialize` was
checked for the same blind spot: “a carrier inside an array or aggregate is
invisible to the point check `typ=recorddef and mop in ...`”. Two more were
found and closed (both converted to the ready cached predicate
`has_non_trivial_value_init`):

- `ninl` (Default): the static `Default(T)` variable was declared read-only for
  an array and aggregate of operator records — unit initialization could not run
  their operators, and `Default(TPair)` / `Default(THolder)` returned zeros
  instead of Initialize values (probe/defval.dpr; the values diverged sharply
  from DCC64: 1 versus 100). The source is now initialized for every carrier.
- `ncgbas` (managed temporary-slot reuse): reinitialization for the slot's new
  occupant ran only for a record with its own operator — an array or aggregate
  temporary remained raw after the previous occupant was finalized. The fix is
  strictly extending: the predicate is broader, the action is the same (full
  RTL initialization understands arrays and nesting).

The `Default` assignment form was then closed by a separate fix. For the exact
`StaticArray := Default(StaticArray)`, the frontend calls a transactional runtime
helper: the fresh value is fully initialized in an aligned heap buffer, the old
destination is finalized, and ownership is transferred with one `Move`. Thus,
the elements receive the DCC value `100`, not the user `Assign` result `101`;
a complex destination is evaluated once, and exceptions and a large array leave
neither a stack temporary nor a lost owner. Two non-transactional variants were
rejected: element-by-element `Assign`, which changed semantics, and a raw stack
temporary, which reevaluated a complex destination and lost ownership on an
exception.
