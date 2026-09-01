# dvl-0047 — fixed: `System.Integer` again matches language `Integer`

Found by the `resident` layer through arbitration with Delphi 12.2: the
`gen-comparer` stage diverged from the oracle. Narrowing it to the cause took
three probes and led to a compiler defect with a direct production consequence
in the RTL.

## What happens

The same cast produces different values depending on whether the type name is
namespace-qualified:

```pascal
var W: Word;
W := 65535;
WriteLn(Integer(W));         // 65535  - correct
WriteLn(System.Integer(W));  // -1     - sign extension
```

| Expression | Ours | Delphi 12.2 |
|---|---|---|
| `Integer(W)`, W=65535 | `65535` | `65535` |
| **`System.Integer(W)`, W=65535** | **`-1`** | `65535` |
| `System.Integer(W)`, W=32768 | `-32768` | `32768` |
| `System.Integer(W)`, W=32767 | `32767` | `32767` |
| `System.Int64(W)`, W=65535 | `65535` | `65535` |
| `System.Cardinal(W)`, W=65535 | `65535` | `65535` |
| `System.NativeInt(W)`, W=65535 | `65535` | `65535` |
| `System.Integer(B)`, B: Byte = 255 | `255` | `255` |

The defect boundaries are narrow, which makes it treacherous:

* only **`System.Integer`**—neighboring `System.Int64`, `System.Cardinal`,
  and `System.NativeInt` from the same value are correct;
* only a **16-bit unsigned source**—`Byte` is widened correctly;
* only the **upper half of the domain** (values ≥ 32768), so ordinary small
  numbers look correct;
* under **every profile**, including `debug`. This is parsing, not
  optimization: `-O` has no role;
* the spelling does not help—it breaks identically in an assignment, expression,
  and call argument.

## Why it is costly: `Word` sorting in the RTL is broken

The defect would not remain theoretical even if no one wrote `System.Integer`
by hand. The RTL writes it in exactly **two places**, both default comparers
(`packages/rtl-generics/src/generics.defaults.pas`):

```pascal
class function TCompare.UInt8(const ALeft, ARight: UInt8): Integer;
begin
  Result := System.Integer(ALeft) - System.Integer(ARight);
end;

class function TCompare.UInt16(const ALeft, ARight: UInt16): Integer;
begin
  Result := System.Integer(ALeft) - System.Integer(ARight);
end;
```

The 8-bit form survived; the 16-bit form did not. Consequently,
`TComparer<Word>.Default` returned the **wrong sign**:

| Comparison | Ours | Delphi |
|---|---|---|
| `Compare(65535, 1)` | `-2` (less!) | `65534` |
| `Compare(40000, 1)` | `-25537` | `39999` |
| `Compare(32768, 1)` | `-32769` | `32767` |
| `Compare(32767, 1)` | `32766` | `32766` |

`Compare` requires only the sign, and the sign here is opposite. Any sort or
binary search over `Word` therefore silently gets the wrong order:

```
TArray.Sort<Word>([1, 65535, 2, 40000, 3, 60000])
  ours:    40000 60000 65535 1 2 3     <- BROKEN
  Delphi:  1 2 3 40000 60000 65535
```

`Byte`, `Cardinal`, and `UInt64` sort correctly—only `Word` is broken.

## Where the defect is not

Checked and excluded:

* **type information is sound**: `GetTypeData(TypeInfo(Word))^.OrdType` =
  `otUWord`, `MinValue` = 0, `MaxValue` = 65535—everything matches Delphi;
* **comparer selection is sound**: `SelectIntegerComparer` correctly returns
  `Comparer_UInt16_Instance` for `otUWord`;
* **the RTL comparer body is written correctly**—it could not be more correct;
  the error is not in that code.

The compiler was at fault: it resolved two semantically identical names to
different types.

## Cause and repair

In the `System` source, `Integer` is historically declared as the bootstrap
alias `SmallInt`. In Object Pascal modes, the implicit `ObjPas` unit
overrides ordinary `Integer` to `LongInt` on every target wider than 16 bits.
Ordinary lookup saw that override, but explicit `System.Integer` bypassed it
and returned the original 16-bit alias. The cast was not the only faulty form:
a variable declared as `System.Integer` was two bytes wide and could not hold
65535.

The repair is at the common qualified-unit-lookup point. Only in modes loading
`ObjPas`, `System.Integer` resolves to the same 32-bit signed type as language
`Integer`; on a 16-bit target it remains 16-bit. TP/ISO and all other
`System` names are unchanged. The global `System` symbol table is not
rewritten: that prototype was broader than the cause and broke bootstrap
packages, so it was rejected.

Permanent regressions cover two layers:

* `tdelphiqualifiedinteger1` — size/range, casts, declarations, pointers,
  arrays, arguments, `var`/`out`, `Word` boundaries, and neighboring integer
  types;
* `tqualifiedintegercomparer1` — `TComparer<Word>` sign, sorting, and binary
  search, plus `Byte`/`Cardinal`/`UInt64` controls.

Both tests pass O-/O2/O3. Separate controls confirmed that ObjFPC gets a
four-byte `System.Integer` while TP retains a two-byte one.

## Relatives

This is the fourth known path of the same disease—loss of unsignedness when
crossing widths (dvl-0001, dvl-0026, dvl-0043, dvl-0045). It has two material
differences:

| | Earlier forms | dvl-0047 |
|---|---|---|
| Path | Cast, generic result, `with`, alias from another module | **Qualified type name** |
| Profile | `release` or `o2` | **All, including `debug`** |
| Consequence | A value in application code | **A broken RTL primitive** |

Earlier findings required someone to write affected code. Here, the affected
code was already written and lives in the standard library.

## Reproduction

* `probe/qualified.dpr` — qualified and unqualified casts side by side,
  fourteen value pairs;
* `probe/comparer.dpr` — `Compare` signs for narrow unsigned types and three
  sorts;
* `probe/widen.dpr` — separates responsibility: type information, widening,
  RTL body, and what the library ultimately returns.

All three build with the ordinary driver; the oracle is Delphi 12.2 `dcc64`
with `-U<lib\win64\release> -NSSystem`.

## What this says about coverage

The `resident` layer did not search for this defect and could not predict it:
it simply asked the default comparer whether its result for `($FFFF, 1)` had
the correct sign. The defect lives at the boundary between the compiler and its
own library, and can be seen only from a program using that library as ordinary
code—a code-generation check alone cannot catch it.
