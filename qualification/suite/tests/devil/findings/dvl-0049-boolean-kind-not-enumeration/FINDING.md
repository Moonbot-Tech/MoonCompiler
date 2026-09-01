# dvl-0049 — Boolean type information is a separate kind, not an enumeration: Delphi RTTI traversals skip it

## Current status

The product `Rtti` facade is fixed: `TRttiType.TypeKind`, `TValue.Kind`,
and `TRttiEnumerationType` present Boolean as Delphi `tkEnumeration`. Raw
`PTypeInfo.Kind` remains FPC `tkBool`, because its type-data layout is
incompatible with the Delphi enumeration layout; the complete raw ABI is an
accepted exact boundary, not a live TODO.

Owner decision (2026-08-23): do not repair the raw ABI because no product
consumer exists. MoonBot audit: all Boolean RTTI machinery for strategies and
MoonProto sync (`Strategies.pas`, `MoonProto/StrategySerializer.pas`) goes
through the facade's `TRttiField.FieldType.TypeKind`, plus comparison
`FieldType.Handle = TypeInfo(Boolean)`—a pointer comparison indifferent to
kind. The only raw call (`GetEnumName` in `Helpers.TEnumConverter`) applies
only to genuine enumerations. mORMot reads raw `Kind` directly, but has its
own FPC branches for `tkBool`. Return this repair to the plan only if a real
raw consumer appears (foreign Delphi-only code with
`PropInfo^.PropType^.Kind`).

Found by the `resident` layer, `gen-kinds` and `rtl-type-info` stages,
through arbitration with Delphi 12.2.

## What happens

| Type | Ours `Ord(Kind)` | Delphi `Ord(Kind)` |
|---|---|---|
| `Boolean` | `18` (`tkBool`) | `3` (`tkEnumeration`) |
| `ByteBool` | `18` | `3` |
| `LongBool` | `18` | `3` |

Our Boolean types have their own `tkBool` kind; Delphi has no such kind, and
there Boolean is a special case of enumeration. The check
`Info^.Kind = tkEnumeration` is `False` for us and `True` for Delphi.

The numeric values of kinds also differ between us and Delphi for other types
(`Int64`, `string`, `AnsiString`), but that is harmless: code uses kind
names rather than numbers. Boolean differs not by number but by **membership of
a kind**, which changes program behavior.

## Why this is costly

Walking properties through RTTI is ordinary work for a serializer, settings
editor, or scripting bridge. Canonical Delphi code is:

```pascal
case PropInfo^.PropType^.Kind of
  tkInteger, tkEnumeration:  { both enumerations and Boolean arrive here }
    Value := GetOrdProp(Instance, PropInfo);
  tkUString:
    ...
end;
```

In Delphi, a Boolean property follows the `tkEnumeration` branch. For us it
matches no branch and silently falls out of traversal: it is not serialized,
displayed, or transferred. No error or warning occurs; the property simply
appears not to exist.

The reverse is also true: code written for us with a `tkBool` branch will not
compile in Delphi, which has no such constant.

## What it is not

This is neither a calculation error nor data corruption: Boolean values
themselves are correct, and `GetOrdProp`/`SetOrdProp` work on them. Only the
classification by which foreign code decides how to treat a field differs.

## Reproduction

`probe/rest.dpr`, `--- kind of Boolean` section. It builds with the ordinary
driver; the oracle is Delphi 12.2 `dcc64` with
`-U<lib\win64\release> -NSSystem`.
