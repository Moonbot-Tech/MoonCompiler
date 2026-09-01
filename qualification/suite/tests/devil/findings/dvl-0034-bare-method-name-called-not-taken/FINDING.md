# dvl-0034 — bare method name before `reference to`: we call it, Delphi takes its address

Found by the `capture` layer (the `field-of-object` form)—Delphi refused to
compile what we compiled and ran.

## What happens

```pascal
type
  TStep = reference to function: Integer;

  TBox = class
    function Make: TStep;   { factory: returns a closure }
  end;

var
  Step: TStep;
begin
  Step := Held.Make;        { no parentheses }
```

| compiler | interpretation | result |
|---|---|---|
| ours | calls `Make` and assigns its result | builds and works |
| Delphi 12.2 | takes the address of method `Make` | `E2010 Incompatible types: 'TStep' and 'Procedure of object'` |

The ambiguity is real: in Pascal, a parameterless function name on the right
side is either a call or a value, and the choice depends on the receiver type.
The receiver is a procedural type, so Delphi chooses “value” and fails because
a method pointer cannot be placed in a `reference to`. We choose “call.”

## Why this is costly

The form `Result := Factory.Make;` is normal notation for a closure factory. A
module written here will not compile in Delphi, and the repair is not cosmetic:
the author sees an error unrelated to the intent, about incompatible types, and
will look in the wrong place.

No reverse direction in which both sides compile and silently diverge was found:
for the classic `function: Integer of object` (the same construct without
`reference to`), both compilers take the address identically. The divergence
exists exactly where the receiver is `reference to`.

## Reproduction

`repro-standalone.dpr` is self-contained: ours prints `step = 1`; Delphi
returns `E2010`.

Through the suite: verdict-gate case `bare-method-into-reference`.

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: it is a call everywhere; this
is parsing. With parentheses (`Held.Make()`), both sides compile and behave
identically.
