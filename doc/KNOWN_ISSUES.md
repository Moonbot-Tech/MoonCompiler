# Known Deviations

This list defines the observable boundaries of the supported MoonCompiler
profile: Delphi-compatible source, Win64 and Linux x86-64, Debug and Release.
Every deviation is locked down by an exact test; any broader crash, miscompile,
or new outcome remains a regression.

Deferred performance work is listed in the [Backlog](BACKLOG.md).

## Unsupported `System.JSON.Builders`

The imported `vcl-compat` unit is not yet part of the supported Delphi RTL
surface. Its API is declared, but the implementation is incomplete:
`TJSONCollectionBuilder.AsJSON` unconditionally returns an empty string,
`WriteJSON` accepts unchecked raw input, several typed getters return zero/empty
stubs, and `AsRoot` does not switch the root collection. This is inherited from
the source base, not a MoonCompiler regression.

Product mORMot uses its own JSON API and does not call this unit. Until a
separate implementation and Delphi 12.2 runtime oracles exist,
`System.JSON.Builders` must not be considered functional merely because the
package compiles.

## Exact boundaries of the broad RTL API surface

These branches are publicly declared by the imported RTL, but are not used by
MoonBot or Arbitrage and are outside the product's stated Delphi parity:

- `TFMTBcdFactory.Cast` does not convert an arbitrary `Variant` to FMTBcd and
  ends with `EBCDNotImplementedException`. The reverse path from the custom
  BCD Variant through `CastTo` is implemented;
- `TUCA_VariableKind.ucaIgnoreSP` has no dedicated Unicode Collation Algorithm:
  it currently executes the same shifted path as `ucaShifted`;
- `TMessageClientList.Clear` is forbidden during active dispatch/update.
  Safe removal of an individual listener is already implemented through delayed
  disable, but mutation-safe bulk clearing inside a callback is not claimed.

These are neither hidden green stubs nor pre-release blockers. If application
code begins to use any of these forms, it first needs a Delphi 12.2 runtime
oracle and a separate causal repair. SHA-512/224 and SHA-512/256 no longer
belong here: they are implemented and checked with exact digest/HMAC vectors.

## Eight exact compile-time limitations

These forms may currently terminate the compiler abnormally or be rejected by
it. No local repair has been proven that preserves neighboring forms, PPU/ABI,
and machine behavior on both target platforms. The limitation applies only to
the listed fixtures and does not permit a broader compiler crash.

- **FPC #41541** — nested type in a generic class when loaded from PPU;
- **FPC #41594** — nested generic types in a generic method signature;
- **FPC #41598** — self-referential managed generic record;
- **FPC #41614** — overload between a generic array and an open array;
- **FPC #41679** — self-specialized generic record with a nested record type.
- **QP-32** — a nested generic callback returns another generic
  `reference to function`; during specialization the scanner loses the outer
  declaration boundary and reads `reference` as a procedure directive. Exact
  repro: `qualification/suite/fixtures/tracker/qp-32/qp_32.dpr`.
- **QP-53** — a Delphi-compatible nested specialization of a generic record
  inside an aggregate. Simply removing the nested-generic guard in Delphi mode
  causes a compiler AV, so the guard is not relaxed without a complete
  ownership/replay repair. Exact repro:
  `qualification/suite/fixtures/tracker/qp-53/qp_53.dpr`.
- **MB-06** — `Random(High(UInt64))` compiles in Delphi 12.2 with a warning
  about a constant out of range, but MoonCompiler cannot select an overload.
  Automatically narrowing the argument or adding a new overload would change
  the general semantics of an out-of-range untyped constant expression. Until
  that semantic is proven for adjacent overload sets, the form remains an
  explicit deviation. Exact repro:
  `qualification/suite/fixtures/tracker/mb-06/mb_06.dpr`; the tracker requires
  the precise diagnostic `Can't determine which overloaded function to call`.

The allowance applies only to the exact repros in the test corpus. It does not
permit a runtime miscompile, a broader compiler crash, or use of the form in
production code.

## Devil: accepted deviations

After causal analysis, the following Devil differences are accepted as explicit
boundaries rather than unfinished repairs. Their checks remain in the system and
must produce exactly the registered result; a new error kind or an unexpected
expansion of the form is a regression.

| ID | Why it is not fixed |
|---|---|
| `dvl-0004` | FPC keeps one consistent raw domain for C-style booleans; the context-dependent Delphi payloads `1/-1` are described below. |
| `dvl-0006`, `dvl-0009`, `dvl-0010` | The measured Delphi result contradicts mathematics or Delphi itself; a correct compiler must not be fitted to it. |
| `dvl-0008` | The static `TRttiContext.GetTypes` deliberately enumerates more linked types than Delphi because the product needs this catalog. |
| `dvl-0014` | RTTI names reflect the real FPC aliases (`UnicodeString`, `AnsiString`); the logical type and layout are not lost. |
| `dvl-0016`, `dvl-0027` | An untyped real literal in an ambiguous `Double/Currency` context is not used by the product; a general repair would require changing literal typing rules. |
| `dvl-0020`, `dvl-0024`, `dvl-0025`, `dvl-0034`, `dvl-0038` | MoonCompiler accepts an FPC extension that Delphi rejects. This is not a miscompile and does not hinder Delphi-compatible source. |
| `dvl-0021`, `dvl-0022` | The rare Delphi forms `varargs` without `external` and an element outside the `set` domain are not used by the product; no safe local repair has been proven. |
| `dvl-0023` | An explicit source `{$mode ...}` directive changes the mode after driver keys under FPC rules. Product sources must use the documented Delphi profile. |
| `dvl-0049` | The public `Rtti` facade exposes Boolean as Delphi `tkEnumeration`, but raw `PTypeInfo.Kind` retains FPC `tkBool` and its consistent storage layout. Replacing one kind byte would make type data internally contradictory; there are no product raw consumers, and mORMot has its own `tkBool` branch. |
| `dvl-0056` | Two side-effecting functions marked `inline` in one expression are evaluated sequentially, like the same non-inlined calls. DCC64 first executes the side effect of both inlined forms and thereby changes observable semantics because of `inline`; MoonCompiler preserves the sequential evaluation of the non-inlined form. |
| `dvl-0069` | Ordinary call arguments are evaluated right to left, while DCC64 evaluates them left to right. The language does not promise an order, so the difference is an explicit boundary. Dependent state accesses are evaluated in separate statements. |

## Accepted Delphi/FPC runtime differences

### Generic `TypeInfo(T)` for a sparse enum

Delphi 12.2 returns `nil` for generic `TypeInfo(T)` when an enum has gaps in its
ordinal range. An attempt to return an identity-only descriptor was rejected: it
produced a formally non-nil `PTypeInfo`, but without a consistent name table
(`GetEnumNameCount=-1`), and an ordinary consumer could read past its boundary.

The compiler therefore preserves Delphi's `nil` behavior. This cannot be fixed
with partial RTTI: if such support becomes necessary, it needs a full coherent
contract for `PTypeInfo`, `TTypeData`, the ordinal/name map, and all standard
consumers.

### Raw Variant carrier for `Char`/`WideChar`

In a late-bound Variant call, Delphi 12.2 Win64 passes `Char` and `WideChar` as
`varOleStr`. The Linux RTL does not use a Windows BSTR carrier and passes the
same text as `varUString`. Neither path now leaves the original scalar `vtChar`
or `vtWideChar`, but a custom `TInvokeableVariantType` that reads raw `VType`
will observe the platform difference. The exact oracle is in
`qualification/suite/tests/smoke/variant_char_dispatch.pas`; replacing the Linux
carrier with `varOleStr` without a separate Variant ABI audit is forbidden.

### Negating an unordered float comparison

For NaN, FPC and Delphi materialize some forms of `not (A < B)` and their
equivalent braid/mux transformations differently. The repair was rejected: it
would change general IEEE/optimizer semantics for a form unused by the product.

Omni retains five red names:

- `fb1-nan-not-ge`;
- `fb1-nan-not-lt`;
- `fb3-braid-demorgan`;
- `fb3-ord-complement-sum`;
- `fb3-ord-mux-nan`.

### `-0.0 + +0.0`

Delphi preserves negative zero in the measured expression, while FPC produces
positive zero. The fix was rejected as too broad a change to floating arithmetic
for a difference unused by the product. Check: `fb3-neg-zero-plus-zero`.

This does not apply to conditional selection through `<=`: the incorrect branch
choice for `+0/-0` is fixed separately and checked by `tfloatminselect1.pp`.

### Inconsistent `Double` rounding in text APIs

`FormatFloat` and the `Format`/`FloatToStrF`/`Str` family currently use two
different decimal-digit generators. Boundary binary64 values can therefore
round differently: for example, `2.005` with two digits yields `2.00` through
`FormatFloat` and `2.01` through the other three paths, while `1.005` yields
`1.00` and `1.01`, respectively. Negative zero is also not fully consistent.

This is not a local error in one formatter. `FormatFloat` rounds the exact
binary value, while the older common `Str` path first builds a shortened decimal
representation. Delphi 12.2 is itself not a single oracle for every detail:
three formatting APIs suppress `-0.00`, while `Str` preserves its sign. Replacing
one rounding point would therefore only move the discrepancy to another API.

A safe repair is deferred until a separate complete matrix exists: all finite
bit patterns around decimal half-boundaries, precision/width,
scientific/fixed/general, locale separators, `NaN`/`Inf`/signed zero,
Win64/Linux, and a Delphi oracle. Then all four APIs must converge on one chosen
decimal core; until then the discrepancy is known and is not disguised as exact
Delphi parity.

### Layout of an anonymous variant part of a record

Delphi and FPC differ in two measured offset/layout forms of an anonymous
variant part. Current MoonBot, Arbitrage, and pinned mORMot have no such layout
contracts; a partial ABI repair is riskier than the known limitation.

Checks: `fty-anon-varpart-arm-hi`, `fty-anon-varpart-arm-lo`. The limitation
must be reconsidered before adding a library with binary record ABI.

### `Currency` with an untyped real literal

A mixed expression of `Currency` and an untyped floating literal is not typed
as it is in Delphi. The product does not use this form; exact `Abs(Currency)`
is already fixed without a float conversion. Check: `zoo-stoned-cur-litfloat`.

### Runtime inline `const` as a `var` argument

Delphi 12.2 forbids direct assignment to a runtime inline `const`, but permits
passing the same binding to a `var` parameter with a warning and thereby
modifying it. MoonCompiler keeps consistent read-only semantics and rejects the
passage. The form is not used in product source; we will not weaken protection
solely for this contradictory Delphi behavior. Exact check:
`qualification/suite/tests/smoke/inline_const_var_parameter_rejected.pas`; the
service gate runs it in Debug/O2/O3 on Linux and Win64.

### Dynamically loaded packages in `TRttiContext.GetTypes`

The static catalog, linked units, `DropContext`, and thread matrix are qualified
for Linux x86-64 and Win64 x86-64 executables. The lifetime of tables from
loaded/unloaded packages, interposition, and removal of their type info are not
implemented. MoonBot and Arbitrage build as static executables and do not cross
this boundary. If runtime-loaded packages appear, they need a separate
registration/unload contract; the current global table must not silently be
considered sufficient.

### Lifetime of repeated function-result temporaries

In an expression where a function returns a managed interface multiple times
and one recipient is subsequently cleared, Delphi may retain two hidden results
until the end of the expression/scope, while FPC releases one sooner. In the
measured oracle, after `B := nil` Delphi keeps `Alive=2`, FPC keeps `Alive=1`;
by scope exit both implementations destroy every object.

This is neither a leak nor a use-after-free: only the observable lifetime point
of a hidden result temporary differs. MoonBot, Arbitrage, and pinned mORMot have
no code that depends on such an intermediate refcount. Broadening the general
rules of function-result ownership for this difference is riskier than the known
deviation. The boundary is controlled by managed tuple/function-result form tests
in `tests/test/cg/tdelphilocalfinalizeforms1.pp`.

### `Ord` and explicit logic over C-style booleans

In Delphi 12.2 the `ByteBool`/`WordBool`/`LongBool` domain is internally
heterogeneous. Runtime `Ord(WordBool(True))` is sign-extended in a 32-bit
context, but unsigned in some 64-bit contexts. Explicit `and`/`or`/`xor` over
C-style Boolean variables additionally materializes Delphi `True` with payload
`1`, whereas the consistent FPC model retains payload `-1`. The logical value is
the same; the difference is observable only through `Ord`, a cast, or arithmetic
over the raw result.

MoonCompiler deliberately keeps one consistent signed domain, without adding
context-dependent extension or separate rules for explicit bitwise operations.
Comparisons `=`/`<>`, constant forms, and ordinary `Boolean` match Delphi. The
exact boundary is locked down in
`RTL-test/semantic/cbool_ord_domain_semantic.dpr` and runs in Debug/O2/O3.

### The static `TRttiContext.GetTypes` catalog is broader than Delphi's

MoonCompiler enumerates some linked types in its static executable catalog that
Delphi 12.2 does not return through `TRttiContext.GetTypes`. This is an
intentional product contract: the catalog is needed for automatic discovery of
command types and replaces manually duplicating Pascal declarations in a
registry. Narrowing it to Delphi visibility would remove used types. Static
executables, threads, and `DropContext` are checked by RTTI gates on Linux
x86-64 and Win64; dynamically loaded packages remain the separate boundary
described above.

## `Extended` on Linux

Pascal `Extended` remains a 10-byte x87 type, whereas Delphi 12.2 Win64 uses
8 bytes and Double precision. `Extended` therefore must not be used in binary
protocols, persisted/raw records, shared memory, or an ABI that must match
Delphi. Use explicit `Double` for such data.

This cannot safely be repaired by one size constant: the type is coupled to the
RTL ABI, `PExtended`, Math, and `fldt/fstpt`. A partial repair is deliberately
forbidden.

At the same time, Delphi-mode results of `Int`, `Frac`, `Exp`, `Ln`, `Sin`,
`Cos`, `ArcTan`, and `Sqrt` already receive the measured Delphi result type and
precision boundary; explicit SysV `CExtended` remains 80-bit.

## Two narrow Delphi forms in the upstream core

Two additional forms reproduce identically in O2/O3 and are absent from
MoonBot, Arbitrage, and product mORMot:

- `webtbs/tw40453.pp` — `generic set of T` inside a generic procedure conflicts
  with the `System` definition;
- `webtbs/tw41282.pp` — a nested procedure capturing `var ShortString` causes
  internal error `200409241`.

They did not appear during final qualification: the upstream expectation had
already recorded them as existing defects. Under the accepted public boundary,
they remain exact Known Deviations and require a separate causal repair if such a
form appears in product code or a dependency.
