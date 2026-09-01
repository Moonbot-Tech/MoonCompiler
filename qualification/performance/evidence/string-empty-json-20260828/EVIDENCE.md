# Empty-string domain / mORMot JSON evidence — 2026-08-28

## Cause

`TDocVariantData.InitJson(RawUtf8)` begins with `Json = ''`. Before the fix,
the DelphiUnicode frontend promoted the operation to UnicodeString and
converted all RawUtf8 before checking the length. The phase probe proved that
the in-place parser, lookup, `ToJson`, and `TSynTempBuffer` are faster than
Delphi on their own.

## Fix and boundaries

Only `=`/`<>` with an empty string literal retain the domain of the second
operand. Ordering comparisons do not change. Product mORMot, TSynTempBuffer,
and the memory manager were not changed.

## Reproduction

```powershell
.\build.ps1 compiler
uv run python RTL-test/run.py `
  --modes debug o2 o3 --only string_empty_compare
uv run python `
  qualification/performance/tools/pulse.py run `
  --mode medium --programs mormot-json --systems moon,delphi `
  --tag empty-string-json-medium-20260828
```

The Delphi oracle was built with DCC64 36.0 / Delphi 12.2 with namespace
prefixes
`System;Winapi;System.Win;Data;Xml`.

## Hash evidence

- `compiler/nadd.pas`: `36BA66E649B58060CE94F6C34C9FB658704C1A4FA5313C45774009B83E47ABB7`
- pre-fix semantic source: `68F37ECA021FE0AF2F9EC0906E20BD9ECD4657E3BD643E4013F97D0F349B9F0A`
- final semantic source (empty/NUL boundaries added): `A24786CF100B843BEC0B46B05A4C699C1C63B5C055447C1DAB3AB64D80427ABF`
- RTL runner: `37B9A2DDF7D339717028BF5D2CC214B117FAE99889105DDF9736FE2CCCF86C48`
- candidate `ppcx64.exe`: `2170C5864988DBE0F2D594CC56FACAF48ECB105089BECC8CFAB63203CC701BFA`
- pre-fix ASM: `A697DB85FCFDF6D2ED0C793ED18512C7CC72227D592C0A008CD9B9F6E1F56002`
- post-fix ASM: `5FEE10437552334282E06478702234443367B5A1144331945222EEEBACFB6ECE`
- accepted quick summary: `1B4500857E8B1FE797CA9606191E9142B2B7A35EFC5C430C27A133A85E5F84EF`
- medium summary: `2D18B312A3CE8F778A13B24CEE76C6CD189AC64F600FBB413EBD7C0ACEE2F24A`

## Semantics and ASM

- Delphi 12.2: `STRING_EMPTY_COMPARE_OK`.
- Moon Debug/O2/O3: 3/3 `STRING_EMPTY_COMPARE_OK`.
- Before the fix on the shared non-empty O3 matrix: 4 `fpc_ansistr_to_unicodestr`,
  4 `fpc_shortstr_to_unicodestr`, 4 `fpc_widestr_to_unicodestr`.
- After the fix on the expanded matrix: 0/0/0. Assign/decref calls remain.
- This zero-call contract is included in the permanent `RTL-test/run.py`.

## Phase A/B, Win64 quick

Three independent processes per state, median ns/op:

| Phase | Delphi | Moon before | Moon after | After/Delphi |
|---|---:|---:|---:|---:|
| `InitJson(RawUtf8)`, 64 KiB | 48 325 | 50 600 | 31 850 | `0.659x` |
| `InitJsonInPlace`, 64 KiB | 48 175 | — | 31 758 | `0.659x` |

The remaining post-fix phases: temp-copy is near parity, while lookup and
`ToJson` are faster than Delphi. Wrapper parity with the in-place parser after
the fix confirms that the eliminated work was precisely the redundant
pre-parser pass.

## Full mORMot JSON

The first quick attempt executed the cases correctly, but the runner rejected
the report because of `1.253x` process drift in short `record-roundtrip-large`.
It is not used as a result. The repeated quick passed the filter: 18/18 MATCH,
geomean `0.907`, 12 faster, 5 at parity, 1 slower.

Final interleaved Win64 medium: 18/18 MATCH, geomean `0.866`, 13 faster,
5 at parity, 0 slower. Main closed tails:

| Case | Before | After |
|---|---:|---:|
| `docvariant-load-large` | `1.084x` | `0.680x` |
| `docvariant-load-medium` | `1.053x` | `0.714x` |
| `docvariant-roundtrip-large` | `1.054x` | `0.762x` |

The slowest remaining case is `object-roundtrip-large 1.031x`, which is parity
under the accepted +/-5% threshold.
