# Pulse evidence: todo-status-20260824

Date: 2026-08-24. Win64, O3, `medium` mode, interleaved process order.
Compiler source: `28b6ba6b992c0cf2c4be0a97766add1fd56ad82c`; benchmark source:
`faea0a6a360ac3666538638f41a524ba71fc7540`.

Systems: Delphi 12.2 + FastMM4, MoonCompiler + bundled MM, and MoonCompiler +
default FPC MM. Before the run, the MoonCompiler toolchain was fully rebuilt
from the stated compiler source with the standard `build.ps1 compiler`.

Target results:

| Case/group | Moon / Delphi | MM effect | Conclusion |
|---|---:|---:|---|
| `managed/managed-exception-cleanup` | `1.436` | `0.990` | the exact exception combination in managed cleanup remains open |
| `json/builder-growth-64k` | `1.262` | `0.918` | the old fix helped, but growth is still slower than Delphi |
| `json/builder-append-prepared-floats-64` | `1.054` | `0.980` | parity boundary |
| `mormot-json`, 18 cases | `0.957` geomean | `0.828` geomean | 18/18 semantic oracle MATCH; 6 faster, 9 at parity, 3 slower |

`mormot-json` measures the actual API of the bundled product mORMot: record,
`TDocVariant`, and object load and round-trip with 32/4096/65536-byte payloads.
The old simple byte-traversal cases in the current source are named
`byte-scan-*`. Three `TDocVariant` tails and a separate `byte-scan` codegen gap
were moved to PULSE-TODO-013/014; completing benchmark coverage is not
presented as optimizing them.

Full aggregate report: [REPORT.md](REPORT.md). Machine-readable values:
[summary.json](summary.json).

The runner completed the full set without process-drift failures; executable
hashes and semantic oracles match.

Hashes:

- compiler: `3B20D2FCF5CB132CEC3006A98B7B12C8EDDC8ED82677A351DB18140D9593F091`;
- compiler config: `F0F1D645212318B7B16655576EFF9E832F478781244637528EBB1C94D7F43449`;
- bundled MM source: `B0AF17E29E98CCA60A8C5CA8A7670552B78B43CAFA6171289A4A6C6107FF40AF`;
- `REPORT.md`: `3E79AE82975F79AA8C43E221E840507141A759C17E751558D08088FCE2F7B005`;
- `summary.json`: `7D92189CFF03372E489A5592CF949E6A6E63E66B3EC3D53054988064C6D6E532`.
