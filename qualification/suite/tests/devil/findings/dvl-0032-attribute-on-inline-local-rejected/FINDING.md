# dvl-0032 — attribute on an inline variable: Delphi builds it, we reject it

Found by the verdict gate, case `attribute-on-local-variable`. This is a
**false reject**: a valid Delphi 12.2 program our compiler does not accept.

## What happens

```pascal
type
  MarkAttribute = class(TCustomAttribute)
  end;

begin
  var [Mark] Slot: Integer;
  Slot := 1;
  WriteLn(Slot);
end.
```

| compiler | result |
|---|---|
| Delphi 12.2 | builds and prints `1` |
| ours | `Syntax error, "identifier" expected but "[" found` |

An attribute before an inline-variable name is part of Delphi syntax (the same
`[Attr]` form used before a field, parameter, or type). We parse the position as
a name declaration and stumble on the bracket; the form is not parsed at all,
rather than being rejected semantically.

## Why this is costly

The rejection is hard: the entire file does not compile. One such line in a
foreign module is enough for a project that builds in Delphi to become
impossible to build here. There is no source workaround except removing the
attribute, which means changing foreign code.

Attributes on local variables are not exotic: DI containers, serializers, and
test frameworks read them through RTTI.

## Reproduction

`repro-standalone.dpr` is self-contained.

Through the suite: verdict-gate cases `attribute-*-parameter`,
`attribute-*-inline-var`, `attribute-on-class-var`.

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: all reject it; this is
parsing, not code generation. Every position in which Delphi permits an
attribute was checked:

| position | our parse result |
|---|---|
| before a type | parses |
| before a class field | parses |
| before a property | parses |
| before a method | parses |
| **before a parameter** | **syntax error** |
| **before an inline variable** | **syntax error** |
| **before a `class var`** | **attribute is not bound** |

Thus three positions fail. Separately, dvl-0033 applies: an attribute without
its own constructor is rejected in **all** positions, including those that
parse here.

## Status: fixed

All three positions parse and match DCC64 (matrix: an attribute on a parameter
as a single attribute, with constructor arguments, and above a name list; on an
inline variable, typed and inferred; on a `class var`; controls `const [ref]`
and `[ref] const` are unaffected):

- **Parameters** (`pdecsub.parse_parameter_dec`): the bracket before the
  parameter is disambiguated by its contents—exactly `[ref]` remains a modifier
  (as in Delphi, where it has priority); everything else is parsed as attributes
  (`parse_rttiattributes` learned to accept an already consumed bracket) and
  bound to parameter symbols—following the field precedent: the first ones by
  copy, the last by ownership transfer. The extended-RTTI writer will pick up
  the binding in cluster 4;
- **Inline variables** (`pstatmnt.inline_var_statement`): attributes before the
  name are parsed and bound to the local; locals have no RTTI—as in Delphi, the
  attribute simply lives on the symbol;
- **`class var`** (`pdecobj`): two `check_unbound_attributes` calls caused the
  rejection—in `parse_class` for non-methods and in a class member's `_VAR`
  branch; both were removed, and attributes now reach regular field binding
  after `read_record_fields`.

Attributes in the new positions are parsed under `block_type=bt_type`—the
attribute name must resolve as a type, which statement/var contexts do not
provide on their own.

The verdict gate against DCC: 82 cases, zero findings; all five `dvl-0032`
registry entries expired and were removed. Pin:
`RTL-test/semantic/attribute_positions_semantic.dpr` (without `{$mode}`—the
directive resets product modeswitches, while the pin needs inline vars).
