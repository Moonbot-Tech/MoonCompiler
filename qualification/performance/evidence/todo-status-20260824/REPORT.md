# MoonCompiler Pulse result

Mode: `medium`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| json | 11 | 0.901 | 6 | 0 | 5 | 0.965 |
| managed | 17 | 0.902 | 9 | 6 | 2 | 0.990 |
| mormot-json | 18 | 0.957 | 6 | 9 | 3 | 0.828 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| codegen | 3 | 1.084 | 0 | 0 | 3 |
| compiler | 12 | 0.875 | 9 | 2 | 1 |
| integrated | 1 | 0.844 | 1 | 0 | 0 |
| mormot-json | 18 | 0.957 | 6 | 9 | 3 |
| rtl | 24 | 0.884 | 14 | 6 | 4 |

## Extreme results

### 15 fastest

- `json/generate-64`: `0.440x`
- `managed/unicode-concat`: `0.517x`
- `managed/managed-record-return`: `0.522x`
- `managed/closure-create-invoke`: `0.663x`
- `mormot-json/object-load-small`: `0.763x`
- `mormot-json/record-load-small`: `0.815x`
- `json/parse-medium-strtofloat`: `0.827x`
- `json/pipeline-parse-vwap-format`: `0.844x`
- `json/parse-large-custom-double`: `0.846x`
- `json/parse-medium-custom-double`: `0.846x`
- `json/parse-small-custom-double`: `0.853x`
- `managed/dynamic-array-assign`: `0.863x`
- `managed/ignored-string-result`: `0.876x`
- `mormot-json/docvariant-roundtrip-small`: `0.889x`
- `mormot-json/object-roundtrip-small`: `0.890x`

### 15 slowest

- `managed/managed-exception-cleanup`: `1.436x`
- `json/builder-growth-64k`: `1.262x`
- `managed/variant-numeric`: `1.238x`
- `json/byte-scan-large-4096`: `1.093x`
- `json/byte-scan-medium-256`: `1.091x`
- `mormot-json/docvariant-load-large`: `1.084x`
- `json/byte-scan-small-16`: `1.070x`
- `mormot-json/docvariant-roundtrip-large`: `1.054x`
- `json/builder-append-prepared-floats-64`: `1.054x`
- `mormot-json/docvariant-load-medium`: `1.053x`
- `mormot-json/object-roundtrip-large`: `1.045x`
- `managed/unicode-assign-mt`: `1.015x`
- `managed/rawbytestring-assign-mt`: `1.015x`
- `managed/unicode-assign`: `1.010x`
- `mormot-json/docvariant-roundtrip-medium`: `1.009x`

## All cases

| Program | Case | Layer | Oracle | Metric | delphi stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| json | builder-append-prepared-floats-64 | rtl | MATCH | cycles | 28.582/28.587/28.618 | 30.124/30.117/30.223 | 1.054 | 30.739 | 0.980 |
| json | builder-growth-64k | rtl | MATCH | cycles | 0.455/0.459/0.468 | 0.574/0.574/0.581 | 1.262 | 0.625 | 0.918 |
| json | byte-scan-large-4096 | codegen | MATCH | cycles | 4.255/4.340/4.518 | 4.650/4.785/4.933 | 1.093 | 4.996 | 0.931 |
| json | byte-scan-medium-256 | codegen | MATCH | cycles | 4.520/4.449/4.520 | 4.930/4.930/4.932 | 1.091 | 4.995 | 0.987 |
| json | byte-scan-small-16 | codegen | MATCH | cycles | 4.572/4.532/4.572 | 4.892/4.889/4.895 | 1.070 | 4.970 | 0.984 |
| json | generate-64 | rtl | MATCH | cycles | 11866.094/12218.103/14358.854 | 5222.773/5217.437/5248.750 | 0.440 | 5512.474 | 0.947 |
| json | parse-large-custom-double | compiler+rtl | MATCH | cycles | 2413.663/2420.857/2493.750 | 2042.222/2049.829/2109.622 | 0.846 | 2200.887 | 0.928 |
| json | parse-medium-custom-double | compiler+rtl | MATCH | cycles | 2487.318/2486.682/2487.812 | 2105.029/2105.692/2115.234 | 0.846 | 2144.365 | 0.982 |
| json | parse-medium-strtofloat | rtl | MATCH | cycles | 5563.066/5607.227/5802.422 | 4601.562/4626.797/4809.375 | 0.827 | 4797.500 | 0.959 |
| json | parse-small-custom-double | compiler+rtl | MATCH | cycles | 2416.562/2378.132/2422.091 | 2061.259/2028.386/2067.627 | 0.853 | 1998.178 | 1.032 |
| json | pipeline-parse-vwap-format | integrated | MATCH | cycles | 2503.151/2510.997/2524.427 | 2113.101/2114.148/2121.172 | 0.844 | 2171.084 | 0.973 |
| managed | closure-create-invoke | compiler+rtl | MATCH | cycles | 227.459/228.194/231.712 | 150.804/149.955/152.402 | 0.663 | 157.160 | 0.960 |
| managed | dynamic-array-assign | rtl | MATCH | cycles | 15.381/15.373/15.437 | 13.275/13.508/14.070 | 0.863 | 14.058 | 0.944 |
| managed | dynamic-array-deep-copy | rtl | MATCH | cycles | 58.278/58.845/62.805 | 52.907/52.929/53.184 | 0.908 | 51.238 | 1.033 |
| managed | ignored-interface-result | compiler+rtl | MATCH | cycles | 25.899/25.522/26.374 | 23.176/23.176/23.177 | 0.895 | 23.906 | 0.969 |
| managed | ignored-string-result | compiler+rtl | MATCH | cycles | 19.744/19.576/19.862 | 17.291/17.083/17.294 | 0.876 | 16.418 | 1.053 |
| managed | interface-copy-call | compiler+rtl | MATCH | cycles | 20.232/20.251/20.342 | 19.042/18.952/19.050 | 0.941 | 19.738 | 0.965 |
| managed | managed-early-exit | compiler+rtl | MATCH | cycles | 71.850/71.859/72.315 | 65.302/65.449/66.075 | 0.909 | 62.499 | 1.045 |
| managed | managed-exception-cleanup | compiler+rtl | MATCH | cycles | 549.930/549.717/553.649 | 789.445/791.569/798.864 | 1.436 | 797.201 | 0.990 |
| managed | managed-record-return | compiler+rtl | MATCH | cycles | 221.437/222.303/224.475 | 115.641/116.420/117.849 | 0.522 | 121.621 | 0.951 |
| managed | out-string-forwarding | compiler+rtl | MATCH | cycles | 24.909/24.934/24.982 | 24.467/24.580/24.774 | 0.982 | 22.855 | 1.071 |
| managed | rawbytestring-assign | rtl | MATCH | cycles | 12.595/13.046/13.838 | 12.684/13.040/13.455 | 1.007 | 13.462 | 0.942 |
| managed | rawbytestring-assign-mt | rtl | MATCH | cycles | 13.252/13.255/13.262 | 13.445/13.451/13.460 | 1.015 | 13.456 | 0.999 |
| managed | unicode-assign | rtl | MATCH | cycles | 12.617/12.629/12.682 | 12.745/12.753/12.809 | 1.010 | 12.741 | 1.000 |
| managed | unicode-assign-mt | rtl | MATCH | cycles | 13.249/13.206/13.252 | 13.450/13.449/13.456 | 1.015 | 13.444 | 1.000 |
| managed | unicode-concat | rtl | MATCH | cycles | 87.595/87.615/87.884 | 45.275/45.294/45.322 | 0.517 | 49.681 | 0.911 |
| managed | unicode-return-ppu | compiler+rtl | MATCH | cycles | 13.250/13.256/13.269 | 13.359/13.356/13.359 | 1.008 | 13.464 | 0.992 |
| managed | variant-numeric | rtl | MATCH | cycles | 136.778/136.094/136.791 | 169.360/169.370/169.394 | 1.238 | 166.945 | 1.014 |
| mormot-json | docvariant-load-large | mormot-json | MATCH | cycles | 2.717/2.712/2.727 | 2.944/2.940/2.962 | 1.084 | 5.699 | 0.517 |
| mormot-json | docvariant-load-medium | mormot-json | MATCH | cycles | 3.216/3.219/3.224 | 3.386/3.384/3.388 | 1.053 | 3.443 | 0.984 |
| mormot-json | docvariant-load-small | mormot-json | MATCH | cycles | 19.910/20.074/20.425 | 19.095/18.917/19.099 | 0.959 | 19.103 | 1.000 |
| mormot-json | docvariant-roundtrip-large | mormot-json | MATCH | cycles | 3.697/3.711/3.779 | 3.898/3.900/3.914 | 1.054 | 5.610 | 0.695 |
| mormot-json | docvariant-roundtrip-medium | mormot-json | MATCH | cycles | 4.882/4.888/4.898 | 4.925/4.933/4.944 | 1.009 | 5.014 | 0.982 |
| mormot-json | docvariant-roundtrip-small | mormot-json | MATCH | cycles | 41.965/42.061/42.238 | 37.312/37.369/37.715 | 0.889 | 37.818 | 0.987 |
| mormot-json | object-load-large | mormot-json | MATCH | cycles | 0.988/0.989/0.991 | 0.981/0.985/0.991 | 0.993 | 1.825 | 0.538 |
| mormot-json | object-load-medium | mormot-json | MATCH | cycles | 1.261/1.264/1.269 | 1.195/1.196/1.203 | 0.948 | 1.201 | 0.995 |
| mormot-json | object-load-small | mormot-json | MATCH | cycles | 10.814/10.813/10.970 | 8.256/8.350/8.494 | 0.763 | 8.569 | 0.963 |
| mormot-json | object-roundtrip-large | mormot-json | MATCH | cycles | 1.961/1.966/1.977 | 2.048/2.046/2.075 | 1.045 | 5.362 | 0.382 |
| mormot-json | object-roundtrip-medium | mormot-json | MATCH | cycles | 2.918/2.922/2.932 | 2.776/2.783/2.798 | 0.951 | 2.823 | 0.983 |
| mormot-json | object-roundtrip-small | mormot-json | MATCH | cycles | 31.595/31.613/32.154 | 28.116/28.119/28.235 | 0.890 | 29.439 | 0.955 |
| mormot-json | record-load-large | mormot-json | MATCH | cycles | 0.925/0.925/0.928 | 0.914/0.914/0.916 | 0.989 | 0.931 | 0.982 |
| mormot-json | record-load-medium | mormot-json | MATCH | cycles | 1.140/1.141/1.145 | 1.091/1.091/1.095 | 0.957 | 1.123 | 0.972 |
| mormot-json | record-load-small | mormot-json | MATCH | cycles | 8.820/8.827/8.932 | 7.190/7.197/7.241 | 0.815 | 7.236 | 0.994 |
| mormot-json | record-roundtrip-large | mormot-json | MATCH | cycles | 1.969/1.948/1.970 | 1.938/1.920/1.944 | 0.984 | 3.343 | 0.580 |
| mormot-json | record-roundtrip-medium | mormot-json | MATCH | cycles | 2.711/2.712/2.750 | 2.627/2.631/2.660 | 0.969 | 2.678 | 0.981 |
| mormot-json | record-roundtrip-small | mormot-json | MATCH | cycles | 27.892/28.036/28.455 | 26.295/26.261/26.377 | 0.943 | 26.788 | 0.982 |
