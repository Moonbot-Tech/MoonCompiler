# MoonCompiler Pulse result

Mode: `quick`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.
TSC is also used explicitly when scheduled thread cycles are unavailable for either system.

## Summary by Program

`< 0.95` means faster, `0.95..1.05` is within 5%, and `> 1.05` means slower. Unresolved rows and diagnostic reference/calibration rows are excluded. For placement families the ratio uses all placements; the timing columns show the plain binaries.

| Program | Cases | Geomean Moon/baseline | Faster | Within 5% | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| dictionary | 30 | 0.633 | 25 | 3 | 2 | 0.000 |

## Summary by Physical Layer

| Layer | Cases | Geomean Moon/baseline | Faster | Within 5% | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| mm | 16 | 0.752 | 12 | 2 | 2 |
| rtl | 30 | 0.633 | 25 | 3 | 2 |

## Extreme Results

### 15 Fastest

- `dictionary/string-u64-lookup-mixed-100`: `0.207x`
- `dictionary/u64-u64-lookup-mixed-100`: `0.267x`
- `dictionary/u64-string-lookup-mixed-100`: `0.303x`
- `dictionary/string-u64-lookup-mixed-10000`: `0.419x`
- `dictionary/u64-u64-lookup-halfload-10000`: `0.438x`
- `dictionary/string-u64-churn-100`: `0.461x`
- `dictionary/u64-u64-build-grow-10000`: `0.476x`
- `dictionary/u64-string-lookup-halfload-10000`: `0.502x`
- `dictionary/u64-u64-build-reserved-100`: `0.514x`
- `dictionary/u64-u64-churn-100`: `0.535x`
- `dictionary/u64-u64-build-grow-100`: `0.569x`
- `dictionary/u64-u64-lookup-hit-10000`: `0.587x`
- `dictionary/string-u64-build-grow-10000`: `0.639x`
- `dictionary/u64-string-build-grow-10000`: `0.650x`
- `dictionary/u64-string-lookup-hit-10000`: `0.667x`

### 15 Slowest

- `dictionary/u64-string-build-grow-100`: `1.212x`
- `dictionary/u64-string-churn-10000`: `1.111x`
- `dictionary/u64-u64-build-reserved-10000`: `1.031x`
- `dictionary/string-u64-build-grow-100`: `0.963x`
- `dictionary/u64-u64-churn-10000`: `0.957x`
- `dictionary/u64-string-build-reserved-100`: `0.902x`
- `dictionary/u64-string-build-reserved-10000`: `0.900x`
- `dictionary/string-u64-build-reserved-10000`: `0.864x`
- `dictionary/u64-string-lookup-miss-10000`: `0.832x`
- `dictionary/string-u64-churn-10000`: `0.807x`
- `dictionary/u64-u64-lookup-miss-10000`: `0.785x`
- `dictionary/u64-string-lookup-mixed-10000`: `0.745x`
- `dictionary/string-u64-build-reserved-100`: `0.725x`
- `dictionary/u64-string-churn-100`: `0.722x`
- `dictionary/u64-u64-lookup-mixed-10000`: `0.711x`

## All Cases

| Program | Case | Layer | Oracle | Metric | delphi median/mean/max | moon median/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| dictionary | string-u64-build-grow-100 | rtl+mm | MATCH | cycles | 450.412/450.412/459.800 | 433.852/433.852/441.471 | 0.963 | 0.000 | 0.000 |
| dictionary | string-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 706.534/706.534/720.328 | 451.440/451.440/464.322 | 0.639 | 0.000 | 0.000 |
| dictionary | string-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 278.084/278.084/285.146 | 201.477/201.477/203.454 | 0.725 | 0.000 | 0.000 |
| dictionary | string-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 386.631/386.631/390.716 | 334.134/334.134/343.862 | 0.864 | 0.000 | 0.000 |
| dictionary | string-u64-churn-100 | rtl+mm | MATCH | cycles | 187.479/187.479/193.021 | 86.407/86.407/88.328 | 0.461 | 0.000 | 0.000 |
| dictionary | string-u64-churn-10000 | rtl+mm | MATCH | cycles | 217.892/217.892/224.352 | 175.826/175.826/180.120 | 0.807 | 0.000 | 0.000 |
| dictionary | string-u64-lookup-mixed-100 | rtl | MATCH | cycles | 146.286/146.286/151.620 | 30.228/30.228/30.848 | 0.207 | 0.000 | 0.000 |
| dictionary | string-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 161.206/161.206/166.231 | 67.517/67.517/69.654 | 0.419 | 0.000 | 0.000 |
| dictionary | u64-string-build-grow-100 | rtl+mm | MATCH | cycles | 340.014/340.014/345.455 | 412.050/412.050/419.900 | 1.212 | 0.000 | 0.000 |
| dictionary | u64-string-build-grow-10000 | rtl+mm | MATCH | cycles | 592.192/592.192/595.232 | 384.978/384.978/388.474 | 0.650 | 0.000 | 0.000 |
| dictionary | u64-string-build-reserved-100 | rtl+mm | MATCH | cycles | 179.618/179.618/182.493 | 161.969/161.969/162.026 | 0.902 | 0.000 | 0.000 |
| dictionary | u64-string-build-reserved-10000 | rtl+mm | MATCH | cycles | 282.796/282.796/285.722 | 254.600/254.600/254.866 | 0.900 | 0.000 | 0.000 |
| dictionary | u64-string-churn-100 | rtl+mm | MATCH | cycles | 88.472/88.472/89.933 | 63.881/63.881/63.935 | 0.722 | 0.000 | 0.000 |
| dictionary | u64-string-churn-10000 | rtl+mm | MATCH | cycles | 115.406/115.406/117.572 | 128.174/128.174/128.250 | 1.111 | 0.000 | 0.000 |
| dictionary | u64-string-lookup-halfload-10000 | rtl | MATCH | cycles | 71.117/71.117/73.112 | 35.672/35.672/35.777 | 0.502 | 0.000 | 0.000 |
| dictionary | u64-string-lookup-hit-10000 | rtl | MATCH | cycles | 68.970/68.970/70.528 | 46.018/46.018/47.120 | 0.667 | 0.000 | 0.000 |
| dictionary | u64-string-lookup-miss-10000 | rtl | MATCH | cycles | 70.053/70.053/71.820 | 58.235/58.235/58.634 | 0.832 | 0.000 | 0.000 |
| dictionary | u64-string-lookup-mixed-100 | rtl | MATCH | cycles | 56.843/56.843/58.111 | 17.224/17.224/17.228 | 0.303 | 0.000 | 0.000 |
| dictionary | u64-string-lookup-mixed-10000 | rtl | MATCH | cycles | 71.022/71.022/72.599 | 52.877/52.877/53.200 | 0.745 | 0.000 | 0.000 |
| dictionary | u64-u64-build-grow-100 | rtl+mm | MATCH | cycles | 132.511/132.511/135.036 | 75.360/75.360/75.549 | 0.569 | 0.000 | 0.000 |
| dictionary | u64-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 262.371/262.371/268.204 | 124.754/124.754/126.616 | 0.476 | 0.000 | 0.000 |
| dictionary | u64-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 92.770/92.770/94.430 | 47.677/47.677/48.534 | 0.514 | 0.000 | 0.000 |
| dictionary | u64-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 155.192/155.192/156.218 | 159.999/159.999/164.008 | 1.031 | 0.000 | 0.000 |
| dictionary | u64-u64-churn-100 | rtl | MATCH | cycles | 64.967/64.967/66.300 | 34.742/34.742/35.132 | 0.535 | 0.000 | 0.000 |
| dictionary | u64-u64-churn-10000 | rtl | MATCH | cycles | 82.061/82.061/83.714 | 78.546/78.546/80.218 | 0.957 | 0.000 | 0.000 |
| dictionary | u64-u64-lookup-halfload-10000 | rtl | MATCH | cycles | 63.935/63.935/65.398 | 27.987/27.987/28.671 | 0.438 | 0.000 | 0.000 |
| dictionary | u64-u64-lookup-hit-10000 | rtl | MATCH | cycles | 58.425/58.425/59.622 | 34.314/34.314/34.770 | 0.587 | 0.000 | 0.000 |
| dictionary | u64-u64-lookup-miss-10000 | rtl | MATCH | cycles | 69.863/69.863/71.516 | 54.834/54.834/56.278 | 0.785 | 0.000 | 0.000 |
| dictionary | u64-u64-lookup-mixed-100 | rtl | MATCH | cycles | 52.580/52.580/54.014 | 14.037/14.037/14.275 | 0.267 | 0.000 | 0.000 |
| dictionary | u64-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 64.001/64.001/65.569 | 45.486/45.486/46.569 | 0.711 | 0.000 | 0.000 |
