# Optimizer core: Win64 baseline

Date: 2026-08-29.

## Recorded state

- source `main`: `4f5c6927b7ea48cce96e53799a4fcaa4aca4cde3`;
- clean separate clone of source HEAD;
- OS: Windows 11 x86-64;
- CPU: AMD64 Family 25 Model 33 Stepping 0, 16 logical CPU;
- Moon backend SHA-256: `443295973C48C17DBD75D4107A36888E3C826D9648143E192C8CEA020EA5C081`;
- Moon `fpc.cfg` SHA-256: `BC70F96608D3FC5908462527CF465ECE14A4DFB25710D1B31CEF5CF25B8A06DB`;
- bundled MM SHA-256: `FCC8FD1AA6214C1FDE5AD60942EF0FDC656649B7C01D744FA9385807A5386703`;
- Delphi 12.2 `dcc64.exe` SHA-256 from manifest: `68CF81C0B1044E585EB584D96947A01E669605D8AC1ED048A2DE44FD867FDB88`.

The compiler was built normally:

```powershell
.\build.ps1 compiler
```

Pulse ran interleaved for Delphi and Moon:

```powershell
uv run python qualification\performance\tools\pulse.py run `
  --mode medium --programs heartbeat,managed,kernels --systems delphi,moon `
  --tag optimizer-core-baseline-medium-20260829

uv run python qualification\performance\tools\pulse.py run `
  --mode quick --programs local-pressure --systems delphi,moon `
  --tag optimizer-core-baseline-local-pressure-20260829
```

Both manifests record a clean tree and exact HEAD. The semantic oracle is
`MATCH` in all 56 main and 9 local-pressure cases.

## Result before the new optimizer architecture

The ratio below is `Moon / Delphi`; below one means a Moon win.

| Program / case | Delphi cycles/op | Moon cycles/op | Moon/Delphi | Decision |
|---|---:|---:|---:|---|
| heartbeat, geomean 20 cases | — | — | `0.844x` | overall application portfolio is already faster |
| heartbeat/spectrum-fft-32x1024 | 11.637 | 12.579 | `1.081x` | main consumer of address/RA diagnostics |
| heartbeat/correlation-32x256 | 3.018 | 2.938 | `0.973x` | parity; do not accept a fix at the cost of regression |
| managed, geomean 17 cases | — | — | `0.901x` | overall managed layer is faster |
| managed/managed-exception-cleanup | 617.294 | 843.758 | `1.367x` | separate runtime/cleanup/SEH decomposition |
| managed/variant-numeric | 143.601 | 181.298 | `1.263x` | not a LICM/GVN/RA consumer |
| kernels, geomean 10 cases | — | — | `0.887x` | broad-algorithm control |
| local-pressure, geomean 9 cases | — | — | `0.231x` | no overall loss from local pressure |
| local-pressure/used-mixed-300 | 4009.445 | 3629.661 | `0.905x` | heavy-used-locals control |
| local-pressure/used-strings-100 | 1513.601 | 1495.363 | `0.988x` | strict parity |

Complete local reports for the baseline run:

- `qualification/performance/results/pulse/optimizer-core-baseline-medium-20260829/REPORT.md`;
- `qualification/performance/results/pulse/optimizer-core-baseline-local-pressure-20260829/REPORT.md`.

These directories are not committed: the manifest and all raw process logs
remain in the frozen baseline clone until optimizer work is complete.

## Comparison contract

Each accepted stage is compared with this exact toolchain through an external
Pulse system (`moon-baseline` against `moon-candidate`) and a separate ASM diff.
Changing the semantic digest is forbidden. A win in one FFT does not compensate
for a regression in correlation, kernels, managed, or local-pressure.
