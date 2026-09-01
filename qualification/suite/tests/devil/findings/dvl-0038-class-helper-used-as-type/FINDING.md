# dvl-0038 — helper name as a type: we accept it, Delphi rejects it

Found while investigating helpers. Small but one-sided: code written here will
not compile in Delphi.

## What happens

```pascal
type
  TBox = class
  end;
  TBoxHelper = class helper for TBox
  public
    class var HelperShared: Integer;
  end;

begin
  TBoxHelper.HelperShared := 5;
```

| compiler | result |
|---|---|
| ours | builds and prints `5` |
| Delphi 12.2 | `E2018 Record, object or class type required` |

A helper in Delphi is not a type, but a set of members attached to another
type: it cannot be addressed by its own name, only through the type it helps.
We permit the helper name in a type position.

The reverse case is rejected by both, only with different wording: a static
helper method called through the helper name (`TBoxHelper.Ask`) compiles neither
there nor here.

## Why this is costly

On its own, not much: it is one-way portability. The significance is elsewhere:
a `class var` inside a helper becomes a reachable entity for us, meaning that
the helper gains state of its own, which it does not have in the Delphi model.
Code relying on this state has no Delphi equivalent at all—not “does not
compile,” but “cannot be expressed.”

## Reproduction

`repro-standalone.dpr` is self-contained.

Through the suite: verdict-gate case `helper-name-as-type`.

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`. Accessing helper members
through the type it helps (`TBox.Ask`) works identically in both.
