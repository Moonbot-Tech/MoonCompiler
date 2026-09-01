# MoonCompiler Pulse result

Mode: `medium`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| dictionary | 30 | 0.883 | 15 | 6 | 9 | 1.083 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| mm | 16 | 0.972 | 8 | 1 | 7 |
| rtl | 30 | 0.883 | 15 | 6 | 9 |

## Extreme results

### 15 fastest

- `dictionary/string-u64-lookup-mixed-100`: `0.290x`
- `dictionary/string-u64-lookup-mixed-10000`: `0.486x`
- `dictionary/string-u64-churn-100`: `0.554x`
- `dictionary/u64-u64-build-grow-10000`: `0.555x`
- `dictionary/u64-u64-lookup-mixed-100`: `0.629x`
- `dictionary/string-u64-build-grow-10000`: `0.661x`
- `dictionary/u64-string-lookup-mixed-100`: `0.685x`
- `dictionary/u64-u64-lookup-halfload-10000`: `0.727x`
- `dictionary/u64-string-build-grow-10000`: `0.757x`
- `dictionary/u64-string-lookup-halfload-10000`: `0.761x`
- `dictionary/u64-u64-build-grow-100`: `0.764x`
- `dictionary/string-u64-churn-10000`: `0.880x`
- `dictionary/u64-u64-lookup-hit-10000`: `0.885x`
- `dictionary/string-u64-build-reserved-10000`: `0.893x`
- `dictionary/u64-u64-build-reserved-100`: `0.918x`

### 15 slowest

- `dictionary/u64-string-build-reserved-100`: `1.827x`
- `dictionary/u64-string-churn-10000`: `1.428x`
- `dictionary/u64-u64-build-reserved-10000`: `1.372x`
- `dictionary/u64-string-build-grow-100`: `1.347x`
- `dictionary/u64-u64-churn-10000`: `1.342x`
- `dictionary/string-u64-build-reserved-100`: `1.227x`
- `dictionary/u64-string-churn-100`: `1.116x`
- `dictionary/u64-string-build-reserved-10000`: `1.105x`
- `dictionary/u64-string-lookup-miss-10000`: `1.080x`
- `dictionary/string-u64-build-grow-100`: `1.021x`
- `dictionary/u64-string-lookup-mixed-10000`: `1.007x`
- `dictionary/u64-u64-lookup-miss-10000`: `0.974x`
- `dictionary/u64-u64-churn-100`: `0.973x`
- `dictionary/u64-u64-lookup-mixed-10000`: `0.963x`
- `dictionary/u64-string-lookup-hit-10000`: `0.960x`

## All cases

| Program | Case | Layer | Oracle | Metric | delphi stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| dictionary | string-u64-build-grow-100 | rtl+mm | MATCH | cycles | 436.598/437.652/442.992 | 445.915/447.538/455.925 | 1.021 | 446.727 | 0.998 |
| dictionary | string-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 666.349/667.142/669.712 | 440.268/443.376/451.877 | 0.661 | 419.615 | 1.049 |
| dictionary | string-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 266.467/265.607/267.922 | 326.927/322.458/330.493 | 1.227 | 320.939 | 1.019 |
| dictionary | string-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 367.232/366.486/372.020 | 328.101/328.868/335.711 | 0.893 | 194.883 | 1.684 |
| dictionary | string-u64-churn-100 | rtl+mm | MATCH | cycles | 182.713/183.970/186.717 | 101.225/100.671/101.261 | 0.554 | 96.787 | 1.046 |
| dictionary | string-u64-churn-10000 | rtl+mm | MATCH | cycles | 211.394/211.967/213.332 | 186.086/185.578/186.504 | 0.880 | 164.369 | 1.132 |
| dictionary | string-u64-lookup-mixed-100 | rtl | MATCH | cycles | 142.642/142.265/143.895 | 41.347/41.258/41.349 | 0.290 | 41.929 | 0.986 |
| dictionary | string-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 154.717/154.579/155.306 | 75.164/75.136/75.734 | 0.486 | 74.679 | 1.006 |
| dictionary | u64-string-build-grow-100 | rtl+mm | MATCH | cycles | 327.320/326.952/329.554 | 440.912/437.388/441.238 | 1.347 | 426.997 | 1.033 |
| dictionary | u64-string-build-grow-10000 | rtl+mm | MATCH | cycles | 552.016/555.242/564.205 | 417.924/416.130/420.375 | 0.757 | 404.776 | 1.032 |
| dictionary | u64-string-build-reserved-100 | rtl+mm | MATCH | cycles | 173.609/174.335/176.479 | 317.259/317.846/327.864 | 1.827 | 315.610 | 1.005 |
| dictionary | u64-string-build-reserved-10000 | rtl+mm | MATCH | cycles | 266.142/268.638/274.094 | 294.168/295.865/300.903 | 1.105 | 183.834 | 1.600 |
| dictionary | u64-string-churn-100 | rtl+mm | MATCH | cycles | 85.182/85.367/86.507 | 95.024/94.924/95.922 | 1.116 | 91.955 | 1.033 |
| dictionary | u64-string-churn-10000 | rtl+mm | MATCH | cycles | 109.934/110.143/110.941 | 157.016/157.000/157.852 | 1.428 | 151.487 | 1.036 |
| dictionary | u64-string-lookup-halfload-10000 | rtl | MATCH | cycles | 68.552/68.528/68.761 | 52.181/52.278/52.450 | 0.761 | 51.585 | 1.012 |
| dictionary | u64-string-lookup-hit-10000 | rtl | MATCH | cycles | 66.747/66.540/66.880 | 64.049/63.837/64.068 | 0.960 | 59.217 | 1.082 |
| dictionary | u64-string-lookup-miss-10000 | rtl | MATCH | cycles | 67.051/67.216/67.760 | 72.441/72.509/73.302 | 1.080 | 68.869 | 1.052 |
| dictionary | u64-string-lookup-mixed-100 | rtl | MATCH | cycles | 55.347/55.451/56.036 | 37.908/38.032/38.256 | 0.685 | 36.800 | 1.030 |
| dictionary | u64-string-lookup-mixed-10000 | rtl | MATCH | cycles | 68.343/68.427/68.571 | 68.818/68.517/69.027 | 1.007 | 66.585 | 1.034 |
| dictionary | u64-u64-build-grow-100 | rtl+mm | MATCH | cycles | 133.439/133.777/134.364 | 101.923/102.538/104.593 | 0.764 | 101.254 | 1.007 |
| dictionary | u64-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 259.711/257.195/266.950 | 144.048/147.497/152.285 | 0.555 | 149.425 | 0.964 |
| dictionary | u64-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 90.231/90.154/90.776 | 82.855/83.033/83.420 | 0.918 | 85.045 | 0.974 |
| dictionary | u64-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 144.466/147.160/152.646 | 198.265/199.763/211.489 | 1.372 | 81.881 | 2.421 |
| dictionary | u64-u64-churn-100 | rtl | MATCH | cycles | 63.109/63.159/63.613 | 61.389/61.471/61.665 | 0.973 | 62.439 | 0.983 |
| dictionary | u64-u64-churn-10000 | rtl | MATCH | cycles | 79.140/78.945/79.392 | 106.229/105.877/106.780 | 1.342 | 102.785 | 1.034 |
| dictionary | u64-u64-lookup-halfload-10000 | rtl | MATCH | cycles | 62.852/63.157/64.096 | 45.709/45.607/45.733 | 0.727 | 45.714 | 1.000 |
| dictionary | u64-u64-lookup-hit-10000 | rtl | MATCH | cycles | 55.998/56.159/57.114 | 49.533/49.803/51.053 | 0.885 | 48.493 | 1.021 |
| dictionary | u64-u64-lookup-miss-10000 | rtl | MATCH | cycles | 67.950/67.901/68.172 | 66.152/66.354/66.703 | 0.974 | 66.734 | 0.991 |
| dictionary | u64-u64-lookup-mixed-100 | rtl | MATCH | cycles | 51.266/51.351/51.895 | 32.235/32.249/32.392 | 0.629 | 33.461 | 0.963 |
| dictionary | u64-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 63.042/63.007/63.308 | 60.724/61.213/62.073 | 0.963 | 59.375 | 1.023 |
