# MoonCompiler Pulse result

Mode: `medium`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| dictionary | 24 | 0.948 | 11 | 3 | 10 | 1.105 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| mm | 16 | 1.034 | 7 | 2 | 7 |
| rtl | 24 | 0.948 | 11 | 3 | 10 |

## Extreme results

### 15 fastest

- `dictionary/string-u64-lookup-mixed-100`: `0.311x`
- `dictionary/string-u64-lookup-mixed-10000`: `0.505x`
- `dictionary/u64-u64-build-grow-10000`: `0.562x`
- `dictionary/string-u64-build-grow-10000`: `0.684x`
- `dictionary/u64-u64-lookup-mixed-100`: `0.708x`
- `dictionary/string-u64-churn-100`: `0.735x`
- `dictionary/u64-string-build-grow-10000`: `0.737x`
- `dictionary/u64-u64-build-grow-100`: `0.765x`
- `dictionary/u64-string-lookup-mixed-100`: `0.863x`
- `dictionary/string-u64-build-reserved-10000`: `0.892x`
- `dictionary/u64-u64-build-reserved-100`: `0.909x`
- `dictionary/u64-u64-churn-100`: `1.011x`
- `dictionary/string-u64-build-grow-100`: `1.021x`
- `dictionary/string-u64-churn-10000`: `1.029x`
- `dictionary/u64-u64-lookup-mixed-10000`: `1.055x`

### 15 slowest

- `dictionary/u64-string-build-reserved-100`: `1.834x`
- `dictionary/u64-string-churn-10000`: `1.744x`
- `dictionary/u64-string-churn-100`: `1.563x`
- `dictionary/u64-u64-churn-10000`: `1.388x`
- `dictionary/u64-u64-build-reserved-10000`: `1.378x`
- `dictionary/u64-string-build-grow-100`: `1.319x`
- `dictionary/string-u64-build-reserved-100`: `1.221x`
- `dictionary/u64-string-lookup-mixed-10000`: `1.145x`
- `dictionary/u64-string-build-reserved-10000`: `1.137x`
- `dictionary/u64-u64-lookup-mixed-10000`: `1.055x`
- `dictionary/string-u64-churn-10000`: `1.029x`
- `dictionary/string-u64-build-grow-100`: `1.021x`
- `dictionary/u64-u64-churn-100`: `1.011x`
- `dictionary/u64-u64-build-reserved-100`: `0.909x`
- `dictionary/string-u64-build-reserved-10000`: `0.892x`

## All cases

| Program | Case | Layer | Oracle | Metric | delphi stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| dictionary | string-u64-build-grow-100 | rtl+mm | MATCH | cycles | 434.311/435.005/437.731 | 443.470/446.963/453.914 | 1.021 | 433.090 | 1.024 |
| dictionary | string-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 657.818/667.394/677.920 | 449.986/448.172/452.789 | 0.684 | 418.722 | 1.075 |
| dictionary | string-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 264.489/263.986/265.106 | 322.864/321.064/332.636 | 1.221 | 314.343 | 1.027 |
| dictionary | string-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 374.177/371.689/384.446 | 333.583/339.853/370.139 | 0.892 | 194.579 | 1.714 |
| dictionary | string-u64-churn-100 | rtl+mm | MATCH | cycles | 178.646/180.313/183.943 | 131.371/132.227/134.611 | 0.735 | 131.720 | 0.997 |
| dictionary | string-u64-churn-10000 | rtl+mm | MATCH | cycles | 209.779/209.611/212.325 | 215.783/216.215/219.260 | 1.029 | 200.203 | 1.078 |
| dictionary | string-u64-lookup-mixed-100 | rtl | MATCH | cycles | 141.942/141.676/142.429 | 44.119/43.956/44.227 | 0.311 | 42.034 | 1.050 |
| dictionary | string-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 156.531/157.663/161.766 | 79.011/78.980/79.534 | 0.505 | 73.777 | 1.071 |
| dictionary | u64-string-build-grow-100 | rtl+mm | MATCH | cycles | 327.461/324.213/327.681 | 431.802/432.092/437.146 | 1.319 | 427.572 | 1.010 |
| dictionary | u64-string-build-grow-10000 | rtl+mm | MATCH | cycles | 553.043/563.393/583.794 | 407.673/410.541/416.613 | 0.737 | 411.853 | 0.990 |
| dictionary | u64-string-build-reserved-100 | rtl+mm | MATCH | cycles | 172.185/172.256/174.167 | 315.740/311.300/315.816 | 1.834 | 308.906 | 1.022 |
| dictionary | u64-string-build-reserved-10000 | rtl+mm | MATCH | cycles | 264.594/270.058/276.678 | 300.969/303.712/310.460 | 1.137 | 185.687 | 1.621 |
| dictionary | u64-string-churn-100 | rtl+mm | MATCH | cycles | 84.583/84.650/85.788 | 132.207/132.277/132.671 | 1.563 | 131.554 | 1.005 |
| dictionary | u64-string-churn-10000 | rtl+mm | MATCH | cycles | 109.863/109.937/110.295 | 191.596/192.085/193.420 | 1.744 | 190.532 | 1.006 |
| dictionary | u64-string-lookup-mixed-100 | rtl | MATCH | cycles | 54.749/54.764/55.315 | 47.248/47.070/47.249 | 0.863 | 47.805 | 0.988 |
| dictionary | u64-string-lookup-mixed-10000 | rtl | MATCH | cycles | 68.011/68.120/68.495 | 77.881/77.653/77.995 | 1.145 | 75.686 | 1.029 |
| dictionary | u64-u64-build-grow-100 | rtl+mm | MATCH | cycles | 132.934/145.447/166.773 | 101.718/110.855/126.663 | 0.765 | 100.941 | 1.008 |
| dictionary | u64-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 267.216/265.411/290.320 | 150.081/156.025/166.478 | 0.562 | 146.214 | 1.026 |
| dictionary | u64-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 90.713/90.542/91.185 | 82.422/82.556/82.990 | 0.909 | 83.628 | 0.986 |
| dictionary | u64-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 151.325/150.958/164.882 | 208.601/207.236/212.819 | 1.378 | 82.365 | 2.533 |
| dictionary | u64-u64-churn-100 | rtl | MATCH | cycles | 63.413/63.841/64.547 | 64.130/64.041/64.450 | 1.011 | 63.199 | 1.015 |
| dictionary | u64-u64-churn-10000 | rtl | MATCH | cycles | 79.135/79.208/79.686 | 109.820/109.646/110.200 | 1.388 | 105.868 | 1.037 |
| dictionary | u64-u64-lookup-mixed-100 | rtl | MATCH | cycles | 50.144/50.174/50.450 | 35.481/35.450/35.582 | 0.708 | 35.836 | 0.990 |
| dictionary | u64-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 61.493/61.291/61.522 | 64.857/65.151/65.930 | 1.055 | 62.700 | 1.034 |
