# MoonCompiler Pulse result

Mode: `medium`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| abi | 24 | 0.735 | 11 | 10 | 3 | 0.955 |
| algorithms | 9 | 0.864 | 5 | 3 | 1 | 0.990 |
| calibration | 4 | 1.029 | 0 | 3 | 1 | 1.012 |
| codegen | 60 | 0.906 | 20 | 27 | 13 | 1.022 |
| dispatch | 15 | 0.892 | 7 | 6 | 2 | 0.981 |
| json | 9 | 0.968 | 6 | 0 | 3 | 1.099 |
| kernels | 10 | 0.856 | 7 | 2 | 1 | 0.987 |
| layout | 20 | 0.675 | 13 | 2 | 5 | 1.073 |
| local-pressure | 9 | 0.218 | 7 | 2 | 0 | 0.933 |
| loops | 20 | 0.938 | 7 | 11 | 2 | 0.958 |
| managed | 17 | 0.910 | 8 | 7 | 2 | 0.942 |
| mm | 15 | 0.972 | 5 | 5 | 5 | 0.609 |
| numeric | 21 | 0.770 | 9 | 11 | 1 | 1.037 |
| rtl | 77 | 0.719 | 45 | 18 | 14 | 0.993 |
| rtl-collections | 48 | 0.793 | 33 | 6 | 9 | 0.980 |
| threads | 17 | 0.125 | 9 | 7 | 1 | 1.120 |
| workloads | 15 | 0.975 | 6 | 4 | 5 | 0.973 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| abi | 24 | 0.735 | 11 | 10 | 3 |
| application | 10 | 0.856 | 7 | 2 | 1 |
| calibration | 4 | 1.029 | 0 | 3 | 1 |
| codegen | 145 | 0.805 | 61 | 59 | 25 |
| compiler | 23 | 0.973 | 10 | 9 | 4 |
| integrated | 1 | 0.939 | 1 | 0 | 0 |
| managed | 11 | 0.257 | 8 | 2 | 1 |
| math | 2 | 1.073 | 1 | 0 | 1 |
| memory | 40 | 0.876 | 17 | 17 | 6 |
| mm | 107 | 0.579 | 59 | 24 | 24 |
| os | 7 | 0.992 | 1 | 5 | 1 |
| rtl | 180 | 0.760 | 109 | 38 | 33 |
| text | 1 | 0.925 | 1 | 0 | 0 |

## Extreme results

### 15 fastest

- `threads/parallel-alloc-free-96-8`: `0.001x`
- `threads/parallel-alloc-free-96-4`: `0.001x`
- `threads/parallel-alloc-free-4`: `0.001x`
- `threads/parallel-alloc-free-2`: `0.002x`
- `threads/parallel-alloc-free-8`: `0.004x`
- `local-pressure/unused-mixed-300`: `0.007x`
- `local-pressure/unused-buffers-100`: `0.010x`
- `local-pressure/unused-strings-100`: `0.032x`
- `rtl/dictionary-capacity-1024`: `0.043x`
- `rtl/helper-endswith-nocase`: `0.056x`
- `rtl/helper-startswith-nocase`: `0.064x`
- `rtl/format-string`: `0.093x`
- `threads/cross-thread-free-4`: `0.152x`
- `rtl/datetime-ms-arith`: `0.184x`
- `codegen/currency-mul-div`: `0.205x`

### 15 slowest

- `codegen/for-downto`: `1.933x`
- `rtl/inttohex-int64`: `1.804x`
- `rtl-collections/list-string-insertrange-2048`: `1.766x`
- `layout/move-1024`: `1.707x`
- `abi/dynamic-array-value`: `1.612x`
- `codegen/try-finally-normal`: `1.584x`
- `dispatch/raise-catch`: `1.552x`
- `managed/managed-exception-cleanup`: `1.497x`
- `codegen/branch-predictable`: `1.478x`
- `rtl/dynamic-array-copy-512`: `1.465x`
- `json/scan-small-16`: `1.418x`
- `json/scan-medium-256`: `1.404x`
- `layout/move-256`: `1.400x`
- `json/scan-large-4096`: `1.396x`
- `codegen/case-dense`: `1.389x`

## All cases

| Program | Case | Layer | Oracle | Metric | delphi stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| abi | dynamic-array-const | abi+managed | MATCH | cycles | 4.882/4.889/4.908 | 4.869/4.859/4.873 | 0.997 | 5.645 | 0.863 |
| abi | dynamic-array-value | abi+managed | MATCH | cycles | 15.112/15.220/15.403 | 24.360/24.340/24.360 | 1.612 | 24.344 | 1.001 |
| abi | eight-args | abi | MATCH | cycles | 11.261/11.268/11.307 | 12.919/12.871/12.920 | 1.147 | 10.814 | 1.195 |
| abi | four-args | abi | MATCH | cycles | 6.407/6.422/6.476 | 6.425/6.439/6.492 | 1.003 | 6.374 | 1.008 |
| abi | function-pointer | abi | MATCH | cycles | 4.843/4.847/4.869 | 4.843/4.843/4.844 | 1.000 | 4.843 | 1.000 |
| abi | interface-method | abi+managed | MATCH | cycles | 6.480/6.480/6.480 | 5.666/5.667/5.667 | 0.875 | 5.666 | 1.000 |
| abi | method-pointer | abi | MATCH | cycles | 5.607/5.607/5.637 | 5.607/5.594/5.608 | 1.000 | 5.607 | 1.000 |
| abi | mixed-args | abi | MATCH | cycles | 13.072/13.089/13.143 | 8.428/8.419/8.429 | 0.645 | 8.479 | 0.994 |
| abi | no-args | abi | MATCH | cycles | 0.838/0.837/0.839 | 0.834/0.835/0.839 | 0.995 | 1.640 | 0.509 |
| abi | one-arg | abi | MATCH | cycles | 4.806/4.810/4.857 | 4.781/4.815/4.915 | 0.995 | 4.781 | 1.000 |
| abi | open-array-const | abi | MATCH | cycles | 4.120/4.111/4.120 | 4.882/4.875/4.882 | 1.185 | 4.869 | 1.003 |
| abi | record16-value | abi | MATCH | cycles | 14.277/14.261/14.280 | 5.632/5.280/5.688 | 0.394 | 5.607 | 1.004 |
| abi | record24-value | abi | MATCH | cycles | 15.923/15.957/16.006 | 3.565/3.560/3.565 | 0.224 | 3.572 | 0.998 |
| abi | record32-const | abi | MATCH | cycles | 4.896/4.892/4.896 | 4.895/4.891/4.896 | 1.000 | 4.908 | 0.997 |
| abi | record32-value | abi | MATCH | cycles | 20.818/20.861/20.933 | 7.599/7.596/7.697 | 0.365 | 8.822 | 0.861 |
| abi | record32-var | abi | MATCH | cycles | 4.895/4.895/4.897 | 5.094/5.095/5.102 | 1.041 | 5.083 | 1.002 |
| abi | record8-value | abi | MATCH | cycles | 6.971/6.973/6.976 | 2.772/2.766/2.772 | 0.398 | 2.756 | 1.006 |
| abi | return-record16 | abi | MATCH | cycles | 12.530/12.557/12.604 | 12.449/12.451/12.482 | 0.993 | 12.822 | 0.971 |
| abi | return-record24 | abi | MATCH | cycles | 18.195/18.228/18.289 | 13.745/13.755/13.816 | 0.755 | 18.336 | 0.750 |
| abi | return-record32 | abi | MATCH | cycles | 19.421/19.371/19.551 | 14.123/14.210/14.375 | 0.727 | 13.967 | 1.011 |
| abi | return-record8 | abi | MATCH | cycles | 11.200/11.203/11.213 | 5.492/5.512/5.578 | 0.490 | 5.520 | 0.995 |
| abi | string-const | abi+managed | MATCH | cycles | 4.869/4.869/4.869 | 3.243/3.241/3.246 | 0.666 | 3.301 | 0.982 |
| abi | string-value | abi+managed | MATCH | cycles | 15.062/15.115/15.238 | 3.243/3.240/3.243 | 0.215 | 3.242 | 1.000 |
| abi | virtual-method | abi | MATCH | cycles | 5.607/5.607/5.608 | 5.607/5.611/5.637 | 1.000 | 5.607 | 1.000 |
| algorithms | binary-search-256 | codegen | MATCH | cycles | 143.790/143.662/143.939 | 143.630/143.218/143.870 | 0.999 | 143.451 | 1.001 |
| algorithms | chacha20-block | codegen | MATCH | cycles | 18.618/18.694/18.824 | 7.783/7.789/7.807 | 0.418 | 7.785 | 1.000 |
| algorithms | crc32-bitwise-4k | codegen | MATCH | cycles | 9.608/9.580/9.609 | 8.975/8.988/9.014 | 0.934 | 9.465 | 0.948 |
| algorithms | generic-list-512 | rtl | MATCH | cycles | 7.355/7.441/7.978 | 7.434/7.424/7.439 | 1.011 | 7.416 | 1.002 |
| algorithms | lz-compress-4k | codegen+memory | MATCH | cycles | 138.488/138.849/139.323 | 118.634/118.362/118.634 | 0.857 | 117.776 | 1.007 |
| algorithms | lz-roundtrip-4k | codegen+memory | MATCH | cycles | 70.229/70.234/70.291 | 59.914/60.072/60.291 | 0.853 | 59.839 | 1.001 |
| algorithms | open-hash-4096 | codegen+memory | MATCH | cycles | 6.934/6.943/6.993 | 7.286/7.324/7.402 | 1.051 | 7.375 | 0.988 |
| algorithms | quicksort-4096 | codegen+rtl | MATCH | cycles | 119.046/119.113/120.292 | 114.424/114.572/115.457 | 0.961 | 118.008 | 0.970 |
| algorithms | sha256-4k | codegen | MATCH | cycles | 17.253/17.207/17.323 | 15.907/15.901/15.946 | 0.922 | 15.950 | 0.997 |
| calibration | asm-dependent-add | calibration | MATCH | cycles | 0.981/0.985/0.996 | 0.981/0.982/0.986 | 1.000 | 0.981 | 1.000 |
| calibration | asm-memory-read-64m | calibration | MATCH | cycles | 0.147/0.156/0.171 | 0.151/0.154/0.168 | 1.030 | 0.150 | 1.006 |
| calibration | asm-memory-write-64m | calibration | MATCH | cycles | 0.225/0.228/0.248 | 0.245/0.233/0.248 | 1.087 | 0.233 | 1.050 |
| calibration | asm-mixed-integer | calibration | MATCH | cycles | 1.275/1.286/1.308 | 1.275/1.286/1.304 | 1.000 | 1.281 | 0.995 |
| codegen | abs-int | codegen | MATCH | cycles | 1.786/1.787/1.799 | 1.594/1.599/1.611 | 0.892 | 1.571 | 1.015 |
| codegen | branch-predictable | codegen | MATCH | cycles | 1.650/1.653/1.659 | 2.440/2.437/2.440 | 1.478 | 1.650 | 1.478 |
| codegen | branch-random | codegen | MATCH | cycles | 2.781/2.776/2.826 | 2.043/2.018/2.062 | 0.735 | 2.048 | 0.997 |
| codegen | call-eight-args | codegen | MATCH | cycles | 12.873/12.864/12.876 | 7.886/7.897/7.927 | 0.613 | 7.873 | 1.002 |
| codegen | call-indirect | codegen | MATCH | cycles | 4.043/4.047/4.071 | 4.042/4.045/4.064 | 1.000 | 4.055 | 0.997 |
| codegen | call-inline | codegen | MATCH | cycles | 2.378/2.376/2.378 | 2.366/2.365/2.378 | 0.995 | 2.366 | 1.000 |
| codegen | call-interface | codegen+rtl | MATCH | cycles | 4.895/4.895/4.896 | 5.675/5.675/5.675 | 1.159 | 6.446 | 0.880 |
| codegen | call-unit-direct | codegen | MATCH | cycles | 2.378/2.376/2.378 | 2.366/2.367/2.390 | 0.995 | 2.378 | 0.995 |
| codegen | call-virtual | codegen | MATCH | cycles | 5.645/5.645/5.645 | 5.615/5.623/5.645 | 0.995 | 4.085 | 1.374 |
| codegen | case-dense | codegen | MATCH | cycles | 3.977/3.924/3.977 | 5.523/5.524/5.544 | 1.389 | 5.446 | 1.014 |
| codegen | case-sparse | codegen | MATCH | cycles | 4.312/4.303/4.312 | 4.208/4.211/4.230 | 0.976 | 4.198 | 1.002 |
| codegen | concrete-reverse-int | codegen | MATCH | cycles | 2.860/2.866/2.884 | 3.280/3.289/3.302 | 1.147 | 3.295 | 0.995 |
| codegen | concrete-reverse-rec | codegen | MATCH | cycles | 14.206/14.206/14.206 | 5.249/5.203/5.257 | 0.369 | 5.104 | 1.028 |
| codegen | cse-expression | codegen | MATCH | cycles | 4.896/4.897/4.901 | 4.299/4.287/4.299 | 0.878 | 4.033 | 1.066 |
| codegen | currency-mul-div | codegen+rtl | MATCH | cycles | 200.835/201.053/202.445 | 41.146/41.148/41.188 | 0.205 | 41.154 | 1.000 |
| codegen | dead-store-chain | codegen | MATCH | cycles | 5.056/5.052/5.058 | 3.658/3.649/3.658 | 0.724 | 3.242 | 1.129 |
| codegen | dep-add | codegen | MATCH | cycles | 3.154/3.152/3.154 | 3.154/3.152/3.154 | 1.000 | 3.138 | 1.005 |
| codegen | double-mixed | codegen | MATCH | cycles | 4.237/4.237/4.237 | 4.237/4.238/4.242 | 1.000 | 4.237 | 1.000 |
| codegen | enum-set-membership | codegen | MATCH | cycles | 4.186/4.183/4.187 | 4.004/4.013/4.059 | 0.956 | 4.174 | 0.959 |
| codegen | fillchar-4k | rtl | MATCH | cycles | 0.037/0.037/0.037 | 0.049/0.049/0.050 | 1.333 | 0.049 | 1.000 |
| codegen | for-byte-0-255 | codegen | MATCH | cycles | 1.629/1.633/1.647 | 0.843/0.848/0.860 | 0.517 | 0.843 | 1.000 |
| codegen | for-downto | codegen | MATCH | cycles | 0.835/0.841/0.852 | 1.613/1.613/1.622 | 1.933 | 0.834 | 1.933 |
| codegen | for-length-array | codegen | MATCH | cycles | 1.632/1.627/1.632 | 1.603/1.606/1.612 | 0.983 | 0.831 | 1.928 |
| codegen | for-length-string | codegen | MATCH | cycles | 1.548/1.539/1.550 | 0.886/0.884/0.886 | 0.572 | 1.603 | 0.552 |
| codegen | for-runtime-0-0 | codegen | MATCH | cycles | 2.378/2.375/2.378 | 1.585/1.582/1.585 | 0.667 | 1.585 | 1.000 |
| codegen | for-runtime-0-255 | codegen | MATCH | cycles | 1.639/1.639/1.639 | 2.215/2.216/2.216 | 1.352 | 1.629 | 1.360 |
| codegen | generic-reverse-int | codegen | MATCH | cycles | 2.778/2.779/2.809 | 3.284/3.280/3.285 | 1.182 | 3.294 | 0.997 |
| codegen | generic-reverse-rec | codegen | MATCH | cycles | 14.268/14.236/14.268 | 5.310/5.316/5.339 | 0.372 | 5.092 | 1.043 |
| codegen | ilp-four-lanes | codegen | MATCH | cycles | 0.797/0.799/0.801 | 0.797/0.797/0.797 | 1.000 | 0.797 | 1.000 |
| codegen | int32-div-const | codegen | MATCH | cycles | 2.396/2.396/2.409 | 1.882/1.888/1.902 | 0.785 | 1.839 | 1.023 |
| codegen | int32-mixed | codegen | MATCH | cycles | 4.707/4.710/4.732 | 4.707/4.707/4.710 | 1.000 | 4.707 | 1.000 |
| codegen | int64-div-const | codegen | MATCH | cycles | 2.187/2.191/2.225 | 2.194/2.210/2.234 | 1.003 | 2.140 | 1.025 |
| codegen | int64-mod-latency | codegen | MATCH | cycles | 11.767/11.767/11.767 | 11.767/11.767/11.768 | 1.000 | 11.767 | 1.000 |
| codegen | int8-int16-promotion | codegen | MATCH | cycles | 5.753/5.753/5.754 | 5.504/5.508/5.536 | 0.957 | 5.504 | 1.000 |
| codegen | loop-early-exit | codegen | MATCH | cycles | 1.730/1.730/1.732 | 1.734/1.734/1.736 | 1.002 | 1.732 | 1.002 |
| codegen | math-transcendentals | rtl | MATCH | cycles | 11.264/11.288/11.378 | 11.154/11.147/11.164 | 0.990 | 11.107 | 1.004 |
| codegen | matrix-double-16 | codegen | MATCH | cycles | 4.153/4.170/4.212 | 3.812/3.822/3.837 | 0.918 | 3.870 | 0.985 |
| codegen | minmax-double | codegen+rtl | MATCH | cycles | 5.757/5.757/5.760 | 2.123/2.120/2.129 | 0.369 | 2.155 | 0.985 |
| codegen | minmax-double-special | codegen+rtl | MATCH | cycles | 4.104/4.106/4.125 | 3.098/3.090/3.098 | 0.755 | 3.292 | 0.941 |
| codegen | minmax-int | codegen+rtl | MATCH | cycles | 1.771/1.776/1.793 | 1.598/1.598/1.598 | 0.902 | 1.592 | 1.004 |
| codegen | move-4k | rtl | MATCH | cycles | 0.032/0.031/0.032 | 0.034/0.034/0.034 | 1.062 | 0.034 | 1.000 |
| codegen | mul-lea | codegen | MATCH | cycles | 0.802/0.803/0.809 | 0.842/0.844/0.846 | 1.051 | 0.837 | 1.007 |
| codegen | packed-odd-sizes | codegen | MATCH | cycles | 0.811/0.809/0.812 | 0.815/0.814/0.816 | 1.005 | 0.812 | 1.003 |
| codegen | pointer-alias-update | codegen+memory | MATCH | cycles | 1.670/1.670/1.671 | 1.676/1.676/1.676 | 1.003 | 1.664 | 1.007 |
| codegen | pointer-chase | codegen+memory | MATCH | cycles | 9.632/9.641/9.660 | 9.662/9.675/9.705 | 1.003 | 9.647 | 1.002 |
| codegen | record-aligned | codegen | MATCH | cycles | 3.239/3.239/3.256 | 3.512/3.518/3.532 | 1.085 | 3.052 | 1.151 |
| codegen | record-packed | codegen | MATCH | cycles | 4.137/4.137/4.137 | 4.563/4.568/4.584 | 1.103 | 4.575 | 0.997 |
| codegen | recursion-tree-8 | codegen | MATCH | cycles | 4.533/4.532/4.547 | 4.533/4.533/4.534 | 1.000 | 5.705 | 0.795 |
| codegen | scan-dram | codegen+memory | MATCH | cycles | 1.173/1.192/1.235 | 1.203/1.220/1.296 | 1.026 | 1.229 | 0.979 |
| codegen | scan-l1 | codegen+memory | MATCH | cycles | 0.796/0.796/0.796 | 0.796/0.796/0.796 | 1.000 | 0.799 | 0.996 |
| codegen | scan-l2 | codegen+memory | MATCH | cycles | 0.794/0.796/0.798 | 0.794/0.796/0.798 | 1.000 | 0.794 | 1.000 |
| codegen | scan-llc | codegen+memory | MATCH | cycles | 0.803/0.818/0.902 | 0.805/0.804/0.809 | 1.002 | 0.852 | 0.945 |
| codegen | scan-random | codegen+memory | MATCH | cycles | 2.522/2.593/2.785 | 2.225/2.198/2.228 | 0.882 | 2.207 | 1.008 |
| codegen | scan-strided | codegen+memory | MATCH | cycles | 2.144/2.135/2.145 | 2.123/2.130/2.155 | 0.990 | 3.368 | 0.630 |
| codegen | single-mixed | codegen | MATCH | cycles | 6.280/6.295/6.380 | 6.273/6.277/6.305 | 0.999 | 6.282 | 0.998 |
| codegen | try-finally-normal | compiler+rtl | MATCH | cycles | 3.569/3.560/3.569 | 5.653/5.653/5.656 | 1.584 | 5.413 | 1.044 |
| codegen | uint32-div-const | codegen | MATCH | cycles | 1.762/1.769/1.782 | 1.554/1.547/1.554 | 0.882 | 1.547 | 1.005 |
| codegen | uint64-div-constant | codegen | MATCH | cycles | 2.423/2.427/2.436 | 2.104/2.106/2.117 | 0.868 | 1.967 | 1.070 |
| codegen | uint64-div-runtime | codegen | MATCH | cycles | 7.038/7.038/7.038 | 7.038/7.038/7.038 | 1.000 | 7.038 | 1.000 |
| codegen | uint64-mixed | codegen | MATCH | cycles | 6.275/6.285/6.341 | 4.707/4.710/4.732 | 0.750 | 4.707 | 1.000 |
| dispatch | class-name-rtti | rtl | MATCH | cycles | 35.916/35.938/36.485 | 15.351/15.358/15.432 | 0.427 | 14.553 | 1.055 |
| dispatch | function-pointer | codegen | MATCH | cycles | 4.756/4.759/4.781 | 5.586/5.582/5.586 | 1.175 | 4.756 | 1.174 |
| dispatch | generic-integer | codegen | MATCH | cycles | 5.491/5.491/5.492 | 4.707/4.708/4.710 | 0.857 | 4.707 | 1.000 |
| dispatch | generic-record | codegen | MATCH | cycles | 5.520/5.520/5.524 | 4.940/4.929/4.941 | 0.895 | 5.146 | 0.960 |
| dispatch | interface-monomorphic | compiler+rtl | MATCH | cycles | 7.209/7.203/7.209 | 5.637/5.633/5.637 | 0.782 | 5.657 | 0.996 |
| dispatch | interface-polymorphic | compiler+rtl | MATCH | cycles | 26.726/26.694/26.728 | 27.394/27.295/27.459 | 1.025 | 27.179 | 1.008 |
| dispatch | list-enumerator | rtl+mm | MATCH | cycles | 8.871/8.874/9.057 | 5.443/5.505/5.729 | 0.614 | 5.484 | 0.992 |
| dispatch | list-index | rtl+mm | MATCH | cycles | 2.419/2.419/2.420 | 2.421/2.421/2.424 | 1.001 | 3.197 | 0.757 |
| dispatch | managed-object-create-free | rtl+mm | MATCH | cycles | 463.511/463.845/465.901 | 313.368/311.966/313.510 | 0.676 | 303.635 | 1.032 |
| dispatch | object-create-free | rtl+mm | MATCH | cycles | 117.114/116.978/117.334 | 105.120/105.255/105.808 | 0.898 | 121.739 | 0.863 |
| dispatch | raise-catch | compiler+rtl+mm | MATCH | cycles | 3657.960/3657.603/3679.871 | 5678.888/5695.771/5753.118 | 1.552 | 5669.681 | 1.002 |
| dispatch | static-method | codegen | MATCH | cycles | 5.520/5.532/5.548 | 5.491/5.495/5.519 | 0.995 | 5.491 | 1.000 |
| dispatch | try-except-no-raise | compiler+rtl | MATCH | cycles | 4.731/4.735/4.756 | 4.707/4.707/4.710 | 0.995 | 4.707 | 1.000 |
| dispatch | virtual-monomorphic | codegen | MATCH | cycles | 5.615/5.615/5.615 | 5.578/5.578/5.583 | 0.993 | 5.615 | 0.993 |
| dispatch | virtual-polymorphic | codegen | MATCH | cycles | 25.075/25.175/25.410 | 25.870/26.869/28.011 | 1.032 | 27.438 | 0.943 |
| json | generate-64 | rtl | MATCH | cycles | 11316.875/11256.369/11350.521 | 4964.174/4963.144/4994.286 | 0.439 | 4987.712 | 0.995 |
| json | parse-large-custom-double | compiler+rtl | MATCH | cycles | 2345.382/2349.540/2376.484 | 2102.803/2117.236/2159.348 | 0.897 | 2163.569 | 0.972 |
| json | parse-medium-custom-double | compiler+rtl | MATCH | cycles | 2337.396/2344.888/2389.844 | 2100.020/2115.102/2143.994 | 0.898 | 2058.828 | 1.020 |
| json | parse-medium-strtofloat | rtl | MATCH | cycles | 5515.938/5512.969/5544.141 | 4880.996/4855.603/4911.797 | 0.885 | 4605.273 | 1.060 |
| json | parse-small-custom-double | compiler+rtl | MATCH | cycles | 2249.936/2258.057/2314.683 | 2065.394/2073.815/2097.745 | 0.918 | 1977.062 | 1.045 |
| json | pipeline-parse-vwap-format | integrated | MATCH | cycles | 2341.354/2391.469/2455.156 | 2198.638/2167.294/2272.764 | 0.939 | 2072.373 | 1.061 |
| json | scan-large-4096 | codegen | MATCH | cycles | 4.137/4.143/4.283 | 5.773/5.803/5.882 | 1.396 | 4.625 | 1.248 |
| json | scan-medium-256 | codegen | MATCH | cycles | 4.409/4.393/4.409 | 6.189/6.212/6.298 | 1.404 | 4.927 | 1.256 |
| json | scan-small-16 | codegen | MATCH | cycles | 4.438/4.404/4.455 | 6.292/6.196/6.293 | 1.418 | 4.908 | 1.282 |
| kernels | base64-encode-4096 | application+text | MATCH | cycles | 2.978/2.978/2.980 | 2.756/2.750/2.758 | 0.925 | 2.754 | 1.001 |
| kernels | correlation-128x32 | application | MATCH | cycles | 7.841/7.876/8.039 | 7.768/7.810/7.852 | 0.991 | 7.806 | 0.995 |
| kernels | dijkstra-64 | application | MATCH | cycles | 13.253/13.218/13.253 | 11.618/11.619/11.657 | 0.877 | 11.966 | 0.971 |
| kernels | huffman-lengths-256 | application | MATCH | cycles | 4.748/4.751/4.771 | 4.019/4.028/4.041 | 0.847 | 4.033 | 0.996 |
| kernels | lu-decomposition-32 | application | MATCH | cycles | 1.662/1.672/1.687 | 1.664/1.669/1.711 | 1.001 | 1.708 | 0.974 |
| kernels | monte-carlo-4096 | application | MATCH | cycles | 14.844/14.869/14.921 | 6.574/6.578/6.609 | 0.443 | 6.564 | 1.002 |
| kernels | neural-dense-32x32 | application | MATCH | cycles | 1.706/1.707/1.714 | 1.596/1.648/1.788 | 0.936 | 1.660 | 0.962 |
| kernels | pixel-transform-4096 | application | MATCH | cycles | 4.732/4.732/4.733 | 4.975/4.976/5.002 | 1.051 | 4.947 | 1.006 |
| kernels | prime-sieve-16384 | application | MATCH | cycles | 5.348/5.350/5.382 | 4.027/4.029/4.043 | 0.753 | 4.155 | 0.969 |
| kernels | sparse-matvec-512x8 | application | MATCH | cycles | 1.825/1.825/1.835 | 1.725/1.727/1.735 | 0.945 | 1.724 | 1.000 |
| layout | aligned-read | codegen+memory | MATCH | cycles | 1.904/1.906/1.914 | 1.639/1.640/1.647 | 0.861 | 0.844 | 1.942 |
| layout | aos-all-fields | codegen+memory | MATCH | cycles | 4.810/4.810/4.813 | 4.708/4.715/4.732 | 0.979 | 4.732 | 0.995 |
| layout | aos-one-field | codegen+memory | MATCH | cycles | 1.604/1.608/1.619 | 0.993/0.999/1.034 | 0.619 | 0.993 | 1.000 |
| layout | dynamic-array | codegen+memory | MATCH | cycles | 1.596/1.595/1.604 | 0.792/0.794/0.798 | 0.496 | 0.792 | 1.000 |
| layout | fill-1024 | rtl | MATCH | cycles | 0.115/0.115/0.115 | 0.049/0.049/0.049 | 0.429 | 0.049 | 1.005 |
| layout | fill-16 | rtl | MATCH | cycles | 0.396/0.397/0.398 | 0.099/0.099/0.099 | 0.250 | 0.099 | 1.000 |
| layout | fill-256 | rtl | MATCH | cycles | 0.068/0.068/0.068 | 0.050/0.050/0.050 | 0.731 | 0.050 | 1.005 |
| layout | fill-64 | rtl | MATCH | cycles | 0.137/0.137/0.137 | 0.050/0.050/0.050 | 0.362 | 0.050 | 1.000 |
| layout | indexed-walk | codegen+memory | MATCH | cycles | 0.790/0.799/0.818 | 0.854/0.858/0.869 | 1.080 | 0.856 | 0.997 |
| layout | move-1024 | rtl | MATCH | cycles | 0.033/0.034/0.034 | 0.057/0.057/0.057 | 1.707 | 0.051 | 1.123 |
| layout | move-16 | rtl | MATCH | cycles | 0.299/0.299/0.299 | 0.100/0.099/0.100 | 0.333 | 0.067 | 1.492 |
| layout | move-256 | rtl | MATCH | cycles | 0.047/0.047/0.047 | 0.066/0.066/0.066 | 1.400 | 0.057 | 1.167 |
| layout | move-64 | rtl | MATCH | cycles | 0.100/0.100/0.100 | 0.066/0.066/0.066 | 0.663 | 0.066 | 1.000 |
| layout | packed-record | codegen+memory | MATCH | cycles | 4.580/4.582/4.585 | 3.154/3.154/3.155 | 0.689 | 3.154 | 1.000 |
| layout | pointer-walk | codegen+memory | MATCH | cycles | 0.790/0.790/0.790 | 0.836/0.837/0.843 | 1.058 | 0.854 | 0.980 |
| layout | soa-all-fields | codegen+memory | MATCH | cycles | 4.732/4.740/4.782 | 4.707/4.711/4.731 | 0.995 | 4.707 | 1.000 |
| layout | soa-one-field | codegen+memory | MATCH | cycles | 1.587/1.587/1.588 | 0.884/0.883/0.884 | 0.557 | 0.881 | 1.003 |
| layout | static-array | codegen+memory | MATCH | cycles | 0.790/0.792/0.795 | 0.856/0.856/0.860 | 1.083 | 0.855 | 1.001 |
| layout | unaligned-read | codegen+memory | MATCH | cycles | 1.920/1.920/1.920 | 0.847/0.847/0.847 | 0.441 | 0.852 | 0.995 |
| layout | variant-record | codegen+memory | MATCH | cycles | 6.080/6.066/6.080 | 2.908/2.872/2.908 | 0.478 | 2.644 | 1.100 |
| local-pressure | empty | codegen | MATCH | cycles | 4.756/4.749/4.760 | 3.963/3.964/3.984 | 0.833 | 4.756 | 0.833 |
| local-pressure | unused-buffers-100 | codegen+managed | MATCH | cycles | 380.504/379.614/380.506 | 3.963/3.969/4.005 | 0.010 | 5.520 | 0.718 |
| local-pressure | unused-mixed-300 | codegen+managed | MATCH | cycles | 722.174/720.795/723.077 | 4.756/4.756/4.756 | 0.007 | 4.756 | 1.000 |
| local-pressure | unused-plain-100 | codegen | MATCH | cycles | 4.731/4.735/4.756 | 3.963/3.963/3.963 | 0.838 | 4.731 | 0.838 |
| local-pressure | unused-strings-100 | codegen+managed | MATCH | cycles | 150.602/150.486/150.609 | 4.781/4.774/4.782 | 0.032 | 4.756 | 1.005 |
| local-pressure | used-buffers-100 | codegen+managed | MATCH | cycles | 2197.170/2218.774/2273.722 | 1770.776/1770.577/1771.366 | 0.806 | 1730.597 | 1.023 |
| local-pressure | used-mixed-300 | codegen+managed | MATCH | cycles | 3793.656/3811.357/3920.552 | 3563.245/3569.723/3586.250 | 0.939 | 3430.278 | 1.039 |
| local-pressure | used-plain-100 | codegen | MATCH | cycles | 115.740/117.035/124.853 | 112.559/112.561/112.567 | 0.973 | 112.550 | 1.000 |
| local-pressure | used-strings-100 | codegen+managed | MATCH | cycles | 1420.630/1423.410/1433.382 | 1407.555/1406.695/1409.207 | 0.991 | 1403.947 | 1.003 |
| loops | aliased-update | codegen | MATCH | cycles | 3.318/3.322/3.347 | 3.138/3.140/3.154 | 0.946 | 3.142 | 0.999 |
| loops | break-continue | codegen | MATCH | cycles | 1.965/1.965/1.966 | 1.670/1.668/1.670 | 0.850 | 1.673 | 0.998 |
| loops | for-down | codegen | MATCH | cycles | 1.754/1.751/1.756 | 1.647/1.647/1.647 | 0.939 | 1.641 | 1.004 |
| loops | for-up | codegen | MATCH | cycles | 1.654/1.655/1.663 | 1.644/1.645/1.653 | 0.994 | 1.554 | 1.058 |
| loops | histogram-random | codegen+memory | MATCH | cycles | 2.769/2.800/2.859 | 1.674/1.708/1.911 | 0.605 | 1.672 | 1.002 |
| loops | invariant-expression | codegen | MATCH | cycles | 2.105/2.104/2.105 | 1.812/1.816/1.822 | 0.861 | 1.650 | 1.098 |
| loops | loop-try-finally | compiler+rtl | MATCH | cycles | 4.577/4.586/4.612 | 4.949/4.950/4.982 | 1.081 | 5.227 | 0.947 |
| loops | loop-with-call | codegen | MATCH | cycles | 5.520/5.524/5.548 | 5.491/5.491/5.491 | 0.995 | 5.491 | 1.000 |
| loops | manual-copy-8192 | codegen+memory | MATCH | cycles | 0.809/0.809/0.810 | 0.799/0.799/0.800 | 0.987 | 1.595 | 0.501 |
| loops | nested-column-major | codegen+memory | MATCH | cycles | 1.636/1.633/1.636 | 1.601/1.601/1.601 | 0.979 | 1.601 | 1.000 |
| loops | nested-row-major | codegen+memory | MATCH | cycles | 1.601/1.601/1.601 | 1.626/1.627/1.635 | 1.016 | 1.602 | 1.015 |
| loops | nonaliased-update | codegen | MATCH | cycles | 3.281/3.293/3.316 | 3.528/3.552/3.659 | 1.075 | 3.306 | 1.067 |
| loops | prefix-dependency | codegen+memory | MATCH | cycles | 1.673/1.673/1.675 | 1.650/1.647/1.651 | 0.986 | 1.658 | 0.995 |
| loops | reduction-four-lanes | codegen | MATCH | cycles | 0.926/0.926/0.926 | 0.800/0.800/0.800 | 0.864 | 0.807 | 0.991 |
| loops | reduction-sum | codegen | MATCH | cycles | 2.354/2.357/2.367 | 2.366/2.364/2.366 | 1.005 | 2.354 | 1.005 |
| loops | repeat-runtime | codegen | MATCH | cycles | 1.675/1.674/1.676 | 1.725/1.726/1.727 | 1.030 | 1.683 | 1.025 |
| loops | strength-multiply-index | codegen | MATCH | cycles | 1.656/1.657/1.658 | 1.638/1.636/1.638 | 0.989 | 1.641 | 0.998 |
| loops | vector-add-8192 | codegen+memory | MATCH | cycles | 1.621/1.620/1.621 | 1.159/1.160/1.164 | 0.715 | 1.621 | 0.715 |
| loops | vector-dot-8192 | codegen+memory | MATCH | cycles | 2.366/2.368/2.378 | 2.354/2.357/2.366 | 0.995 | 2.366 | 0.995 |
| loops | while-runtime | codegen | MATCH | cycles | 1.674/1.674/1.674 | 1.679/1.677/1.680 | 1.003 | 1.691 | 0.993 |
| managed | closure-create-invoke | compiler+rtl | MATCH | cycles | 227.689/228.388/230.157 | 158.766/157.191/158.878 | 0.697 | 156.280 | 1.016 |
| managed | dynamic-array-assign | rtl | MATCH | cycles | 15.328/15.375/15.644 | 13.994/14.026/14.070 | 0.913 | 14.061 | 0.995 |
| managed | dynamic-array-deep-copy | rtl | MATCH | cycles | 58.352/58.467/60.213 | 51.594/51.593/51.804 | 0.884 | 53.216 | 0.970 |
| managed | ignored-interface-result | compiler+rtl | MATCH | cycles | 25.675/25.476/25.685 | 23.679/23.679/23.679 | 0.922 | 22.928 | 1.033 |
| managed | ignored-string-result | compiler+rtl | MATCH | cycles | 19.269/19.248/19.703 | 16.385/16.482/17.067 | 0.850 | 15.559 | 1.053 |
| managed | interface-copy-call | compiler+rtl | MATCH | cycles | 20.126/20.124/20.129 | 20.397/20.388/20.519 | 1.013 | 55.139 | 0.370 |
| managed | managed-early-exit | compiler+rtl | MATCH | cycles | 71.636/72.602/76.074 | 66.371/66.601/67.161 | 0.926 | 64.532 | 1.029 |
| managed | managed-exception-cleanup | compiler+rtl | MATCH | cycles | 546.524/547.580/554.106 | 817.888/825.933/852.683 | 1.497 | 810.887 | 1.009 |
| managed | managed-record-return | compiler+rtl | MATCH | cycles | 221.530/224.156/235.162 | 113.887/113.295/113.906 | 0.514 | 121.888 | 0.934 |
| managed | out-string-forwarding | compiler+rtl | MATCH | cycles | 24.692/24.754/24.981 | 24.177/24.232/24.304 | 0.979 | 21.938 | 1.102 |
| managed | rawbytestring-assign | rtl | MATCH | cycles | 12.492/12.505/12.561 | 12.619/12.633/12.684 | 1.010 | 12.613 | 1.000 |
| managed | rawbytestring-assign-mt | rtl | MATCH | cycles | 13.257/13.255/13.265 | 13.449/13.454/13.466 | 1.015 | 13.450 | 1.000 |
| managed | unicode-assign | rtl | MATCH | cycles | 12.493/12.498/12.551 | 12.612/12.640/12.683 | 1.010 | 12.663 | 0.996 |
| managed | unicode-assign-mt | rtl | MATCH | cycles | 13.245/13.169/13.256 | 13.449/13.441/13.464 | 1.015 | 13.435 | 1.001 |
| managed | unicode-concat | rtl | MATCH | cycles | 83.925/84.826/86.530 | 43.247/43.357/43.510 | 0.515 | 48.704 | 0.888 |
| managed | unicode-return-ppu | compiler+rtl | MATCH | cycles | 13.250/13.393/14.227 | 13.360/13.368/13.387 | 1.008 | 13.520 | 0.988 |
| managed | variant-numeric | rtl | MATCH | cycles | 136.029/136.055/136.074 | 161.773/161.820/162.049 | 1.189 | 163.750 | 0.988 |
| mm | alloc-free-100500 | mm | MATCH | cycles | 52.085/52.452/54.245 | 40.801/40.799/40.805 | 0.783 | 68.458 | 0.596 |
| mm | alloc-free-1024 | mm | MATCH | cycles | 51.465/52.000/53.363 | 65.631/66.002/66.614 | 1.275 | 82.919 | 0.792 |
| mm | alloc-free-16 | mm | MATCH | cycles | 24.155/24.135/24.813 | 25.115/25.406/26.005 | 1.040 | 26.223 | 0.958 |
| mm | alloc-free-16k | mm | MATCH | cycles | 52.141/52.100/52.470 | 40.769/40.661/40.774 | 0.782 | 78.955 | 0.516 |
| mm | alloc-free-17408 | mm | MATCH | cycles | 52.146/52.309/53.441 | 40.740/40.717/40.787 | 0.781 | 78.516 | 0.519 |
| mm | alloc-free-17409 | mm | MATCH | cycles | 52.165/52.412/53.637 | 40.747/40.751/40.776 | 0.781 | 79.164 | 0.515 |
| mm | alloc-free-1m | mm | MATCH | cycles | 27059.821/24896.301/28454.762 | 27105.194/25419.790/29808.077 | 1.002 | 53901.848 | 0.503 |
| mm | alloc-free-256 | mm | MATCH | cycles | 51.604/52.552/55.496 | 65.325/65.900/69.661 | 1.266 | 40.751 | 1.603 |
| mm | alloc-free-2m | mm | MATCH | cycles | 34085.880/34020.367/34605.522 | 34192.910/35140.421/38906.667 | 1.003 | 64426.625 | 0.531 |
| mm | alloc-free-64 | mm | MATCH | cycles | 24.159/24.641/27.533 | 26.584/26.586/26.597 | 1.100 | 26.325 | 1.010 |
| mm | fragmented-mixed | mm | MATCH | cycles | 1043.191/1047.584/1129.053 | 1099.968/1104.918/1223.960 | 1.054 | 1845.728 | 0.596 |
| mm | realloc-grow | mm | MATCH | cycles | 57.019/57.696/61.138 | 59.421/59.592/60.148 | 1.042 | 106.449 | 0.558 |
| mm | realloc-shrink | mm | MATCH | cycles | 30.479/30.350/30.491 | 29.704/29.739/29.863 | 0.975 | 124.226 | 0.239 |
| mm | ring-mixed-16-to-1m | mm | MATCH | cycles | 1914.844/1923.962/1992.402 | 1605.815/1622.899/1674.375 | 0.839 | 4682.275 | 0.343 |
| mm | ring-same-class-96 | mm | MATCH | cycles | 13.081/12.951/13.254 | 13.737/13.811/14.627 | 1.050 | 16.972 | 0.809 |
| numeric | bit-boolean | codegen | MATCH | cycles | 9.217/9.218/9.219 | 6.275/6.280/6.309 | 0.681 | 6.275 | 1.000 |
| numeric | double-arithmetic | codegen | MATCH | cycles | 5.489/5.497/5.521 | 5.490/5.494/5.519 | 1.000 | 5.490 | 1.000 |
| numeric | int-double-convert | codegen+rtl | MATCH | cycles | 8.074/8.068/8.075 | 3.351/3.354/3.369 | 0.415 | 3.344 | 1.002 |
| numeric | int32-add-mul | codegen | MATCH | cycles | 3.636/3.627/3.636 | 3.943/3.950/3.990 | 1.085 | 3.942 | 1.000 |
| numeric | int32-div-runtime | codegen | MATCH | cycles | 9.414/9.487/9.878 | 9.414/9.428/9.511 | 1.000 | 9.414 | 1.000 |
| numeric | int64-add-mul | codegen | MATCH | cycles | 3.963/3.966/3.984 | 3.963/3.969/3.984 | 1.000 | 3.963 | 1.000 |
| numeric | int64-div-runtime | codegen | MATCH | cycles | 14.040/14.040/14.041 | 14.040/14.040/14.042 | 1.000 | 14.040 | 1.000 |
| numeric | min-max-mixed | codegen | MATCH | cycles | 3.294/3.295/3.297 | 2.135/2.136/2.137 | 0.648 | 2.203 | 0.969 |
| numeric | overflow-checked | codegen | MATCH | cycles | 3.242/3.247/3.259 | 3.259/3.256/3.259 | 1.005 | 2.489 | 1.309 |
| numeric | overflow-unchecked | codegen | MATCH | cycles | 2.354/2.362/2.378 | 2.353/2.359/2.378 | 1.000 | 2.365 | 0.995 |
| numeric | range-checked-index | codegen | MATCH | cycles | 2.477/2.478/2.483 | 2.489/2.488/2.490 | 1.005 | 1.703 | 1.462 |
| numeric | rotate-mix | codegen | MATCH | cycles | 6.276/6.276/6.276 | 4.706/4.711/4.731 | 0.750 | 4.706 | 1.000 |
| numeric | shift-constant | codegen | MATCH | cycles | 2.378/2.380/2.391 | 2.378/2.380/2.390 | 1.000 | 2.378 | 1.000 |
| numeric | shift-variable | codegen | MATCH | cycles | 2.527/2.531/2.542 | 2.527/2.529/2.541 | 1.000 | 2.515 | 1.005 |
| numeric | single-arithmetic | codegen | MATCH | cycles | 10.138/10.138/10.139 | 10.138/10.137/10.138 | 1.000 | 10.136 | 1.000 |
| numeric | single-double-convert | codegen | MATCH | cycles | 4.880/4.888/4.906 | 2.545/2.547/2.558 | 0.521 | 2.342 | 1.087 |
| numeric | small-set-ops | codegen | MATCH | cycles | 2.834/2.965/3.281 | 0.753/0.753/0.756 | 0.266 | 0.704 | 1.070 |
| numeric | uint32-div-constant | codegen | MATCH | cycles | 5.538/5.546/5.596 | 4.140/4.146/4.183 | 0.748 | 4.150 | 0.998 |
| numeric | uint64-div-constant | codegen | MATCH | cycles | 4.880/4.887/4.906 | 4.313/4.324/4.353 | 0.884 | 4.270 | 1.010 |
| numeric | unchecked-index | codegen | MATCH | cycles | 1.712/1.711/1.713 | 1.691/1.691/1.691 | 0.988 | 1.703 | 0.993 |
| numeric | wide-set-ops | codegen+rtl | MATCH | cycles | 90.365/90.378/90.411 | 27.674/27.719/27.818 | 0.306 | 27.697 | 0.999 |
| rtl | datetime-encode-decode | rtl | MATCH | cycles | 247.781/248.349/250.969 | 141.923/141.938/142.041 | 0.573 | 143.359 | 0.990 |
| rtl | datetime-format | rtl+mm | MATCH | cycles | 2108.651/2107.329/2127.151 | 1280.453/1282.997/1291.915 | 0.607 | 1242.622 | 1.030 |
| rtl | datetime-ms-arith | rtl | MATCH | cycles | 171.080/171.301/171.804 | 31.544/31.613/31.707 | 0.184 | 32.332 | 0.976 |
| rtl | datetime-now | rtl | MATCH | cycles | 194.557/194.407/194.565 | 211.818/211.813/211.826 | 1.089 | 211.811 | 1.000 |
| rtl | dictionary-512 | rtl+mm | MATCH | cycles | 65.678/65.735/66.109 | 59.415/59.606/59.957 | 0.905 | 60.532 | 0.982 |
| rtl | dictionary-add-512 | rtl+mm | MATCH | cycles | 90.342/90.359/90.713 | 80.629/80.801/81.263 | 0.892 | 82.799 | 0.974 |
| rtl | dictionary-add-reserved-512 | rtl+mm | MATCH | cycles | 93.752/94.006/94.716 | 66.398/66.466/66.819 | 0.708 | 66.531 | 0.998 |
| rtl | dictionary-capacity-1024 | rtl+mm | MATCH | cycles | 18100.703/18136.723/18297.760 | 779.712/780.762/789.297 | 0.043 | 1086.388 | 0.718 |
| rtl | dictionary-create-free | rtl+mm | MATCH | cycles | 288.578/289.290/291.939 | 284.237/284.043/285.935 | 0.985 | 291.735 | 0.974 |
| rtl | dictionary-get | rtl | MATCH | cycles | 42.993/43.083/43.358 | 38.911/38.888/39.256 | 0.905 | 39.057 | 0.996 |
| rtl | dictionary-string-get | rtl | MATCH | cycles | 67.501/67.466/67.973 | 43.274/43.538/43.986 | 0.641 | 44.483 | 0.973 |
| rtl | dictionary-update-remove-256 | rtl+mm | MATCH | cycles | 91.792/92.157/93.036 | 101.714/101.759/102.336 | 1.108 | 99.074 | 1.027 |
| rtl | dynamic-array-capacity-512 | rtl+mm | MATCH | cycles | 192.197/194.746/205.538 | 223.572/224.075/224.933 | 1.163 | 186.771 | 1.197 |
| rtl | dynamic-array-copy-512 | rtl+mm | MATCH | cycles | 0.218/0.220/0.225 | 0.319/0.313/0.322 | 1.465 | 0.358 | 0.891 |
| rtl | floattostr-double | rtl+mm | MATCH | cycles | 450.859/450.807/454.946 | 400.253/400.431/403.172 | 0.888 | 398.365 | 1.005 |
| rtl | format-float | rtl+mm | MATCH | cycles | 675.888/676.786/680.335 | 366.851/366.057/368.301 | 0.543 | 359.535 | 1.020 |
| rtl | format-integer | rtl+mm | MATCH | cycles | 227.021/226.583/227.053 | 72.270/72.412/72.763 | 0.318 | 71.043 | 1.017 |
| rtl | format-literal | rtl+mm | MATCH | cycles | 134.004/134.795/137.124 | 110.755/110.728/110.774 | 0.827 | 113.282 | 0.978 |
| rtl | format-mixed | rtl+mm | MATCH | cycles | 832.587/837.636/846.880 | 553.650/554.167/557.070 | 0.665 | 573.775 | 0.965 |
| rtl | format-string | rtl+mm | MATCH | cycles | 147.426/147.448/147.572 | 13.694/13.812/14.493 | 0.093 | 13.694 | 1.000 |
| rtl | generic-list-add-reserved | rtl | MATCH | cycles | 10.896/11.155/12.374 | 11.585/11.614/11.764 | 1.063 | 8.466 | 1.368 |
| rtl | generic-list-binarysearch | rtl | MATCH | cycles | 111.704/111.412/113.289 | 74.742/75.285/76.445 | 0.669 | 81.623 | 0.916 |
| rtl | generic-list-capacity-512 | rtl+mm | MATCH | cycles | 421.362/427.236/442.194 | 427.693/430.981/436.438 | 1.015 | 402.705 | 1.062 |
| rtl | generic-list-create-free | rtl+mm | MATCH | cycles | 215.359/214.441/215.759 | 202.922/201.676/202.936 | 0.942 | 231.462 | 0.877 |
| rtl | generic-list-delete-front-128 | rtl | MATCH | cycles | 38.245/38.105/38.250 | 38.340/38.322/38.747 | 1.002 | 37.434 | 1.024 |
| rtl | generic-list-delete-tail-512 | rtl | MATCH | cycles | 21.056/21.260/22.107 | 15.624/15.751/16.080 | 0.742 | 15.789 | 0.990 |
| rtl | generic-list-enumerator-512 | rtl | MATCH | cycles | 9.374/9.484/9.784 | 6.372/6.433/6.857 | 0.680 | 6.405 | 0.995 |
| rtl | generic-list-growth-512 | rtl+mm | MATCH | cycles | 14.906/15.038/15.797 | 15.304/15.320/15.436 | 1.027 | 15.820 | 0.967 |
| rtl | generic-list-index-512 | rtl | MATCH | cycles | 3.444/3.518/3.885 | 3.928/3.923/3.931 | 1.141 | 3.795 | 1.035 |
| rtl | generic-list-indexof | rtl | MATCH | cycles | 431.619/430.690/431.631 | 132.493/132.585/133.164 | 0.307 | 131.240 | 1.010 |
| rtl | generic-list-remove-128 | rtl | MATCH | cycles | 141.672/141.860/142.381 | 65.096/64.531/66.049 | 0.459 | 55.692 | 1.169 |
| rtl | generic-list-reserved-512 | rtl+mm | MATCH | cycles | 8.912/8.932/8.990 | 9.311/9.315/9.440 | 1.045 | 9.370 | 0.994 |
| rtl | generic-list-sort-512 | rtl | MATCH | cycles | 61818.611/61705.169/61866.111 | 45917.959/45805.023/45917.959 | 0.743 | 47298.125 | 0.971 |
| rtl | helper-compareto | rtl | MATCH | cycles | 36.795/36.913/37.326 | 31.826/31.678/31.875 | 0.865 | 31.947 | 0.996 |
| rtl | helper-endswith-nocase | rtl+mm | MATCH | cycles | 210.329/210.978/213.510 | 11.865/11.918/12.033 | 0.056 | 11.883 | 0.999 |
| rtl | helper-indexof-string | rtl+mm | MATCH | cycles | 2342.665/2335.265/2343.055 | 1850.456/1852.720/1856.003 | 0.790 | 1811.794 | 1.021 |
| rtl | helper-split-16 | rtl+mm | MATCH | cycles | 91.863/91.944/92.248 | 81.565/81.444/81.585 | 0.888 | 80.565 | 1.012 |
| rtl | helper-startswith | rtl | MATCH | cycles | 15.248/15.226/15.250 | 12.248/12.246/12.263 | 0.803 | 12.286 | 0.997 |
| rtl | helper-startswith-nocase | rtl+mm | MATCH | cycles | 278.058/277.996/279.824 | 17.816/17.825/17.897 | 0.064 | 17.410 | 1.023 |
| rtl | inttohex-int64 | rtl+mm | MATCH | cycles | 42.295/42.275/42.316 | 76.279/76.250/76.472 | 1.804 | 72.747 | 1.049 |
| rtl | inttostr-int32 | rtl+mm | MATCH | cycles | 29.590/29.615/29.779 | 30.269/30.339/30.431 | 1.023 | 31.683 | 0.955 |
| rtl | inttostr-int64 | rtl+mm | MATCH | cycles | 32.941/32.932/32.958 | 34.877/34.884/34.911 | 1.059 | 36.851 | 0.946 |
| rtl | lowercase-short | rtl+mm | MATCH | cycles | 29.920/29.811/29.924 | 35.077/35.119/35.248 | 1.172 | 34.874 | 1.006 |
| rtl | memorystream-64k | rtl+mm | MATCH | cycles | 0.055/0.055/0.056 | 0.055/0.055/0.055 | 0.994 | 0.056 | 0.987 |
| rtl | memorystream-write-small | rtl+mm | MATCH | cycles | 15.604/15.641/15.687 | 11.943/11.951/11.999 | 0.765 | 12.612 | 0.947 |
| rtl | object-alloc-zero-free | mm | MATCH | cycles | 26.576/26.492/26.577 | 28.840/28.845/28.867 | 1.085 | 36.042 | 0.800 |
| rtl | object-create-free | rtl+mm | MATCH | cycles | 98.291/97.984/98.801 | 73.306/74.228/75.767 | 0.746 | 89.012 | 0.824 |
| rtl | object-create-virtual-free | rtl+mm | MATCH | cycles | 108.367/107.912/108.371 | 126.756/126.710/128.171 | 1.170 | 99.224 | 1.277 |
| rtl | object-new-freeinstance | rtl+mm | MATCH | cycles | 63.412/63.382/63.811 | 53.386/53.314/53.674 | 0.842 | 68.654 | 0.778 |
| rtl | object-virtual-call | rtl | MATCH | cycles | 4.075/4.075/4.075 | 4.832/4.832/4.832 | 1.186 | 4.048 | 1.194 |
| rtl | queue-512 | rtl+mm | MATCH | cycles | 20.095/20.085/20.144 | 17.306/17.310/17.386 | 0.861 | 16.674 | 1.038 |
| rtl | queue-reserved-512 | rtl | MATCH | cycles | 18.841/18.850/18.964 | 16.866/16.870/16.955 | 0.895 | 15.310 | 1.102 |
| rtl | sametext-short | rtl | MATCH | cycles | 12.815/12.816/12.819 | 13.393/13.511/13.773 | 1.045 | 13.396 | 1.000 |
| rtl | stack-512 | rtl | MATCH | cycles | 16.831/16.813/16.862 | 15.989/16.000/16.054 | 0.950 | 15.201 | 1.052 |
| rtl | str-double-general | rtl | MATCH | cycles | 405.521/406.504/408.975 | 218.466/218.791/219.381 | 0.539 | 220.660 | 0.990 |
| rtl | string-replace-all | rtl+mm | MATCH | cycles | 299.893/302.794/324.920 | 332.369/332.252/333.494 | 1.108 | 345.763 | 0.961 |
| rtl | stringlist-add-128 | rtl+mm | MATCH | cycles | 82.626/82.709/83.458 | 42.778/42.915/43.253 | 0.518 | 45.266 | 0.945 |
| rtl | stringlist-add-sort-128 | rtl+mm | MATCH | cycles | 2420.379/2422.106/2441.161 | 2457.701/2463.214/2474.241 | 1.015 | 2431.830 | 1.011 |
| rtl | stringlist-delimited | rtl+mm | MATCH | cycles | 239.946/239.048/243.072 | 150.295/150.986/152.673 | 0.626 | 126.445 | 1.189 |
| rtl | stringlist-indexof-128 | rtl | MATCH | cycles | 28332.266/28356.864/28525.234 | 29576.172/29584.654/29687.500 | 1.044 | 29151.641 | 1.015 |
| rtl | stringlist-namevalue | rtl | MATCH | cycles | 26344.483/26355.775/26431.839 | 26318.239/26296.586/26390.568 | 0.999 | 27170.000 | 0.969 |
| rtl | stringlist-values | rtl+mm | MATCH | cycles | 7093.943/7090.588/7105.032 | 7106.060/7103.013/7119.873 | 1.002 | 7240.490 | 0.981 |
| rtl | stringstream-build | rtl+mm | MATCH | cycles | 290.114/291.885/295.089 | 281.301/282.094/284.270 | 0.970 | 284.716 | 0.988 |
| rtl | strtofloat-double | rtl+mm | MATCH | cycles | 277.832/278.506/280.006 | 266.757/265.545/266.997 | 0.960 | 283.010 | 0.943 |
| rtl | strtoint-int64 | rtl+mm | MATCH | cycles | 39.388/39.434/39.842 | 37.709/37.730/37.772 | 0.957 | 38.396 | 0.982 |
| rtl | trim-string | rtl+mm | MATCH | cycles | 61.298/60.662/61.861 | 35.249/35.663/36.328 | 0.575 | 36.480 | 0.966 |
| rtl | trystrtoint | rtl | MATCH | cycles | 39.465/39.481/39.571 | 44.939/44.926/44.945 | 1.139 | 45.261 | 0.993 |
| rtl | trystrtoint-edges | rtl | MATCH | cycles | 30.911/30.621/30.911 | 28.356/28.463/29.115 | 0.917 | 28.488 | 0.995 |
| rtl | unicode-comparetext | rtl | MATCH | cycles | 20.134/20.242/20.460 | 20.141/20.334/21.403 | 1.000 | 20.759 | 0.970 |
| rtl | unicode-concat-32 | rtl+mm | MATCH | cycles | 79.582/79.920/80.495 | 66.822/66.640/66.826 | 0.840 | 78.095 | 0.856 |
| rtl | unicode-copy-96 | rtl+mm | MATCH | cycles | 57.178/56.915/57.710 | 30.765/30.774/31.158 | 0.538 | 31.410 | 0.979 |
| rtl | unicode-lowercase-4k | rtl+mm | MATCH | cycles | 1.598/1.600/1.607 | 1.197/1.198/1.203 | 0.749 | 1.206 | 0.992 |
| rtl | unicode-pos-4k | rtl | MATCH | cycles | 4035.776/4146.099/4848.693 | 3309.940/3321.597/3368.513 | 0.820 | 3251.742 | 1.018 |
| rtl | unicode-uppercase-4k | rtl+mm | MATCH | cycles | 1.606/1.606/1.606 | 1.197/1.200/1.203 | 0.745 | 1.203 | 0.995 |
| rtl | utf8-decode-4k | rtl+mm | MATCH | cycles | 0.649/0.649/0.651 | 0.647/0.647/0.647 | 0.997 | 0.658 | 0.983 |
| rtl | utf8-encode-4k | rtl+mm | MATCH | cycles | 0.631/0.631/0.633 | 0.251/0.250/0.251 | 0.397 | 0.260 | 0.962 |
| rtl | utf8-encode-decode-4k | rtl+mm | MATCH | cycles | 1.287/1.287/1.288 | 0.901/0.901/0.905 | 0.700 | 0.920 | 0.980 |
| rtl-collections | array-binarysearch | rtl | MATCH | cycles | 120.621/120.197/120.702 | 110.623/112.671/126.872 | 0.917 | 114.939 | 0.962 |
| rtl-collections | array-integer-copy | rtl+mm | MATCH | cycles | 0.322/0.320/0.323 | 0.347/0.347/0.348 | 1.079 | 0.541 | 0.642 |
| rtl-collections | array-integer-sort | rtl+mm | MATCH | cycles | 48.280/48.187/48.299 | 38.434/38.434/38.690 | 0.796 | 36.675 | 1.048 |
| rtl-collections | array-string-sort | rtl+mm | MATCH | cycles | 206.712/206.857/207.812 | 156.161/156.692/157.423 | 0.755 | 159.027 | 0.982 |
| rtl-collections | dictionary-addorset | rtl | MATCH | cycles | 49.848/49.634/50.060 | 49.794/49.659/49.999 | 0.999 | 49.305 | 1.010 |
| rtl-collections | dictionary-collision-churn | rtl+mm | MATCH | cycles | 325.430/325.304/325.983 | 339.857/340.494/343.101 | 1.044 | 318.655 | 1.067 |
| rtl-collections | dictionary-contains-key | rtl | MATCH | cycles | 32.772/32.612/32.792 | 30.368/30.394/30.445 | 0.927 | 29.407 | 1.033 |
| rtl-collections | dictionary-contains-value | rtl | MATCH | cycles | 3101.804/3174.916/3410.500 | 1488.828/1489.460/1492.539 | 0.480 | 1585.043 | 0.939 |
| rtl-collections | dictionary-keys | rtl | MATCH | cycles | 38.071/38.148/38.319 | 19.979/19.953/19.996 | 0.525 | 20.064 | 0.996 |
| rtl-collections | dictionary-pairs | rtl | MATCH | cycles | 48.297/48.438/48.861 | 22.171/22.163/22.325 | 0.459 | 21.885 | 1.013 |
| rtl-collections | dictionary-string-add | rtl+mm | MATCH | cycles | 240.733/241.177/241.994 | 266.490/264.733/267.232 | 1.107 | 267.525 | 0.996 |
| rtl-collections | dictionary-string-clear | rtl+mm | MATCH | cycles | 312.965/315.707/324.760 | 362.775/362.762/364.971 | 1.159 | 360.827 | 1.005 |
| rtl-collections | dictionary-string-contains | rtl | MATCH | cycles | 57.585/57.449/57.640 | 39.768/39.892/40.118 | 0.691 | 39.049 | 1.018 |
| rtl-collections | dictionary-tryadd | rtl+mm | MATCH | cycles | 56.594/56.545/56.735 | 57.476/57.500/57.823 | 1.016 | 56.092 | 1.025 |
| rtl-collections | dictionary-values | rtl | MATCH | cycles | 38.287/38.253/38.613 | 19.883/19.858/19.923 | 0.519 | 20.101 | 0.989 |
| rtl-collections | list-exchange-reverse | rtl+mm | MATCH | cycles | 19.374/19.370/19.597 | 16.587/16.674/16.833 | 0.856 | 18.688 | 0.888 |
| rtl-collections | list-integer-addrange-4096 | rtl+mm | MATCH | cycles | 0.481/0.479/0.481 | 0.335/0.336/0.339 | 0.696 | 0.516 | 0.649 |
| rtl-collections | list-integer-clear-4096 | rtl+mm | MATCH | cycles | 0.428/0.426/0.428 | 0.272/0.272/0.272 | 0.635 | 0.446 | 0.609 |
| rtl-collections | list-integer-copy-construct | rtl+mm | MATCH | cycles | 2.575/2.582/2.595 | 1.682/1.606/1.686 | 0.653 | 1.836 | 0.916 |
| rtl-collections | list-integer-delete-insert-range-4096 | rtl+mm | MATCH | cycles | 0.191/0.192/0.192 | 0.155/0.156/0.157 | 0.813 | 0.145 | 1.070 |
| rtl-collections | list-integer-empty-create | rtl+mm | MATCH | cycles | 211.980/210.917/212.818 | 197.894/199.223/201.206 | 0.934 | 217.204 | 0.911 |
| rtl-collections | list-integer-exchange | rtl | MATCH | cycles | 5.026/5.030/5.054 | 6.084/6.080/6.090 | 1.210 | 6.076 | 1.001 |
| rtl-collections | list-integer-indexof | rtl | MATCH | cycles | 179.888/180.329/182.640 | 91.390/92.499/99.055 | 0.508 | 102.232 | 0.894 |
| rtl-collections | list-integer-insertrange-list-4096 | rtl+mm | MATCH | cycles | 1.013/1.017/1.029 | 1.127/1.128/1.132 | 1.113 | 1.429 | 0.789 |
| rtl-collections | list-integer-pack-alternating-4096 | rtl+mm | MATCH | cycles | 25.121/25.719/26.761 | 7.494/7.518/7.543 | 0.298 | 6.920 | 1.083 |
| rtl-collections | list-integer-reverse | rtl | MATCH | cycles | 1.764/1.776/1.799 | 2.371/2.291/2.400 | 1.344 | 2.254 | 1.052 |
| rtl-collections | list-integer-sort | rtl+mm | MATCH | cycles | 50.370/50.461/50.663 | 40.061/40.047/40.218 | 0.795 | 39.052 | 1.026 |
| rtl-collections | list-string-add-reserved | rtl+mm | MATCH | cycles | 26.095/26.102/26.214 | 29.162/29.195/29.329 | 1.118 | 27.099 | 1.076 |
| rtl-collections | list-string-addrange-4096 | rtl+mm | MATCH | cycles | 24.977/26.033/29.880 | 28.833/29.102/29.724 | 1.154 | 27.952 | 1.032 |
| rtl-collections | list-string-clear-4096 | rtl+mm | MATCH | cycles | 24.682/24.769/24.876 | 21.293/21.363/21.609 | 0.863 | 20.233 | 1.052 |
| rtl-collections | list-string-enumerate | rtl | MATCH | cycles | 15.538/15.745/16.151 | 14.367/14.638/14.933 | 0.925 | 14.552 | 0.987 |
| rtl-collections | list-string-indexof | rtl | MATCH | cycles | 1140.212/1147.922/1199.799 | 829.617/830.232/834.219 | 0.728 | 827.984 | 1.002 |
| rtl-collections | list-string-insert-delete | rtl+mm | MATCH | cycles | 72.510/76.867/87.021 | 75.225/75.488/75.817 | 1.037 | 73.470 | 1.024 |
| rtl-collections | list-string-insertrange-2048 | rtl+mm | MATCH | cycles | 62.748/62.854/63.593 | 110.836/112.127/114.297 | 1.766 | 125.952 | 0.880 |
| rtl-collections | list-string-read | rtl | MATCH | cycles | 3.247/3.248/3.250 | 2.472/2.472/2.475 | 0.761 | 2.463 | 1.004 |
| rtl-collections | list-string-sort | rtl+mm | MATCH | cycles | 219.298/219.760/220.563 | 179.200/179.462/180.094 | 0.817 | 181.798 | 0.986 |
| rtl-collections | list-string-toarray | rtl+mm | MATCH | cycles | 13.481/13.279/13.613 | 12.964/12.943/13.007 | 0.962 | 13.145 | 0.986 |
| rtl-collections | objectlist-owned-clear | rtl+mm | MATCH | cycles | 141.716/141.531/142.141 | 147.787/134.235/148.052 | 1.043 | 118.354 | 1.249 |
| rtl-collections | queue-enumerate | rtl | MATCH | cycles | 15.141/15.161/15.284 | 6.629/6.635/6.651 | 0.438 | 6.635 | 0.999 |
| rtl-collections | queue-integer-steady | rtl | MATCH | cycles | 0.141/0.141/0.141 | 0.118/0.118/0.118 | 0.837 | 0.112 | 1.057 |
| rtl-collections | queue-record128-steady | rtl | MATCH | cycles | 72.880/73.342/76.426 | 37.521/37.370/37.725 | 0.515 | 37.080 | 1.012 |
| rtl-collections | queue-string-clear | rtl+mm | MATCH | cycles | 61.872/61.976/63.340 | 54.530/54.464/54.555 | 0.881 | 48.598 | 1.122 |
| rtl-collections | queue-string-roundtrip | rtl+mm | MATCH | cycles | 49.827/50.597/52.943 | 27.514/27.556/27.923 | 0.552 | 23.292 | 1.181 |
| rtl-collections | queue-string-steady | rtl | MATCH | cycles | 50.129/51.153/53.099 | 25.907/25.962/26.043 | 0.517 | 23.046 | 1.124 |
| rtl-collections | stack-enumerate | rtl | MATCH | cycles | 9.763/9.726/9.875 | 6.595/6.637/6.755 | 0.675 | 6.608 | 0.998 |
| rtl-collections | stack-integer-roundtrip | rtl | MATCH | cycles | 16.972/17.027/17.119 | 14.781/14.807/15.010 | 0.871 | 15.529 | 0.952 |
| rtl-collections | stack-string-clear | rtl+mm | MATCH | cycles | 65.411/65.486/66.005 | 59.029/59.126/59.355 | 0.902 | 56.060 | 1.053 |
| rtl-collections | stack-string-roundtrip | rtl+mm | MATCH | cycles | 48.198/50.744/60.582 | 25.684/25.715/25.808 | 0.533 | 24.665 | 1.041 |
| threads | cross-thread-free-4 | mm | MATCH | tsc | 29383.521/30026.963/34241.980 | 4456.393/4582.318/5259.243 | 0.152 | 3503.162 | 1.272 |
| threads | false-sharing-4 | memory | MATCH | tsc | 20.859/21.165/21.610 | 21.496/21.385/22.183 | 1.031 | 21.631 | 0.994 |
| threads | independent-cpu-1 | compiler+os | MATCH | tsc | 3.165/3.285/3.931 | 3.188/3.197/3.276 | 1.007 | 3.176 | 1.004 |
| threads | independent-cpu-2 | compiler+os | MATCH | tsc | 1.864/1.914/2.032 | 1.900/1.948/2.101 | 1.019 | 1.609 | 1.181 |
| threads | independent-cpu-4 | compiler+os | MATCH | tsc | 0.937/0.940/0.960 | 0.944/0.951/0.966 | 1.007 | 0.808 | 1.167 |
| threads | independent-cpu-8 | compiler+os | MATCH | tsc | 0.519/0.553/0.636 | 0.520/0.535/0.590 | 1.002 | 0.440 | 1.181 |
| threads | locked-increment-4 | rtl+os | MATCH | tsc | 108.633/107.470/112.090 | 92.953/92.639/93.938 | 0.856 | 102.114 | 0.910 |
| threads | padded-counters-4 | memory | MATCH | tsc | 0.955/0.958/0.964 | 0.888/0.888/0.889 | 0.930 | 0.411 | 2.158 |
| threads | parallel-alloc-free-1 | mm | MATCH | tsc | 64.684/65.016/66.353 | 62.355/62.261/62.899 | 0.964 | 88.231 | 0.707 |
| threads | parallel-alloc-free-2 | mm | MATCH | tsc | 29390.068/19079.453/29663.796 | 60.734/61.019/62.638 | 0.002 | 82.406 | 0.737 |
| threads | parallel-alloc-free-4 | mm | MATCH | tsc | 44149.453/39871.286/44154.094 | 53.625/54.094/63.525 | 0.001 | 41.679 | 1.287 |
| threads | parallel-alloc-free-8 | mm | MATCH | tsc | 29225.641/27761.561/29399.200 | 107.073/106.010/115.622 | 0.004 | 20.858 | 5.134 |
| threads | parallel-alloc-free-96-4 | mm | MATCH | tsc | 21478.728/25872.812/30967.152 | 14.625/14.832/15.410 | 0.001 | 19.690 | 0.743 |
| threads | parallel-alloc-free-96-8 | mm | MATCH | tsc | 14375.780/12252.445/16497.302 | 9.529/13.721/18.084 | 0.001 | 12.131 | 0.786 |
| threads | producer-consumer | rtl+os | MATCH | tsc | 167.171/165.278/184.503 | 165.051/180.815/205.389 | 0.987 | 161.656 | 1.021 |
| threads | shared-read-4 | compiler+memory | MATCH | tsc | 0.999/0.996/1.004 | 0.831/0.830/0.833 | 0.832 | 1.028 | 0.809 |
| threads | thread-start-join-4 | os+rtl | MATCH | tsc | 160375.042/155363.057/171782.167 | 173637.042/175183.619/197932.500 | 1.083 | 169290.792 | 1.026 |
| workloads | binary-trees-depth-10 | codegen+mm | MATCH | cycles | 37.574/38.052/39.349 | 41.729/41.442/42.728 | 1.111 | 44.241 | 0.943 |
| workloads | convolution-256 | codegen+memory | MATCH | cycles | 3.569/3.573/3.587 | 2.784/2.784/2.799 | 0.780 | 2.804 | 0.993 |
| workloads | fannkuch-8 | codegen | MATCH | cycles | 102.396/102.627/103.152 | 98.332/98.414/98.793 | 0.960 | 98.885 | 0.994 |
| workloads | fft-1024 | codegen+math | MATCH | cycles | 11.305/11.376/11.574 | 13.750/13.792/13.994 | 1.216 | 13.751 | 1.000 |
| workloads | floyd-warshall-64 | codegen+memory | MATCH | cycles | 3.645/3.643/3.652 | 4.581/4.534/4.584 | 1.257 | 4.901 | 0.935 |
| workloads | jacobi-2d-128x4 | codegen+memory | MATCH | cycles | 3.144/3.144/3.153 | 3.631/3.636/3.657 | 1.155 | 4.490 | 0.809 |
| workloads | linked-list-insert-sort-512 | codegen+mm | MATCH | cycles | 456.858/457.541/459.414 | 494.709/494.909/497.101 | 1.083 | 479.618 | 1.031 |
| workloads | mandelbrot-128 | codegen | MATCH | cycles | 185.385/185.365/185.454 | 186.712/191.912/211.245 | 1.007 | 185.234 | 1.008 |
| workloads | nbody-5x100 | codegen+math | MATCH | cycles | 18.911/19.550/23.277 | 17.911/19.078/22.040 | 0.947 | 17.905 | 1.000 |
| workloads | numeric-state-machine | codegen | MATCH | cycles | 7.561/7.561/7.621 | 5.519/5.527/5.664 | 0.730 | 5.568 | 0.991 |
| workloads | spectral-norm-128 | codegen | MATCH | cycles | 5.745/5.762/5.805 | 4.640/4.628/4.640 | 0.808 | 4.583 | 1.012 |
| workloads | stream-add | memory | MATCH | cycles | 1.106/1.153/1.270 | 1.077/1.121/1.237 | 0.974 | 1.140 | 0.945 |
| workloads | stream-copy | memory | MATCH | cycles | 1.162/1.142/1.223 | 1.096/1.131/1.213 | 0.944 | 1.054 | 1.040 |
| workloads | stream-scale | memory | MATCH | cycles | 1.224/1.293/1.498 | 1.063/1.110/1.185 | 0.869 | 1.179 | 0.901 |
| workloads | stream-triad | memory | MATCH | cycles | 1.157/1.131/1.206 | 1.103/1.078/1.246 | 0.953 | 1.081 | 1.020 |
