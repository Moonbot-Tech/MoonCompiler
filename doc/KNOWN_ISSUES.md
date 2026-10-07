# Known Deviations

This file contains only observable boundaries of the supported MoonCompiler
profile: Delphi-compatible source on Win64 and Linux x86-64 in Debug and
Release, and, in the last section, the exact environment failures the
qualification accepts. A compiler crash, miscompile, ABI break, or build
failure outside the exact cases below remains a regression. Deferred speed work
belongs in the [Backlog](BACKLOG.md).

## Unsupported RTL surface

### `TUCA_VariableKind.ucaIgnoreSP`

`ucaIgnoreSP` currently follows the same Unicode Collation Algorithm path as
`ucaShifted`; it has no separate implementation. The other UCA modes are not
covered by this limitation.

## Exact compile-time limitations

These forms are pinned by standalone fixtures. The accepted boundary applies
only to the named form and outcome; it does not permit a broader compiler
failure.

| Form | Current boundary |
|---|---|
| FPC #41541 | A generic nested type loaded from a PPU can terminate the compiler internally. |
| FPC #41594 | Nested generic types in a generic method signature can terminate the compiler internally. |
| FPC #41598 | A self-referential managed generic record terminates the Linux x86-64 compiler internally; the current Win64 compiler accepts the fixture. |
| FPC #41614 | An overload between a generic array and an open array is rejected because the implementation header is not matched to its declaration. |
| FPC #41679 | A self-specialized generic record with a nested record type terminates the Linux x86-64 compiler internally; the current Win64 compiler accepts the fixture. |
| QP-32 | A nested generic callback returning another generic `reference to function` is rejected after the specialization scanner loses the outer declaration boundary. [Fixture](../qualification/suite/fixtures/tracker/qp-32/qp_32.dpr). |
| QP-53 | A nested specialization of a generic record inside an aggregate remains behind a fail-closed guard; merely removing the guard causes a compiler AV. [Fixture](../qualification/suite/fixtures/tracker/qp-53/qp_53.dpr). |
| MB-06 | `Random(High(UInt64))` cannot select an overload. Narrowing the untyped out-of-range constant automatically would change general overload semantics. [Fixture](../qualification/suite/fixtures/tracker/mb-06/mb_06.dpr). |
| `tw40453.pp` | `generic set of T` inside a generic procedure conflicts with the `System` definition at O2/O3. |
| `tw41282.pp` | A nested procedure capturing `var ShortString` causes internal error `200409241` at O2/O3. |
| `-Fa<unit>` without a PPU | A unit named with `-Fa` that has no compiled PPU on the unit path and must be compiled from its source ends in internal error `2026032615` (`ctask.pas`, `finishmodule` → `do_recompile`), with every compiler of the RTL profile stand and the product toolchain alike. The product runtime prefix (`-Fafpwinmonitor` and the Linux units) always has installed PPUs and is not affected; a program that needs such a unit lists it in `uses` instead. |

The five FPC issue fixtures are in
`qualification/suite/fixtures/known`; the two `tw*` fixtures are inherited
from `tests/webtbs`.

## Accepted language and runtime differences

These results are intentional boundaries, not unfixed wrong-code. Devil keeps
the exact forms registered, so an expansion or a different failure remains a
regression.

| Surface | Boundary |
|---|---|
| C-style Boolean payload and raw RTTI (`dvl-0004`, `dvl-0049`) | MoonCompiler keeps one consistent signed `ByteBool`/`WordBool`/`LongBool` domain. The public `Rtti` facade reports Delphi `tkEnumeration`, while raw `PTypeInfo.Kind` remains FPC `tkBool` so its storage metadata stays coherent. Raw `Ord`/bitwise payloads can therefore differ from Delphi although logical comparisons agree. |
| Delphi oracle inconsistencies (`dvl-0006`, `dvl-0009`, `dvl-0010`) | The measured Delphi result contradicts mathematics or another Delphi form; MoonCompiler is not fitted to the inconsistent result. |
| Static `TRttiContext.GetTypes` (`dvl-0008`) | The static executable catalogue deliberately includes more linked types than Delphi because automatic command discovery consumes them. |
| RTTI alias names (`dvl-0014`) | Names expose the real FPC aliases (`UnicodeString`, `AnsiString`); type identity and layout are preserved. |
| Ambiguous untyped real literals (`dvl-0016`, `dvl-0027`) | A `Double`/`Currency` overload or expression can be resolved differently. Product code uses an explicit type in this rare ambiguous form. |
| Accepted FPC syntax (`dvl-0020`, `dvl-0024`, `dvl-0025`, `dvl-0034`, `dvl-0038`) | MoonCompiler accepts several FPC extensions that Delphi rejects. This does not alter valid Delphi-compatible source. |
| Rare rejected forms (`dvl-0021`, `dvl-0022`) | `varargs` without `external` and an element outside a `set` domain are not supported product forms. |
| Explicit source mode (`dvl-0023`) | A source-level `{$mode ...}` directive naming a mode other than Delphi (`objfpc`, `fpc`, `tp`, ...) switches that unit to it under FPC rules; `String` stays Unicode. `{$mode delphi}` is a no-op while the product configuration's Delphi profile is active, and `{$mode delphiunicode}` only adds the system source code page, as in Delphi (see [Compiler Fixes](COMPILER_FIXES.md#mode-delphi-repeated-inside-a-unit)). |
| Side effects and `inline` (`dvl-0056`) | Two side-effecting calls retain the same sequential semantics whether or not they inline; DCC64 changes the measured order after inlining. |
| Call argument order (`dvl-0069`) | Ordinary arguments are evaluated right to left, while DCC64 currently evaluates them left to right. Pascal does not define the order; dependent side effects must be split into statements. |
| Case-insensitive text search of plain ASCII (`AnsiSameText`, `StartsText`, `EndsText`, `ContainsText`, `ReplaceText`, `StringReplace` with `rfIgnoreCase`, `TStringList.IndexOf`/`IndexOfName` with `UseLocale`) | Text made only of printable ASCII (`$20..$7E`) is compared by ASCII case folding without a locale call; everything else goes through the locale as before. On Windows this is exactly what `CompareStringW(NORM_IGNORECASE)` and `LCMapStringW(LCMAP_UPPERCASE)` answer for such text in every locale, Turkish and Azeri included (the RTL does not pass the linguistic-casing flags). On Linux the RTL folds through `towupper` of the process locale, and under `tr_TR`/`az_AZ` that maps `i` to a dotted capital I: there `AnsiSameText('i', 'I')` is `True` in MoonCompiler and `False` in the locale routine. |

### Variant text carrier

In a late-bound Variant call, Delphi 12.2 and MoonCompiler/Win64 carry `Char`
and `WideChar` as `varOleStr`; Linux uses `varUString` because its RTL has no
Windows BSTR ABI. The text is identical, but a custom `TInvokeableVariantType`
that reads raw `VType` can observe the carrier. The exact oracle is
[`variant_char_dispatch.pas`](../qualification/suite/tests/smoke/variant_char_dispatch.pas).

### Floating-point edge cases

- `RoundTo` is exact for the binary input under the supported nearest/even FP
  environment, including decimal half-boundaries, values outside `Int64`,
  subnormals, signed zero, and the finite limits of `Single`, `Double`, and
  native `Extended`. Code that directly changes the hardware rounding or
  denormal controls must restore them before calling the product RTL; reading
  that state on every ordinary call was rejected because it doubled the hot
  path cost. The wider foreign-state oracle remains in
  [`numeric_edge_contracts.pas`](../qualification/suite/tests/research/numeric_edge_contracts.pas).
- `Mean`, `Variance`, and `StdDev` are qualified for ordinary finite server
  data. Same-sign values whose intermediate sum overflows, exact cancellation
  of extreme magnitudes, subnormal residues, and externally modified x87/SSE
  control state may differ from an exact rational calculation. Their direct
  algorithms deliberately avoid a software exact/scaled wrapper on every
  ordinary call. `Norm` keeps its separate scaled sum-of-squares repair because
  it avoids overflow without slowing the normal path. The same research probe
  preserves the exact and altered-FPU-state counterexamples.
- Some negated unordered comparisons over NaN differ from Delphi. Omni pins
  the five `fb1/fb3` forms; general IEEE optimizer semantics remain unchanged
  for those unused expressions.
- `-0.0 + +0.0` becomes positive zero, while Delphi preserves negative zero in
  the measured expression. Ordinary conditional selection over `+0/-0` is
  fixed and is not part of this boundary.
- `FormatFloat` and the `Format`/`FloatToStrF`/`Str` family use different digit
  generators, so binary64 half-boundaries and negative zero are not rendered
  uniformly. A safe repair requires one decimal core and a complete
  cross-API, cross-platform matrix; Delphi itself is not consistent across all
  four APIs. This work remains in the [Backlog](BACKLOG.md).

### Record, lifetime, and RTTI boundaries

- Two anonymous variant-record forms have different offsets from Delphi:
  `fty-anon-varpart-arm-hi` and `fty-anon-varpart-arm-lo`. Do not use such a
  record as a shared binary ABI without an explicit layout check.
- Delphi permits a runtime inline `const` to be passed to a `var` parameter
  with a warning. MoonCompiler rejects it consistently as read-only. The exact
  negative check is
  [`inline_const_var_parameter_rejected.pas`](../qualification/suite/tests/smoke/inline_const_var_parameter_rejected.pas).
- Repeated managed interface function results can be released at a different
  intermediate point. All objects are released by scope exit; product code
  must not depend on the temporary refcount between statements.
- `TRttiContext.GetTypes` is qualified for statically linked executables.
  Registration, interposition, and removal of RTTI from dynamically loaded or
  unloaded packages are not implemented.

### Linux `Extended`

On Linux x86-64, `Extended` is the native 10-byte x87 type; Delphi 12.2 Win64
uses an 8-byte `Double` representation. Use explicit `Double` in persisted
records, wire formats, shared memory, and cross-platform binary APIs. Changing
only the size would break the RTL and SysV ABI, so this is a target contract,
not a partial compatibility fix. Delphi-mode math intrinsics already use the
qualified Delphi result-width rules; explicit `CExtended` remains 80-bit.

### Clearing local secrets

Release may remove ordinary assignments to local variables whose values are
never read again, including zeroing before a routine returns. Explicit
`FillChar`, `FillByte`, `FillWord`, `FillDWord`, `FillQWord` and `Move` operations
retain their local-buffer writes at routine exit, including small operations
expanded by `MEMINLINE` and inline helpers loaded from PPU.

Use an explicit clearing operation on the intended buffer. It clears only
that storage when execution reaches the call; it does not clear other copies
of the secret or protect a path which exits before the clearing operation.

## External GNU linking of Win64 DLLs

The optional external GNU linker route (`-Xe`) has a known failure for Win64
libraries containing the RTL's unwind sections. The compiler emits a dummy
code-to-`.pdata` relocation to retain exception metadata during section garbage
collection. GNU `ld --shared` rejects that relocation with `0-bit reloc in dll`;
the legacy base-file/`dlltool` route can instead turn it into a base relocation
at a function entry, corrupting instructions when the DLL is rebased. This
route is not accepted for such DLLs even if linking succeeds.

Use the default internal Win64 linker, or select it explicitly with `-Xi`.
This limitation is specific to the external GNU DLL route; it does not extend
to the default internal route or to externally linked executables.

## Qualification environment exceptions

These failures measure the lab's network, not compiled code.

- `mormot2tests` of the MoonORMot line (MM gate
  `qualification/suite/scripts/mm/run_mormot_mm_gate.sh`, `runner.py mormot`),
  method `DNS and LDAP`: with Internet access the 2024 test resolves
  `synopse.info` and `blog.synopse.info` and reverse-resolves the answer, and
  expects the records of that time (`62.210.254.173`,
  `62-210-254-173.rev.poneytelecom.eu`). The public records have changed since,
  so exactly those three assertions (`dns1`, `dns2`, `rev`) fail. The MM gate
  accepts `TNetworkProtocols` only when this method is the one failing method
  of the class, with exactly 3 failures and no exception; `runner.py mormot`
  classifies it as environment together with the other methods named in
  [TESTS.md](../qualification/suite/docs/TESTS.md#mormot).
