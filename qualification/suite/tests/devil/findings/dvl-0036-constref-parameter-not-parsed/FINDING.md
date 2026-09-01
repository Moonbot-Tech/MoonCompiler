# dvl-0036 — the `const [ref]` parameter modifier is not parsed

Found while analysing dvl-0035; it is a separate defect because `const [ref]`
is an independent parameter-passing form, not part of record operators.

## Status

Fixed without a new ABI mechanism: both Delphi spellings, `const [ref]` and
`[ref] const`, map to the existing internal `constref`. The regression verifies
the actual address of a managed record and the read-only prohibition; the ObjFPC
control continues to reject Delphi syntax.

## What happens

```pascal
procedure Touch(const [ref] V: Integer);
begin
  WriteLn(V);
end;
```

| compiler | result |
|---|---|
| Delphi 12.2 | builds and prints `7` |
| ours | `Syntax error, "identifier" expected but "[" found` |

## Why this is costly

`const [ref]` means “pass by reference and promise not to modify.” Delphi may
pass a small ordinary `const` value in a register, whereas `[ref]` prohibits a
copy: the address must be the actual address of the caller's object. It is used
when the precise address matters—pointer comparison, passing a large record
without copying, or calling a foreign API that requires a pointer.

Moreover, `const [ref]` is a mandatory part of the `Assign` operator signature
(dvl-0035); without it, that half of the language remains unreachable even if
the operator itself is supported.

The rejection is syntactic, so the entire module does not compile.

## Reproduction

`repro-standalone.dpr` is self-contained.

Through the suite: verdict-gate cases `constref-parameter`,
`constref-record-parameter`.

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: all reject it. Ordinary
`const` parses normally; exactly the bracket following it causes the failure.
