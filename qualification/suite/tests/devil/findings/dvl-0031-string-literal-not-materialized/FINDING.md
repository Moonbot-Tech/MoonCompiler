# dvl-0031 — a string literal does not receive its own copy: refcount `-1`, writing to the buffer faults

Found by the `matrix` layer (the `refcount` passenger; after rotation of the
matrix slices, it reached this case for the first time) and decomposed by the
`lit` layer, which was written in the wake of this finding.

## What happens

```pascal
var
  G: AnsiString;
begin
  G := AnsiString('poke-me');
  PAnsiChar(G)[0] := 'X';   { Delphi: works. Ours: EAccessViolation }
```

When Delphi stores a literal, it puts an **independent heap copy** into the
variable: refcount 1, its own buffer, writable. We leave a pointer to the
constant in the image: refcount `-1` (“not counted”), with a read-only page.

The exact storage destination is the axis. The `lit` layer asks each storage
site three questions: its refcount, whether its buffer is writable, and
whether it shares memory with another occurrence of the same literal.

| storage site | ours | Delphi 12.2 |
|---|---|---|
| local variable | `-1`, write faults | `-1`, write faults — **match** |
| global variable | `-1`, faults | `1`, writable |
| object field | `-1`, faults | `1`, writable |
| global-record field | `-1`, faults | `1`, writable |
| dynamic-array element | `-1`, faults | `1`, writable |
| nested dynamic array | `-1`, faults | `1`, writable |
| static-array element | `-1`, faults | `1`, writable |
| `out` parameter | `-1`, faults | `1`, writable |
| function result | `-1`, faults | `1`, writable |
| closure-captured variable | `-1`, faults | `1`, writable |
| `threadvar` | `-1`, faults | `1`, writable |
| object field behind an interface | `-1`, faults | `1`, writable |

The rule fits in one line: **Delphi materializes a literal at every storage
destination except a simple local variable; we materialize it nowhere.**

The literal's written form does not affect this: an `AnsiString(...)`,
`RawByteString(...)`, or `UTF8String(...)` cast, an implicit assignment, a typed
constant, or concatenation of two literals all diverge in the same way. Only a
string genuinely built at runtime (`Copy`) does not diverge: both produce
refcount 1 and allow writes. This case deliberately belongs in the layer—it
shows that the instrument does not flag everything indiscriminately.

The third observation, identity, also diverges for a local: two occurrences of
one literal are the same buffer for us and different buffers in Delphi.

## Why this is costly

1. **A fault where Delphi works.** Filling a template in place, passing
   `PAnsiChar` to a C API that writes to the buffer, or changing a couple of
   bytes is routine in hot code. It works in Delphi for years; here it becomes
   an AV in production, at the most inconvenient point—on the first write to
   foreign memory.
2. **A shared buffer instead of a private one.** If the write does happen to
   succeed (the page is writable), it corrupts the literal for every occurrence
   in the program at once, because ours is the same memory.
3. **A silent branch change.** `If StringRefCount(S) = 1 then <write in place> else
   UniqueString(S)` never takes the fast branch for us: `-1` ≠ 1. Checks like
   this live in mormot, which is supplied here as the memory manager.

Our behaviour is cheaper in isolation—the literal is not copied. But the
compiler contract is Delphi 12.2 behaviour, not “better than Delphi.”

## Reproduction

`repro-standalone.dpr` is self-contained: Delphi prints `poked = Xoke-me`; ours
prints `poke raised EAccessViolation`.

The complete table is available through the layer:

```
run_devil_gate.py --seeds 5 --cases 60 --layers lit --profiles release --dcc ...
```

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: all four have `-1`; the
decision is made by the front end. A string built at runtime behaves identically
in both.

## Status: fixed

The DCC64 36.0 oracle refined the rule: materialization happens not “everywhere
except a simple local,” but **everywhere the storage outlives the current stack
frame**. A local static array, a local-record field, a nested record/array chain
above a local, and `with` on a local record remain shared at `-1`—like a simple
local; so does a value parameter (its slot belongs to the callee's frame).
Global variables, `threadvar`, object fields, dynamic arrays, heap records,
`var`/`out` parameters, `Result`, and closure-captured locals receive a copy.
Writing to the shared buffer faults in Delphi too—literals are stored in
read-only memory in both, and there was and is no divergence there.

The repair has two parts, following the Delphi `UStrAsg`/`UStrLAsg` pair:

- **Compiler** (`nld.pas`, assignment-helper selection): the classifier unwraps
  the target along the “static-array element → record field” chain to its root;
  if the root is a local (not `Result` and not captured) or a value parameter,
  the existing shared helper remains, otherwise `fpc_*_assign_global` is chosen.
  Selection happens in `pass_1`, when captures are already known.
- **RTL** (`astrings.inc`/`ustrings.inc`): `fpc_*_assign_global` on x86-64 has a
  three-instruction asm prologue: a source with `Ref>=0` tail-jumps to normal
  assignment (zero extra calls on the hot path), while `Ref<0` goes to a Pascal
  materializer that copies the header+payload and sets `Ref=1`. The source is
  checked at runtime rather than the RHS form; therefore the copy also happens
  for typed constants and for a literal that reaches a field through a `const`
  parameter in a setter.

The `lit` layer on seeds 1–5 against the DCC binary matched all 52 observations;
both `dvl-0031` entries were removed from `known_findings.json`—the layer's
identity probes compare an occurrence with a global, and the global now owns
its own copy in both. A deliberate residual boundary not measured by the layer:
two occurrences of the same literal in TWO stack locations share one read-only
buffer (the constant pool) for us, while Delphi uses two different ones; the
refcounts and write fault match, and string semantics do not change.

Inlining boundary: the “inline managed getter without a temp” optimization may
elide the materializing copy only when the source is proven not to carry
`Ref<0`—a fresh value or escaping storage that this repair itself keeps
materialized. A literal, string temp, or stack-chain source keeps the copy;
otherwise `StringRefCount` of an inlined `Result := 'lit'` would observably
diverge from Delphi (caught by the pin at O3).

Pin: `RTL-test/semantic/string_literal_materialize_semantic.dpr`—a matrix of
all storage destinations plus a mutation-isolation control; the pin is green
under DCC64 too.
