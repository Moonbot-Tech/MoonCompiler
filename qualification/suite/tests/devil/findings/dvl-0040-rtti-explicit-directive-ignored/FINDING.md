# dvl-0040 — `{$RTTI EXPLICIT ...}` did not control table contents: we emitted what the author forbade

## Current status

Closed by a causal writer/runtime-facade repair. Default product RTTI does not
require a directive in application code, while `{$RTTI EXPLICIT ...}` now
precisely controls the contents of extended member tables and attribute payload.
Delphi/FPC runtime oracle: `RTL-test/semantic/attribute_rtti_semantic.dpr`.

Found through **reverse minimization**. For a day and a half the difference
appeared contextual—it existed only in the full program and disappeared when
the case was cut out, so an ordinary minimizer killed it. The new bisector cuts
the environment rather than the case: it reduced the program to two layers
(`decl` + `attr`, five cases) and identified `decl` as the cause. It then
became clear that `decl` left a directive behind, and that directive lived to
the end of the module.

## What happens

```pascal
{$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublic]) FIELDS([vcPublic])}
{$M+}
type
  TBox = class
  private
    FSlot: Integer;
  published
    [Mark(11)]
    property Slot: Integer read FSlot write FSlot;
  end;
{$M-}
```

The program reads class properties through `TRttiContext` and sums attribute
tags.

| Directive | Ours | Delphi 12.2 |
|---|---|---|
| Default | 1 property, 11 tag units | 1 property, 11 tag units |
| `EXPLICIT … PROPERTIES([vcPublic])` | 1 property, **11 tag units** | 1 property, **0 tag units** |
| Then restore `PROPERTIES([vcPublished])` | 1 property, 11 tag units | 1 property, 11 tag units |

In Delphi, the directive works: `published` visibility is outside the allowed
set, so attributes for that property are not written to the tables; restoring
the directive restores the attributes. In our implementation, the directive
changed nothing: tables were always complete.

## Why this is costly

`{$RTTI EXPLICIT ...}` has two purposes, and both were broken here:

1. **Size.** Extended RTTI tables are a material part of a binary; narrowing
   visibility trims them. Our program carried complete tables no matter how
   narrowly the author specified them.
2. **Concealment.** The directive hides internals from foreign code that walks
   RTTI. In our implementation, hidden members remained visible, so the
   guarantee on which the author relied was not met.

The error is silent: no error or warning occurs, and the difference is visible
only to code that deliberately reads the tables or compares sizes.

Relationship: dvl-0037 is the same subsystem from the other end. There we
**did not emit** attributes that Delphi emits (fields, methods, `public`
properties); here we **emitted** attributes that Delphi intentionally removes.
The table contents therefore did not follow the rules at all, rather than being
shifted in one direction.

## Reproduction

`repro-standalone.dpr` is self-contained: it produces `tags = 11` for us and
`tags = 0` for Delphi.

Through the suite: case `dvl-attr-rtti-explicit-public-readback`.

## Boundaries

Checked under `debug`, `o1`, `o2`, and `release`—identically in every
case, because this is table generation. The directive applies to the end of the
module, which is why it propagated from one layer into another and made the
difference appear “contextual.” The generator's `decl` layer now restores the
directive state immediately after its case so it cannot taint neighbors; the
check itself is a separate case in the `attr` layer.

## Status: fixed

The DCC64 model captured by the repro is that the directive controls the
**attribute payload**, while enumeration of a published property remains the
classic `{$M+}` contract and is not disabled. With
`EXPLICIT PROPERTIES([vcPublic])`, the published property remains in
`GetProperties` (1 property), but has 0 tag units; restoring
`PROPERTIES([vcPublished])` restores the tags.

Writer repair (`ncgrtti`):

- for a classic property record, the attribute-table reference is cleared when
  the definition has an inherited RTTI directive and the property's visibility
  is outside the `PROPERTIES` set; the plain profile without directives is
  unaffected;
- in the extended property-table visibility set, `published` is included
  unconditionally for classes, so the property remains enumerable while its
  attributes are trimmed by the rule above.

Pin: `RTL-test/semantic/attribute_rtti_semantic.dpr` (green under DCC64 too).
The registry entry was removed.
