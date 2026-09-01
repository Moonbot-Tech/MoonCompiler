# Pulse baseline before the 2026-08-28 focused optimization pass

This snapshot was recorded before changing automatic runtime-unit injection,
the Linux stack contract, byte scanning, `TStringBuilder`, or `TDocVariant`
JSON paths.

## Exact source state

- branch: `main`
- HEAD: `6f9b186debf1e4e8213cd0e753c09b68cf3e222e`
- the only untracked file was the unrelated `AUDIT_Pulse1.md`
- bundled MM SHA-256: `fcc8fd1aa6214c1fde5ad60942ef0fdc656649b7c01d744fa9385807a5386703`

## Accepted comparison baseline

The last stable `medium` run remains the acceptance baseline because it has
enough samples and passed the stability policy. Its full report is in
`qualification/performance/evidence/todo-status-20260824/REPORT.md`.

| Case | Delphi | Moon | Moon/Delphi |
| --- | ---: | ---: | ---: |
| `json/builder-growth-64k` | 0.455 | 0.574 | 1.262x |
| `json/builder-append-prepared-floats-64` | 28.582 | 30.124 | 1.054x |
| `json/byte-scan-small-16` | 4.572 | 4.892 | 1.070x |
| `json/byte-scan-medium-256` | 4.520 | 4.930 | 1.091x |
| `json/byte-scan-large-4096` | 4.255 | 4.650 | 1.093x |
| `mormot-json/docvariant-load-small` | 19.910 | 19.095 | 0.959x |
| `mormot-json/docvariant-load-medium` | 3.216 | 3.386 | 1.053x |
| `mormot-json/docvariant-load-large` | 2.717 | 2.944 | 1.084x |
| `mormot-json/docvariant-roundtrip-small` | 41.965 | 37.312 | 0.889x |
| `mormot-json/docvariant-roundtrip-medium` | 4.882 | 4.925 | 1.009x |
| `mormot-json/docvariant-roundtrip-large` | 3.697 | 3.898 | 1.054x |

Values are scheduled thread cycles per operation. Ratios below 1 mean Moon is
faster.

## Exact-HEAD quick scouting run

Command:

```powershell
uv run python qualification\performance\tools\pulse.py run `
  --mode quick --programs json,mormot-json `
  --systems delphi,moon,moon-default `
  --tag pre-autoprefix-byte-builder-docvariant-20260828
```

Raw artifacts are under
`qualification/performance/results/pulse/pre-autoprefix-byte-builder-docvariant-20260828/`.
The run built and executed all requested programs, but report validation
correctly rejected it because the unrelated
`delphi/mormot-json/record-roundtrip-medium` process pair drifted by 1.447x.
Therefore these values are diagnostic only and must not replace the stable
medium baseline.

| Case | Delphi | Moon | Moon/Delphi |
| --- | ---: | ---: | ---: |
| `json/builder-growth-64k` | 0.454 | 0.646 | 1.422x |
| `json/builder-append-prepared-floats-64` | 28.139 | 33.620 | 1.195x |
| `json/byte-scan-small-16` | 4.216 | 4.784 | 1.135x |
| `json/byte-scan-medium-256` | 4.171 | 4.794 | 1.149x |
| `json/byte-scan-large-4096` | 4.155 | 4.790 | 1.153x |
| `mormot-json/docvariant-load-small` | 19.218 | 17.844 | 0.929x |
| `mormot-json/docvariant-load-medium` | 3.051 | 3.250 | 1.065x |
| `mormot-json/docvariant-load-large` | 2.570 | 2.789 | 1.085x |
| `mormot-json/docvariant-roundtrip-small` | 40.329 | 35.993 | 0.893x |
| `mormot-json/docvariant-roundtrip-medium` | 4.656 | 4.725 | 1.015x |
| `mormot-json/docvariant-roundtrip-large` | 3.521 | 3.703 | 1.052x |

## Acceptance rule for this pass

Use short focused A/B probes while developing. After each repair, rerun only
the affected Pulse cases. Compare against both this exact-HEAD quick scouting
snapshot and the stable medium baseline, but accept a performance claim only
from stable samples with matching semantic digests.
