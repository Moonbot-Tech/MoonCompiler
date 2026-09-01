# dvl-0043 — `release` loses unsigned narrowing for a value assigned inside `with`

This was the third path for the same disease as dvl-0001 and dvl-0026. The
first two went through an ordinary cast and a generic-method result; here the
value is assigned inside a `with` block over a record and narrowed outside it.

## What happens

```pascal
var
  Val: SmallInt;
  W1: TDvlBox;
begin
  W1.Fi32 := Integer(OpaqueI(1));
  with W1 do
  begin
    Val := SmallInt(-32767);
    if Fi32 <> 1 then
      DevilFailures := High(UInt64);
  end;
  DevilCheckU('dvl-gen-00109-nested', DvlRawi16(Val), UInt64($8001));
```

where `DvlRawi16(V: SmallInt): UInt64` is `UInt64(Word(V))`: an unsigned
narrowing to `Word` followed by widening again.

| Build | Result |
|---|---|
| `debug`, `o1`, `o2` | `$8001` — correct |
| Delphi 12.2 | `$8001` — correct |
| **`release`** | **`$FFFF8001`** |

The result is sign extension to 32 bits: narrowing to `Word` did not occur at
all. The signature matches dvl-0001 and dvl-0026.

## What it took to pin down

In isolation, the form **does not reproduce**. Five variants
(`tried-standalone.py`) were built and run under three profiles: with and
without `with`, with an empty `with`, with a constant field instead of an
opaque one, and with narrowing directly at the call site—all fifteen builds
return the correct answer.

The defect was therefore pinned down by **reverse minimization**
(`run_devil_bisect.py`), which cuts the environment rather than the case.
Protocol: `bisect-log.txt`. Result:

- **one `gen` layer** is sufficient; no neighbors are needed;
- **volume within the layer** is needed: the difference exists at 120 cases and
  disappears at 60.

The trigger is therefore not neighboring code but module size: as volume grows,
inlining and allocation decisions change, and at some threshold the narrowing
stops reaching code generation.

## Reproduction

```
run_devil_gate.py --seeds 24 --cases 120 --layers gen --profiles debug,release --dcc ...
```

The `dvl-gen-00109-nested` check turns red; `debug` and Delphi are green.
With `--cases 60`, the run is clean—the threshold lies between them.

## Relationship

dvl-0001 (ordinary cast and a module boundary), dvl-0026 (a generic-method
result), and dvl-0043 (assignment inside `with`) are three different paths to
one loss, and all three trigger only under full optimization. They must be fixed
together: a repair that closes one path leaves the other two, exactly as
dvl-0026 survived the dvl-0001 repair.

## Status: fixed by a common repair

`with` was not the cause; it changed register allocation and delivered the
code to the long-distance peephole `MOV const ... MOVZX/MOVSX`. The rule removed
the extension without normalizing the immediate to its original width. Common
normalization of 8/16/32-bit immediates closed dvl-0001, dvl-0026, and dvl-0043
together.

The exact discovery repro `seed=24/cases=120/gen` now agrees across all
profiles. The broader permanent gate uses seeds 1 and 24, 200 cases, layers
`expr,unary,fold,unit,gen`, and Debug/O1/O2/O3.
