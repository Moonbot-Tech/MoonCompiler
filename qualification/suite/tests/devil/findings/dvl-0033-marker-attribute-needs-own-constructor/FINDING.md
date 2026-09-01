# dvl-0033 — a marker attribute without its own constructor does not compile in any position

## Current status

Fixed in the RTL: `TCustomAttribute.Create` is public and inherited by a
marker class. Regression: `tests/test/cg/tmoonattributemarker1.pp`.

Found while investigating dvl-0032. It is a separate and more serious problem:
the failure is not at a position, but in the attribute itself.

## What happens

```pascal
type
  MarkAttribute = class(TCustomAttribute)
  end;

  TBox = class
  public
    [Mark] Slot: Integer;
  end;
```

| compiler | result |
|---|---|
| Delphi 12.2 | builds |
| ours | `Error: Wrong number of parameters specified for call to "Create"` |

The rejection is identical in **all** positions where the attribute parses at
all: before a type, field, property, or method. Merely declaring an attribute
class's own `constructor Create;` makes everything build. In other words, the
inherited parameterless `Create` from `TCustomAttribute` is not considered at
all when applying the attribute.

## Why this is costly

A marker class without its own constructor is the **primary** form for writing
an attribute:

```pascal
type
  MyIndexAttribute = class(TCustomAttribute);
```

Markers are declared this way in all Delphi DI containers, ORMs, serializers,
and test frameworks. Therefore any module using such attributes does not
compile here—it does not run incorrectly; it simply does not compile. A
workaround exists (add an empty constructor), but it requires changing foreign
code.

## Reproduction

`repro-standalone.dpr` is self-contained.

Through the suite: verdict-gate cases `attribute-marker-*`.

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: all reject it. With a declared
`constructor Create;` (even an empty one), all four positions compile; an
attribute with arguments (`[Mark('x')]`) also compiles when the matching
constructor exists. Exactly the “constructor inherited only” case diverges.
