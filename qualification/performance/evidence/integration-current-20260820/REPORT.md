# MoonCompiler Pulse result

Mode: `medium`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| abi | 24 | 0.715 | 11 | 10 | 3 | 0.924 |
| algorithms | 9 | 0.867 | 5 | 3 | 1 | 1.003 |
| calibration | 4 | 1.001 | 0 | 4 | 0 | 0.996 |
| codegen | 60 | 0.904 | 21 | 27 | 12 | 1.025 |
| dispatch | 15 | 0.905 | 7 | 5 | 3 | 1.016 |
| json | 9 | 0.865 | 6 | 0 | 3 | 1.008 |
| kernels | 10 | 0.855 | 7 | 3 | 0 | 0.974 |
| layout | 20 | 0.672 | 13 | 2 | 5 | 1.066 |
| local-pressure | 9 | 0.217 | 7 | 2 | 0 | 0.931 |
| loops | 20 | 0.938 | 7 | 11 | 2 | 0.960 |
| managed | 17 | 0.910 | 7 | 8 | 2 | 0.960 |
| mm | 15 | 1.004 | 5 | 4 | 6 | 0.591 |
| numeric | 21 | 0.770 | 9 | 11 | 1 | 1.039 |
| rtl | 77 | 0.699 | 48 | 17 | 12 | 0.983 |
| rtl-collections | 48 | 0.757 | 35 | 7 | 6 | 0.943 |
| threads | 17 | 0.128 | 9 | 5 | 3 | 1.268 |
| workloads | 15 | 0.950 | 8 | 2 | 5 | 0.977 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| abi | 24 | 0.715 | 11 | 10 | 3 |
| application | 10 | 0.855 | 7 | 3 | 0 |
| calibration | 4 | 1.001 | 0 | 4 | 0 |
| codegen | 145 | 0.799 | 62 | 59 | 24 |
| compiler | 23 | 0.955 | 10 | 9 | 4 |
| integrated | 1 | 0.889 | 1 | 0 | 0 |
| managed | 11 | 0.255 | 8 | 2 | 1 |
| math | 2 | 1.072 | 1 | 0 | 1 |
| memory | 40 | 0.850 | 19 | 14 | 7 |
| mm | 107 | 0.574 | 62 | 22 | 23 |
| os | 7 | 1.012 | 1 | 4 | 2 |
| rtl | 180 | 0.742 | 113 | 38 | 29 |
| text | 1 | 0.916 | 1 | 0 | 0 |

## Extreme results

### 15 fastest

- `threads/parallel-alloc-free-96-4`: `0.000x`
- `threads/parallel-alloc-free-4`: `0.001x`
- `threads/parallel-alloc-free-2`: `0.003x`
- `threads/parallel-alloc-free-96-8`: `0.003x`
- `threads/parallel-alloc-free-8`: `0.004x`
- `local-pressure/unused-mixed-300`: `0.007x`
- `local-pressure/unused-buffers-100`: `0.010x`
- `local-pressure/unused-strings-100`: `0.032x`
- `rtl/dictionary-capacity-1024`: `0.042x`
- `rtl/helper-endswith-nocase`: `0.057x`
- `rtl/helper-startswith-nocase`: `0.064x`
- `rtl/format-string`: `0.089x`
- `threads/cross-thread-free-4`: `0.105x`
- `rtl/datetime-ms-arith`: `0.176x`
- `codegen/currency-mul-div`: `0.205x`

### 15 slowest

- `codegen/for-downto`: `1.933x`
- `rtl/inttohex-int64`: `1.763x`
- `rtl-collections/list-string-insertrange-2048`: `1.757x`
- `layout/move-1024`: `1.707x`
- `codegen/try-finally-normal`: `1.586x`
- `dispatch/raise-catch`: `1.550x`
- `managed/managed-exception-cleanup`: `1.550x`
- `abi/dynamic-array-value`: `1.502x`
- `codegen/branch-predictable`: `1.478x`
- `rtl/dynamic-array-copy-512`: `1.476x`
- `mm/alloc-free-256`: `1.455x`
- `mm/alloc-free-1024`: `1.453x`
- `codegen/case-dense`: `1.451x`
- `managed/variant-numeric`: `1.426x`
- `layout/move-256`: `1.400x`

## All cases

| Program | Case | Layer | Oracle | Metric | delphi stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| abi | dynamic-array-const | abi+managed | MATCH | cycles | 4.856/4.891/5.012 | 4.793/4.840/4.975 | 0.987 | 5.586 | 0.858 |
| abi | dynamic-array-value | abi+managed | MATCH | cycles | 14.978/15.015/15.081 | 22.499/22.614/23.301 | 1.502 | 23.298 | 0.966 |
| abi | eight-args | abi | MATCH | cycles | 11.142/11.115/11.143 | 12.718/12.684/12.749 | 1.141 | 10.646 | 1.195 |
| abi | four-args | abi | MATCH | cycles | 6.309/6.309/6.313 | 6.325/6.335/6.391 | 1.003 | 6.276 | 1.008 |
| abi | function-pointer | abi | MATCH | cycles | 4.793/4.789/4.793 | 4.794/4.791/4.798 | 1.000 | 4.794 | 1.000 |
| abi | interface-method | abi+managed | MATCH | cycles | 6.412/6.407/6.412 | 5.628/5.632/5.657 | 0.878 | 5.607 | 1.004 |
| abi | method-pointer | abi | MATCH | cycles | 5.548/5.539/5.548 | 5.549/5.545/5.549 | 1.000 | 5.549 | 1.000 |
| abi | mixed-args | abi | MATCH | cycles | 12.935/12.934/12.935 | 8.295/8.295/8.296 | 0.641 | 8.343 | 0.994 |
| abi | no-args | abi | MATCH | cycles | 0.821/0.821/0.821 | 0.821/0.821/0.821 | 1.000 | 1.606 | 0.511 |
| abi | one-arg | abi | MATCH | cycles | 4.707/4.707/4.707 | 4.707/4.707/4.707 | 1.000 | 4.707 | 1.000 |
| abi | open-array-const | abi | MATCH | cycles | 4.076/4.070/4.077 | 4.831/4.824/4.832 | 1.185 | 5.586 | 0.865 |
| abi | record16-value | abi | MATCH | cycles | 14.053/14.051/14.069 | 2.951/2.956/2.967 | 0.210 | 5.520 | 0.535 |
| abi | record24-value | abi | MATCH | cycles | 15.758/15.759/15.764 | 3.509/3.509/3.509 | 0.223 | 3.516 | 0.998 |
| abi | record32-const | abi | MATCH | cycles | 4.818/4.829/4.843 | 4.994/4.996/5.011 | 1.036 | 4.857 | 1.028 |
| abi | record32-value | abi | MATCH | cycles | 20.700/20.708/20.728 | 7.518/7.513/7.522 | 0.363 | 8.712 | 0.863 |
| abi | record32-var | abi | MATCH | cycles | 4.844/4.840/4.844 | 5.014/5.003/5.015 | 1.035 | 5.030 | 0.997 |
| abi | record8-value | abi | MATCH | cycles | 6.865/6.870/6.901 | 2.729/2.727/2.729 | 0.398 | 2.714 | 1.006 |
| abi | return-record16 | abi | MATCH | cycles | 12.401/12.401/12.408 | 12.288/12.288/12.290 | 0.991 | 12.692 | 0.968 |
| abi | return-record24 | abi | MATCH | cycles | 18.005/18.005/18.005 | 13.603/13.573/13.603 | 0.755 | 18.069 | 0.753 |
| abi | return-record32 | abi | MATCH | cycles | 19.121/19.121/19.121 | 13.976/13.977/13.979 | 0.731 | 13.822 | 1.011 |
| abi | return-record8 | abi | MATCH | cycles | 11.083/11.085/11.092 | 5.492/5.492/5.492 | 0.496 | 5.492 | 1.000 |
| abi | string-const | abi+managed | MATCH | cycles | 4.818/4.822/4.843 | 3.192/3.197/3.209 | 0.662 | 3.268 | 0.977 |
| abi | string-value | abi+managed | MATCH | cycles | 14.912/14.922/14.970 | 3.209/3.207/3.212 | 0.215 | 3.209 | 1.000 |
| abi | virtual-method | abi | MATCH | cycles | 5.548/5.548/5.549 | 5.586/5.586/5.587 | 1.007 | 5.549 | 1.007 |
| algorithms | binary-search-256 | codegen | MATCH | cycles | 143.653/143.513/143.893 | 143.330/143.493/143.938 | 0.998 | 143.358 | 1.000 |
| algorithms | chacha20-block | codegen | MATCH | cycles | 18.551/18.534/18.613 | 7.791/7.787/7.791 | 0.420 | 7.785 | 1.001 |
| algorithms | crc32-bitwise-4k | codegen | MATCH | cycles | 9.549/9.574/9.635 | 9.011/9.037/9.065 | 0.944 | 8.987 | 1.003 |
| algorithms | generic-list-512 | rtl | MATCH | cycles | 7.362/7.363/7.444 | 7.344/7.331/7.375 | 0.998 | 7.443 | 0.987 |
| algorithms | lz-compress-4k | codegen+memory | MATCH | cycles | 140.088/140.097/140.861 | 118.982/119.012/119.631 | 0.849 | 119.318 | 0.997 |
| algorithms | lz-roundtrip-4k | codegen+memory | MATCH | cycles | 70.593/70.618/70.678 | 60.140/60.102/60.187 | 0.852 | 60.280 | 0.998 |
| algorithms | open-hash-4096 | codegen+memory | MATCH | cycles | 6.960/6.966/7.072 | 7.396/7.399/7.538 | 1.063 | 7.348 | 1.006 |
| algorithms | quicksort-4096 | codegen+rtl | MATCH | cycles | 118.147/118.367/119.562 | 119.608/119.264/119.817 | 1.012 | 113.033 | 1.058 |
| algorithms | sha256-4k | codegen | MATCH | cycles | 17.309/17.315/17.439 | 15.642/15.617/15.684 | 0.904 | 15.990 | 0.978 |
| calibration | asm-dependent-add | calibration | MATCH | cycles | 0.841/0.841/0.841 | 0.841/0.841/0.842 | 1.000 | 0.841 | 1.000 |
| calibration | asm-memory-read-64m | calibration | MATCH | cycles | 0.139/0.139/0.144 | 0.140/0.141/0.143 | 1.010 | 0.141 | 0.990 |
| calibration | asm-memory-write-64m | calibration | MATCH | cycles | 0.186/0.189/0.203 | 0.185/0.186/0.190 | 0.996 | 0.186 | 0.994 |
| calibration | asm-mixed-integer | calibration | MATCH | cycles | 1.275/1.305/1.366 | 1.275/1.301/1.367 | 1.000 | 1.275 | 1.000 |
| codegen | abs-int | codegen | MATCH | cycles | 1.774/1.776/1.783 | 1.586/1.588/1.595 | 0.894 | 1.553 | 1.021 |
| codegen | branch-predictable | codegen | MATCH | cycles | 1.642/1.670/1.723 | 2.427/2.431/2.440 | 1.478 | 1.650 | 1.471 |
| codegen | branch-random | codegen | MATCH | cycles | 2.737/2.744/2.770 | 1.923/1.942/2.045 | 0.703 | 2.027 | 0.949 |
| codegen | call-eight-args | codegen | MATCH | cycles | 12.674/12.749/13.072 | 7.845/7.845/7.846 | 0.619 | 7.834 | 1.001 |
| codegen | call-indirect | codegen | MATCH | cycles | 4.000/4.003/4.021 | 4.001/3.999/4.022 | 1.000 | 3.993 | 1.002 |
| codegen | call-inline | codegen | MATCH | cycles | 2.354/2.353/2.354 | 2.354/2.354/2.354 | 1.000 | 2.354 | 1.000 |
| codegen | call-interface | codegen+rtl | MATCH | cycles | 4.843/4.844/4.869 | 4.844/4.845/4.871 | 1.000 | 6.379 | 0.759 |
| codegen | call-unit-direct | codegen | MATCH | cycles | 2.354/2.354/2.356 | 2.354/2.354/2.354 | 1.000 | 2.354 | 1.000 |
| codegen | call-virtual | codegen | MATCH | cycles | 5.586/5.598/5.615 | 5.586/5.599/5.615 | 1.000 | 4.819 | 1.159 |
| codegen | case-dense | codegen | MATCH | cycles | 3.809/3.823/3.907 | 5.527/5.521/5.539 | 1.451 | 5.446 | 1.015 |
| codegen | case-sparse | codegen | MATCH | cycles | 4.289/4.290/4.290 | 4.187/4.187/4.191 | 0.976 | 4.180 | 1.002 |
| codegen | concrete-reverse-int | codegen | MATCH | cycles | 2.842/2.876/2.964 | 3.276/3.289/3.376 | 1.153 | 3.286 | 0.997 |
| codegen | concrete-reverse-rec | codegen | MATCH | cycles | 14.132/14.262/14.475 | 5.238/5.232/5.248 | 0.371 | 5.136 | 1.020 |
| codegen | cse-expression | codegen | MATCH | cycles | 4.896/4.885/4.897 | 4.270/4.281/4.296 | 0.872 | 4.004 | 1.066 |
| codegen | currency-mul-div | codegen+rtl | MATCH | cycles | 200.600/200.591/200.802 | 41.181/41.198/41.230 | 0.205 | 41.131 | 1.001 |
| codegen | dead-store-chain | codegen | MATCH | cycles | 5.033/5.067/5.285 | 3.639/3.654/3.725 | 0.723 | 3.225 | 1.128 |
| codegen | dep-add | codegen | MATCH | cycles | 3.138/3.138/3.138 | 3.138/3.138/3.138 | 1.000 | 3.138 | 1.000 |
| codegen | double-mixed | codegen | MATCH | cycles | 4.237/4.237/4.237 | 4.237/4.237/4.238 | 1.000 | 4.237 | 1.000 |
| codegen | enum-set-membership | codegen | MATCH | cycles | 4.164/4.170/4.186 | 3.937/3.987/4.083 | 0.945 | 4.174 | 0.943 |
| codegen | fillchar-4k | rtl | MATCH | cycles | 0.037/0.037/0.037 | 0.049/0.049/0.049 | 1.326 | 0.049 | 1.000 |
| codegen | for-byte-0-255 | codegen | MATCH | cycles | 1.621/1.622/1.629 | 0.843/0.843/0.843 | 0.520 | 0.843 | 1.000 |
| codegen | for-downto | codegen | MATCH | cycles | 0.830/0.835/0.852 | 1.605/1.606/1.612 | 1.933 | 0.830 | 1.933 |
| codegen | for-length-array | codegen | MATCH | cycles | 1.615/1.615/1.622 | 1.595/1.604/1.640 | 0.988 | 0.827 | 1.929 |
| codegen | for-length-string | codegen | MATCH | cycles | 1.533/1.530/1.549 | 0.881/0.881/0.881 | 0.575 | 1.595 | 0.552 |
| codegen | for-runtime-0-0 | codegen | MATCH | cycles | 2.366/2.371/2.380 | 1.577/1.580/1.586 | 0.667 | 1.585 | 0.995 |
| codegen | for-runtime-0-255 | codegen | MATCH | cycles | 1.639/1.651/1.690 | 2.216/2.227/2.259 | 1.352 | 1.630 | 1.360 |
| codegen | generic-reverse-int | codegen | MATCH | cycles | 2.744/2.771/2.811 | 3.250/3.259/3.270 | 1.184 | 3.278 | 0.991 |
| codegen | generic-reverse-rec | codegen | MATCH | cycles | 14.120/14.120/14.121 | 5.283/5.240/5.291 | 0.374 | 5.071 | 1.042 |
| codegen | ilp-four-lanes | codegen | MATCH | cycles | 0.789/0.790/0.793 | 0.789/0.789/0.789 | 1.000 | 0.789 | 1.000 |
| codegen | int32-div-const | codegen | MATCH | cycles | 2.384/2.386/2.396 | 1.882/1.878/1.882 | 0.790 | 1.830 | 1.029 |
| codegen | int32-mixed | codegen | MATCH | cycles | 4.707/4.726/4.797 | 4.707/4.717/4.769 | 1.000 | 4.707 | 1.000 |
| codegen | int64-div-const | codegen | MATCH | cycles | 2.176/2.176/2.177 | 2.210/2.199/2.212 | 1.015 | 2.129 | 1.038 |
| codegen | int64-mod-latency | codegen | MATCH | cycles | 11.767/11.767/11.768 | 11.769/11.768/11.769 | 1.000 | 11.769 | 1.000 |
| codegen | int8-int16-promotion | codegen | MATCH | cycles | 5.753/5.754/5.754 | 5.504/5.494/5.504 | 0.957 | 5.504 | 1.000 |
| codegen | loop-early-exit | codegen | MATCH | cycles | 1.723/1.724/1.732 | 1.725/1.728/1.736 | 1.001 | 1.730 | 0.997 |
| codegen | math-transcendentals | rtl | MATCH | cycles | 11.244/11.233/11.268 | 11.198/11.194/11.201 | 0.996 | 11.172 | 1.002 |
| codegen | matrix-double-16 | codegen | MATCH | cycles | 4.191/4.180/4.234 | 3.782/3.783/3.785 | 0.902 | 3.846 | 0.983 |
| codegen | minmax-double | codegen+rtl | MATCH | cycles | 5.754/5.752/5.822 | 2.135/2.130/2.145 | 0.371 | 2.155 | 0.991 |
| codegen | minmax-double-special | codegen+rtl | MATCH | cycles | 4.082/4.082/4.082 | 3.083/3.083/3.085 | 0.755 | 3.275 | 0.941 |
| codegen | minmax-int | codegen+rtl | MATCH | cycles | 1.771/1.785/1.844 | 1.598/1.608/1.670 | 0.902 | 1.592 | 1.004 |
| codegen | move-4k | rtl | MATCH | cycles | 0.031/0.031/0.032 | 0.033/0.034/0.035 | 1.062 | 0.033 | 1.000 |
| codegen | mul-lea | codegen | MATCH | cycles | 0.797/0.798/0.802 | 0.842/0.845/0.870 | 1.056 | 0.832 | 1.012 |
| codegen | packed-odd-sizes | codegen | MATCH | cycles | 0.808/0.807/0.810 | 0.808/0.808/0.811 | 1.001 | 0.805 | 1.004 |
| codegen | pointer-alias-update | codegen+memory | MATCH | cycles | 1.662/1.662/1.670 | 1.674/1.674/1.674 | 1.007 | 1.659 | 1.009 |
| codegen | pointer-chase | codegen+memory | MATCH | cycles | 9.631/9.635/9.658 | 9.678/10.011/12.019 | 1.005 | 9.626 | 1.005 |
| codegen | record-aligned | codegen | MATCH | cycles | 3.221/3.221/3.222 | 3.495/3.495/3.498 | 1.085 | 3.035 | 1.151 |
| codegen | record-packed | codegen | MATCH | cycles | 4.115/4.115/4.116 | 4.542/4.543/4.554 | 1.104 | 4.550 | 0.998 |
| codegen | recursion-tree-8 | codegen | MATCH | cycles | 4.509/4.517/4.566 | 4.534/4.534/4.534 | 1.005 | 5.677 | 0.799 |
| codegen | scan-dram | codegen+memory | MATCH | cycles | 1.109/1.123/1.148 | 1.117/1.132/1.172 | 1.007 | 1.111 | 1.005 |
| codegen | scan-l1 | codegen+memory | MATCH | cycles | 0.792/0.803/0.836 | 0.792/0.799/0.833 | 1.000 | 0.799 | 0.991 |
| codegen | scan-l2 | codegen+memory | MATCH | cycles | 0.794/0.796/0.812 | 0.794/0.793/0.794 | 1.000 | 0.794 | 1.000 |
| codegen | scan-llc | codegen+memory | MATCH | cycles | 0.795/0.794/0.796 | 0.796/0.796/0.796 | 1.001 | 0.796 | 1.000 |
| codegen | scan-random | codegen+memory | MATCH | cycles | 2.667/2.652/2.799 | 2.174/2.221/2.327 | 0.815 | 2.185 | 0.995 |
| codegen | scan-strided | codegen+memory | MATCH | cycles | 2.124/2.155/2.297 | 2.122/2.145/2.262 | 0.999 | 2.087 | 1.017 |
| codegen | single-mixed | codegen | MATCH | cycles | 6.280/6.280/6.281 | 6.274/6.273/6.274 | 0.999 | 6.283 | 0.998 |
| codegen | try-finally-normal | compiler+rtl | MATCH | cycles | 3.546/3.545/3.546 | 5.624/5.626/5.630 | 1.586 | 5.413 | 1.039 |
| codegen | uint32-div-const | codegen | MATCH | cycles | 1.762/1.771/1.815 | 1.538/1.543/1.573 | 0.873 | 1.531 | 1.005 |
| codegen | uint64-div-constant | codegen | MATCH | cycles | 2.423/2.425/2.436 | 2.106/2.104/2.115 | 0.869 | 1.967 | 1.071 |
| codegen | uint64-div-runtime | codegen | MATCH | cycles | 7.038/7.038/7.038 | 7.040/7.039/7.040 | 1.000 | 7.040 | 1.000 |
| codegen | uint64-mixed | codegen | MATCH | cycles | 6.275/6.276/6.280 | 4.707/4.707/4.707 | 0.750 | 4.707 | 1.000 |
| dispatch | class-name-rtti | rtl | MATCH | cycles | 35.653/35.975/37.329 | 13.030/13.001/13.030 | 0.365 | 16.095 | 0.810 |
| dispatch | function-pointer | codegen | MATCH | cycles | 4.756/4.756/4.756 | 4.756/4.756/4.756 | 1.000 | 4.793 | 0.992 |
| dispatch | generic-integer | codegen | MATCH | cycles | 5.491/5.491/5.492 | 4.707/4.708/4.712 | 0.857 | 4.707 | 1.000 |
| dispatch | generic-record | codegen | MATCH | cycles | 5.520/5.520/5.520 | 5.151/5.151/5.152 | 0.933 | 4.897 | 1.052 |
| dispatch | interface-monomorphic | compiler+rtl | MATCH | cycles | 7.208/7.203/7.209 | 5.637/5.637/5.638 | 0.782 | 5.657 | 0.996 |
| dispatch | interface-polymorphic | compiler+rtl | MATCH | cycles | 26.719/26.695/26.719 | 26.931/27.030/27.237 | 1.008 | 28.208 | 0.955 |
| dispatch | list-enumerator | rtl+mm | MATCH | cycles | 9.024/8.935/9.069 | 5.483/5.523/5.754 | 0.608 | 5.537 | 0.990 |
| dispatch | list-index | rtl+mm | MATCH | cycles | 2.419/2.419/2.420 | 3.214/3.214/3.214 | 1.328 | 2.423 | 1.326 |
| dispatch | managed-object-create-free | rtl+mm | MATCH | cycles | 462.810/464.536/471.369 | 353.263/353.586/357.338 | 0.763 | 304.401 | 1.161 |
| dispatch | object-create-free | rtl+mm | MATCH | cycles | 116.547/116.808/117.163 | 109.586/110.874/112.509 | 0.940 | 112.573 | 0.973 |
| dispatch | raise-catch | compiler+rtl+mm | MATCH | cycles | 3660.871/3664.389/3679.565 | 5672.856/5675.641/5710.106 | 1.550 | 5646.223 | 1.005 |
| dispatch | static-method | codegen | MATCH | cycles | 5.520/5.528/5.549 | 5.492/5.492/5.492 | 0.995 | 5.492 | 1.000 |
| dispatch | try-except-no-raise | compiler+rtl | MATCH | cycles | 4.731/4.735/4.756 | 4.707/4.707/4.707 | 0.995 | 4.707 | 1.000 |
| dispatch | virtual-monomorphic | codegen | MATCH | cycles | 5.615/5.616/5.626 | 5.579/5.578/5.579 | 0.994 | 5.578 | 1.000 |
| dispatch | virtual-polymorphic | codegen | MATCH | cycles | 25.101/25.093/25.147 | 27.423/27.481/28.079 | 1.093 | 26.038 | 1.053 |
| json | generate-64 | rtl | MATCH | cycles | 11753.281/11680.335/11867.083 | 5399.167/5404.963/5564.427 | 0.459 | 5301.693 | 1.018 |
| json | parse-large-custom-double | compiler+rtl | MATCH | cycles | 2337.264/2359.229/2454.553 | 2040.807/2050.956/2128.687 | 0.873 | 2187.830 | 0.933 |
| json | parse-medium-custom-double | compiler+rtl | MATCH | cycles | 2456.146/2459.609/2466.536 | 2133.882/2128.329/2173.496 | 0.869 | 2150.303 | 0.992 |
| json | parse-medium-strtofloat | rtl | MATCH | cycles | 5523.359/5634.475/5826.172 | 4584.492/4709.286/4889.531 | 0.830 | 4793.789 | 0.956 |
| json | parse-small-custom-double | compiler+rtl | MATCH | cycles | 2363.323/2367.536/2403.500 | 2119.244/2126.016/2133.542 | 0.897 | 2068.401 | 1.025 |
| json | pipeline-parse-vwap-format | integrated | MATCH | cycles | 2474.701/2476.150/2483.359 | 2199.194/2181.713/2202.070 | 0.889 | 2161.992 | 1.017 |
| json | scan-large-4096 | codegen | MATCH | cycles | 4.413/4.410/4.431 | 4.666/4.671/4.684 | 1.057 | 4.519 | 1.033 |
| json | scan-medium-256 | codegen | MATCH | cycles | 4.409/4.407/4.423 | 4.683/4.680/4.685 | 1.062 | 4.521 | 1.036 |
| json | scan-small-16 | codegen | MATCH | cycles | 4.442/4.432/4.465 | 4.669/4.663/4.669 | 1.051 | 4.362 | 1.070 |
| kernels | base64-encode-4096 | application+text | MATCH | cycles | 2.964/2.969/2.979 | 2.716/2.720/2.729 | 0.916 | 2.706 | 1.004 |
| kernels | correlation-128x32 | application | MATCH | cycles | 7.718/7.720/7.723 | 7.693/7.693/7.694 | 0.997 | 7.689 | 1.001 |
| kernels | dijkstra-64 | application | MATCH | cycles | 13.063/13.089/13.130 | 11.550/11.537/11.551 | 0.884 | 11.875 | 0.973 |
| kernels | huffman-lengths-256 | application | MATCH | cycles | 4.697/4.698/4.702 | 3.890/3.899/3.912 | 0.828 | 4.740 | 0.821 |
| kernels | lu-decomposition-32 | application | MATCH | cycles | 1.661/1.655/1.662 | 1.647/1.647/1.650 | 0.992 | 1.699 | 0.969 |
| kernels | monte-carlo-4096 | application | MATCH | cycles | 14.766/14.765/14.769 | 6.528/6.529/6.535 | 0.442 | 6.276 | 1.040 |
| kernels | neural-dense-32x32 | application | MATCH | cycles | 1.683/1.683/1.690 | 1.597/1.622/1.772 | 0.949 | 1.637 | 0.976 |
| kernels | pixel-transform-4096 | application | MATCH | cycles | 4.708/4.708/4.709 | 4.933/4.933/4.933 | 1.048 | 4.924 | 1.002 |
| kernels | prime-sieve-16384 | application | MATCH | cycles | 5.289/5.293/5.324 | 4.006/3.994/4.006 | 0.757 | 4.096 | 0.978 |
| kernels | sparse-matvec-512x8 | application | MATCH | cycles | 1.816/1.816/1.816 | 1.717/1.719/1.726 | 0.946 | 1.719 | 0.999 |
| layout | aligned-read | codegen+memory | MATCH | cycles | 1.904/1.904/1.904 | 1.639/1.639/1.639 | 0.861 | 0.844 | 1.942 |
| layout | aos-all-fields | codegen+memory | MATCH | cycles | 4.810/4.815/4.840 | 4.708/4.715/4.733 | 0.979 | 4.708 | 1.000 |
| layout | aos-one-field | codegen+memory | MATCH | cycles | 1.604/1.610/1.618 | 0.993/1.003/1.026 | 0.619 | 1.027 | 0.967 |
| layout | dynamic-array | codegen+memory | MATCH | cycles | 1.595/1.592/1.596 | 0.792/0.793/0.796 | 0.497 | 0.793 | 1.000 |
| layout | fill-1024 | rtl | MATCH | cycles | 0.115/0.115/0.115 | 0.049/0.049/0.049 | 0.429 | 0.049 | 1.005 |
| layout | fill-16 | rtl | MATCH | cycles | 0.396/0.396/0.396 | 0.099/0.099/0.100 | 0.250 | 0.099 | 1.000 |
| layout | fill-256 | rtl | MATCH | cycles | 0.068/0.068/0.068 | 0.050/0.050/0.050 | 0.735 | 0.050 | 1.005 |
| layout | fill-64 | rtl | MATCH | cycles | 0.137/0.137/0.137 | 0.050/0.050/0.050 | 0.362 | 0.050 | 1.000 |
| layout | indexed-walk | codegen+memory | MATCH | cycles | 0.790/0.790/0.790 | 0.853/0.851/0.854 | 1.080 | 0.856 | 0.997 |
| layout | move-1024 | rtl | MATCH | cycles | 0.033/0.033/0.033 | 0.057/0.057/0.057 | 1.707 | 0.051 | 1.123 |
| layout | move-16 | rtl | MATCH | cycles | 0.299/0.299/0.299 | 0.099/0.099/0.100 | 0.332 | 0.067 | 1.484 |
| layout | move-256 | rtl | MATCH | cycles | 0.047/0.047/0.048 | 0.066/0.066/0.066 | 1.400 | 0.057 | 1.167 |
| layout | move-64 | rtl | MATCH | cycles | 0.100/0.100/0.100 | 0.066/0.066/0.066 | 0.663 | 0.066 | 1.000 |
| layout | packed-record | codegen+memory | MATCH | cycles | 4.581/4.581/4.586 | 3.155/3.157/3.171 | 0.689 | 3.155 | 1.000 |
| layout | pointer-walk | codegen+memory | MATCH | cycles | 0.790/0.790/0.790 | 0.833/0.834/0.837 | 1.054 | 0.853 | 0.976 |
| layout | soa-all-fields | codegen+memory | MATCH | cycles | 4.732/4.732/4.733 | 4.708/4.712/4.732 | 0.995 | 4.708 | 1.000 |
| layout | soa-one-field | codegen+memory | MATCH | cycles | 1.587/1.587/1.587 | 0.881/0.883/0.885 | 0.555 | 0.880 | 1.001 |
| layout | static-array | codegen+memory | MATCH | cycles | 0.790/0.791/0.795 | 0.855/0.854/0.856 | 1.082 | 0.851 | 1.005 |
| layout | unaligned-read | codegen+memory | MATCH | cycles | 1.920/1.920/1.920 | 0.847/0.847/0.848 | 0.441 | 0.847 | 1.000 |
| layout | variant-record | codegen+memory | MATCH | cycles | 6.079/6.070/6.080 | 2.644/2.757/2.908 | 0.435 | 2.644 | 1.000 |
| local-pressure | empty | codegen | MATCH | cycles | 4.707/4.707/4.707 | 3.923/3.929/3.963 | 0.833 | 4.707 | 0.833 |
| local-pressure | unused-buffers-100 | codegen+managed | MATCH | cycles | 376.493/376.823/378.436 | 3.943/3.952/3.984 | 0.010 | 5.492 | 0.718 |
| local-pressure | unused-mixed-300 | codegen+managed | MATCH | cycles | 714.738/715.552/718.729 | 4.707/4.707/4.707 | 0.007 | 4.707 | 1.000 |
| local-pressure | unused-plain-100 | codegen | MATCH | cycles | 4.707/4.710/4.731 | 3.923/3.929/3.943 | 0.833 | 4.707 | 0.833 |
| local-pressure | unused-strings-100 | codegen+managed | MATCH | cycles | 148.262/148.594/149.031 | 4.707/4.711/4.732 | 0.032 | 4.707 | 1.000 |
| local-pressure | used-buffers-100 | codegen+managed | MATCH | cycles | 2183.731/2197.213/2256.415 | 1740.608/1739.383/1740.748 | 0.797 | 1721.244 | 1.011 |
| local-pressure | used-mixed-300 | codegen+managed | MATCH | cycles | 3746.446/3763.832/3805.017 | 3479.285/3477.158/3492.188 | 0.929 | 3367.441 | 1.033 |
| local-pressure | used-plain-100 | codegen | MATCH | cycles | 115.125/115.125/115.127 | 111.996/111.907/111.998 | 0.973 | 111.988 | 1.000 |
| local-pressure | used-strings-100 | codegen+managed | MATCH | cycles | 1408.623/1421.229/1478.336 | 1397.969/1396.861/1405.860 | 0.992 | 1386.018 | 1.009 |
| loops | aliased-update | codegen | MATCH | cycles | 3.318/3.318/3.318 | 3.138/3.141/3.156 | 0.946 | 3.144 | 0.998 |
| loops | break-continue | codegen | MATCH | cycles | 1.966/1.966/1.966 | 1.670/1.667/1.670 | 0.850 | 1.673 | 0.998 |
| loops | for-down | codegen | MATCH | cycles | 1.745/1.745/1.746 | 1.647/1.647/1.647 | 0.944 | 1.641 | 1.003 |
| loops | for-up | codegen | MATCH | cycles | 1.654/1.660/1.707 | 1.644/1.644/1.644 | 0.994 | 1.556 | 1.057 |
| loops | histogram-random | codegen+memory | MATCH | cycles | 2.769/2.783/2.833 | 1.674/1.732/1.873 | 0.605 | 1.672 | 1.001 |
| loops | invariant-expression | codegen | MATCH | cycles | 2.105/2.103/2.106 | 1.822/1.819/1.822 | 0.865 | 1.650 | 1.104 |
| loops | loop-try-finally | compiler+rtl | MATCH | cycles | 4.587/4.582/4.587 | 4.950/4.944/4.957 | 1.079 | 5.233 | 0.946 |
| loops | loop-with-call | codegen | MATCH | cycles | 5.491/5.508/5.549 | 5.492/5.492/5.492 | 1.000 | 5.492 | 1.000 |
| loops | manual-copy-8192 | codegen+memory | MATCH | cycles | 0.809/0.811/0.816 | 0.799/0.800/0.804 | 0.987 | 1.587 | 0.503 |
| loops | nested-column-major | codegen+memory | MATCH | cycles | 1.636/1.636/1.636 | 1.601/1.600/1.610 | 0.979 | 1.593 | 1.005 |
| loops | nested-row-major | codegen+memory | MATCH | cycles | 1.601/1.601/1.601 | 1.626/1.626/1.626 | 1.016 | 1.602 | 1.015 |
| loops | nonaliased-update | codegen | MATCH | cycles | 3.298/3.295/3.310 | 3.531/3.536/3.549 | 1.071 | 3.311 | 1.066 |
| loops | prefix-dependency | codegen+memory | MATCH | cycles | 1.673/1.673/1.673 | 1.650/1.646/1.650 | 0.986 | 1.658 | 0.995 |
| loops | reduction-four-lanes | codegen | MATCH | cycles | 0.926/0.926/0.926 | 0.800/0.799/0.800 | 0.864 | 0.807 | 0.991 |
| loops | reduction-sum | codegen | MATCH | cycles | 2.354/2.356/2.366 | 2.354/2.359/2.366 | 1.000 | 2.354 | 1.000 |
| loops | repeat-runtime | codegen | MATCH | cycles | 1.675/1.675/1.676 | 1.727/1.728/1.734 | 1.031 | 1.682 | 1.026 |
| loops | strength-multiply-index | codegen | MATCH | cycles | 1.665/1.661/1.665 | 1.638/1.637/1.638 | 0.984 | 1.641 | 0.998 |
| loops | vector-add-8192 | codegen+memory | MATCH | cycles | 1.612/1.616/1.621 | 1.167/1.171/1.191 | 0.724 | 1.612 | 0.724 |
| loops | vector-dot-8192 | codegen+memory | MATCH | cycles | 2.366/2.368/2.378 | 2.354/2.356/2.366 | 0.995 | 2.366 | 0.995 |
| loops | while-runtime | codegen | MATCH | cycles | 1.674/1.674/1.674 | 1.679/1.677/1.680 | 1.003 | 1.682 | 0.998 |
| managed | closure-create-invoke | compiler+rtl | MATCH | cycles | 226.190/220.877/230.566 | 145.069/144.764/145.861 | 0.641 | 155.554 | 0.933 |
| managed | dynamic-array-assign | rtl | MATCH | cycles | 15.479/15.456/15.489 | 15.354/15.020/15.420 | 0.992 | 14.164 | 1.084 |
| managed | dynamic-array-deep-copy | rtl | MATCH | cycles | 57.841/59.740/63.937 | 54.587/55.511/58.324 | 0.944 | 52.316 | 1.043 |
| managed | ignored-interface-result | compiler+rtl | MATCH | cycles | 25.694/25.233/25.781 | 24.443/24.407/24.479 | 0.951 | 22.110 | 1.105 |
| managed | ignored-string-result | compiler+rtl | MATCH | cycles | 19.021/19.069/19.176 | 14.091/13.956/14.124 | 0.741 | 14.771 | 0.954 |
| managed | interface-copy-call | compiler+rtl | MATCH | cycles | 20.342/20.423/21.062 | 20.621/20.588/20.641 | 1.014 | 55.904 | 0.369 |
| managed | managed-early-exit | compiler+rtl | MATCH | cycles | 72.021/72.630/75.025 | 65.110/65.062/66.862 | 0.904 | 68.388 | 0.952 |
| managed | managed-exception-cleanup | compiler+rtl | MATCH | cycles | 557.524/556.515/560.749 | 863.912/861.120/865.453 | 1.550 | 829.821 | 1.041 |
| managed | managed-record-return | compiler+rtl | MATCH | cycles | 223.183/223.463/224.586 | 125.081/127.071/133.358 | 0.560 | 120.031 | 1.042 |
| managed | out-string-forwarding | compiler+rtl | MATCH | cycles | 24.651/24.606/24.731 | 18.743/18.710/18.795 | 0.760 | 17.959 | 1.044 |
| managed | rawbytestring-assign | rtl | MATCH | cycles | 12.626/12.704/13.260 | 12.743/12.896/13.451 | 1.009 | 12.734 | 1.001 |
| managed | rawbytestring-assign-mt | rtl | MATCH | cycles | 13.251/13.292/13.413 | 13.449/13.460/13.513 | 1.015 | 13.438 | 1.001 |
| managed | unicode-assign | rtl | MATCH | cycles | 12.562/12.580/12.704 | 12.677/12.675/12.752 | 1.009 | 12.905 | 0.982 |
| managed | unicode-assign-mt | rtl | MATCH | cycles | 13.250/13.249/13.293 | 13.457/13.457/13.465 | 1.016 | 13.440 | 1.001 |
| managed | unicode-concat | rtl | MATCH | cycles | 87.711/88.483/91.155 | 45.527/45.504/45.533 | 0.519 | 50.845 | 0.895 |
| managed | unicode-return-ppu | compiler+rtl | MATCH | cycles | 13.256/13.282/13.399 | 13.433/13.439/13.458 | 1.013 | 13.446 | 0.999 |
| managed | variant-numeric | rtl | MATCH | cycles | 137.514/136.179/137.525 | 196.067/195.406/196.313 | 1.426 | 153.425 | 1.278 |
| mm | alloc-free-100500 | mm | MATCH | cycles | 52.092/52.155/52.388 | 40.793/40.896/41.277 | 0.783 | 67.816 | 0.602 |
| mm | alloc-free-1024 | mm | MATCH | cycles | 45.553/46.849/54.551 | 66.204/66.320/66.919 | 1.453 | 83.146 | 0.796 |
| mm | alloc-free-16 | mm | MATCH | cycles | 25.226/25.118/25.309 | 27.067/27.032/27.902 | 1.073 | 27.370 | 0.989 |
| mm | alloc-free-16k | mm | MATCH | cycles | 52.290/52.287/53.163 | 40.980/40.865/40.982 | 0.784 | 82.940 | 0.494 |
| mm | alloc-free-17408 | mm | MATCH | cycles | 52.093/52.375/53.408 | 40.954/40.915/41.138 | 0.786 | 83.009 | 0.493 |
| mm | alloc-free-17409 | mm | MATCH | cycles | 53.402/53.633/56.773 | 41.013/41.084/42.032 | 0.768 | 82.823 | 0.495 |
| mm | alloc-free-1m | mm | MATCH | cycles | 30322.417/28344.234/30369.600 | 31693.056/29677.594/31772.222 | 1.045 | 67786.988 | 0.468 |
| mm | alloc-free-256 | mm | MATCH | cycles | 45.271/45.645/46.573 | 65.878/66.589/67.728 | 1.455 | 40.619 | 1.622 |
| mm | alloc-free-2m | mm | MATCH | cycles | 36829.355/36927.061/37134.098 | 36965.198/37410.665/38615.085 | 1.004 | 73910.000 | 0.500 |
| mm | alloc-free-64 | mm | MATCH | cycles | 25.228/24.922/25.229 | 29.436/28.990/29.438 | 1.167 | 42.538 | 0.692 |
| mm | fragmented-mixed | mm | MATCH | cycles | 1262.090/1263.150/1269.141 | 1320.352/1286.145/1322.578 | 1.046 | 1916.885 | 0.689 |
| mm | realloc-grow | mm | MATCH | cycles | 55.653/56.185/56.826 | 60.501/62.194/66.241 | 1.087 | 118.716 | 0.510 |
| mm | realloc-shrink | mm | MATCH | cycles | 30.280/30.449/30.925 | 30.388/30.538/31.064 | 1.004 | 127.216 | 0.239 |
| mm | ring-mixed-16-to-1m | mm | MATCH | cycles | 2115.605/2080.484/2126.738 | 1770.210/1773.324/1793.867 | 0.837 | 4770.410 | 0.371 |
| mm | ring-same-class-96 | mm | MATCH | cycles | 12.606/12.766/13.058 | 13.609/13.708/14.047 | 1.080 | 16.778 | 0.811 |
| numeric | bit-boolean | codegen | MATCH | cycles | 9.217/9.219/9.225 | 6.277/6.276/6.277 | 0.681 | 6.277 | 1.000 |
| numeric | double-arithmetic | codegen | MATCH | cycles | 5.489/5.488/5.489 | 5.480/5.480/5.481 | 0.998 | 5.459 | 1.004 |
| numeric | int-double-convert | codegen+rtl | MATCH | cycles | 8.032/8.038/8.074 | 3.348/3.345/3.365 | 0.417 | 3.350 | 0.999 |
| numeric | int32-add-mul | codegen | MATCH | cycles | 3.616/3.625/3.708 | 3.923/3.936/4.011 | 1.085 | 3.922 | 1.000 |
| numeric | int32-div-runtime | codegen | MATCH | cycles | 9.414/9.431/9.531 | 9.414/9.432/9.535 | 1.000 | 9.414 | 1.000 |
| numeric | int64-add-mul | codegen | MATCH | cycles | 3.963/3.963/3.964 | 3.963/3.961/3.968 | 1.000 | 3.943 | 1.005 |
| numeric | int64-div-runtime | codegen | MATCH | cycles | 14.040/14.040/14.040 | 14.042/14.043/14.043 | 1.000 | 14.042 | 1.000 |
| numeric | min-max-mixed | codegen | MATCH | cycles | 3.294/3.280/3.295 | 2.113/2.124/2.136 | 0.641 | 2.180 | 0.969 |
| numeric | overflow-checked | codegen | MATCH | cycles | 3.242/3.242/3.242 | 3.242/3.247/3.259 | 1.000 | 2.489 | 1.303 |
| numeric | overflow-unchecked | codegen | MATCH | cycles | 2.353/2.353/2.353 | 2.353/2.354/2.354 | 1.000 | 2.366 | 0.995 |
| numeric | range-checked-index | codegen | MATCH | cycles | 2.477/2.478/2.483 | 2.489/2.486/2.490 | 1.005 | 1.712 | 1.454 |
| numeric | rotate-mix | codegen | MATCH | cycles | 6.276/6.277/6.281 | 4.707/4.715/4.757 | 0.750 | 4.707 | 1.000 |
| numeric | shift-constant | codegen | MATCH | cycles | 2.366/2.364/2.366 | 2.366/2.364/2.366 | 1.000 | 2.353 | 1.005 |
| numeric | shift-variable | codegen | MATCH | cycles | 2.514/2.514/2.516 | 2.514/2.514/2.514 | 1.000 | 2.502 | 1.005 |
| numeric | single-arithmetic | codegen | MATCH | cycles | 10.138/10.192/10.407 | 10.140/10.139/10.140 | 1.000 | 10.138 | 1.000 |
| numeric | single-double-convert | codegen | MATCH | cycles | 4.855/4.870/4.906 | 2.547/2.539/2.547 | 0.525 | 2.330 | 1.093 |
| numeric | small-set-ops | codegen | MATCH | cycles | 2.835/2.996/3.249 | 0.745/0.748/0.755 | 0.263 | 0.691 | 1.079 |
| numeric | uint32-div-constant | codegen | MATCH | cycles | 5.538/5.531/5.566 | 4.141/4.136/4.141 | 0.748 | 4.129 | 1.003 |
| numeric | uint64-div-constant | codegen | MATCH | cycles | 4.854/4.873/4.982 | 4.314/4.320/4.331 | 0.889 | 4.248 | 1.015 |
| numeric | unchecked-index | codegen | MATCH | cycles | 1.712/1.710/1.712 | 1.682/1.684/1.691 | 0.982 | 1.703 | 0.988 |
| numeric | wide-set-ops | codegen+rtl | MATCH | cycles | 90.374/90.287/90.668 | 27.694/27.665/27.755 | 0.306 | 27.627 | 1.002 |
| rtl | datetime-encode-decode | rtl | MATCH | cycles | 248.765/248.510/249.300 | 141.229/141.221/141.229 | 0.568 | 142.662 | 0.990 |
| rtl | datetime-format | rtl+mm | MATCH | cycles | 2123.117/2115.435/2126.411 | 1204.200/1206.654/1215.359 | 0.567 | 1242.595 | 0.969 |
| rtl | datetime-ms-arith | rtl | MATCH | cycles | 171.956/171.822/173.014 | 30.282/30.306/30.444 | 0.176 | 31.081 | 0.974 |
| rtl | datetime-now | rtl | MATCH | cycles | 194.569/195.673/202.814 | 211.052/211.168/211.662 | 1.085 | 211.052 | 1.000 |
| rtl | dictionary-512 | rtl+mm | MATCH | cycles | 65.451/65.267/65.689 | 54.322/54.575/55.154 | 0.830 | 55.025 | 0.987 |
| rtl | dictionary-add-512 | rtl+mm | MATCH | cycles | 89.918/90.090/90.592 | 71.861/71.753/72.077 | 0.799 | 72.704 | 0.988 |
| rtl | dictionary-add-reserved-512 | rtl+mm | MATCH | cycles | 94.392/94.278/94.416 | 57.789/57.618/57.920 | 0.612 | 56.677 | 1.020 |
| rtl | dictionary-capacity-1024 | rtl+mm | MATCH | cycles | 18075.840/18072.548/18157.920 | 755.663/756.015/759.617 | 0.042 | 1066.379 | 0.709 |
| rtl | dictionary-create-free | rtl+mm | MATCH | cycles | 285.601/301.751/341.717 | 275.887/276.556/278.331 | 0.966 | 270.167 | 1.021 |
| rtl | dictionary-get | rtl | MATCH | cycles | 43.023/42.709/43.427 | 37.287/37.495/38.155 | 0.867 | 37.014 | 1.007 |
| rtl | dictionary-string-get | rtl | MATCH | cycles | 66.790/67.648/69.916 | 44.748/44.838/44.990 | 0.670 | 43.766 | 1.022 |
| rtl | dictionary-update-remove-256 | rtl+mm | MATCH | cycles | 91.629/91.732/92.537 | 93.066/93.331/94.479 | 1.016 | 93.666 | 0.994 |
| rtl | dynamic-array-capacity-512 | rtl+mm | MATCH | cycles | 192.208/193.556/201.625 | 215.749/214.636/215.762 | 1.122 | 192.747 | 1.119 |
| rtl | dynamic-array-copy-512 | rtl+mm | MATCH | cycles | 0.218/0.219/0.224 | 0.322/0.322/0.324 | 1.476 | 0.358 | 0.899 |
| rtl | floattostr-double | rtl+mm | MATCH | cycles | 453.155/454.641/460.223 | 410.140/412.297/420.539 | 0.905 | 412.372 | 0.995 |
| rtl | format-float | rtl+mm | MATCH | cycles | 677.405/684.874/698.136 | 400.155/400.209/405.501 | 0.591 | 371.500 | 1.077 |
| rtl | format-integer | rtl+mm | MATCH | cycles | 226.272/227.163/228.689 | 72.991/73.005/73.553 | 0.323 | 85.537 | 0.853 |
| rtl | format-literal | rtl+mm | MATCH | cycles | 134.367/134.525/135.981 | 73.318/73.315/73.697 | 0.546 | 72.516 | 1.011 |
| rtl | format-mixed | rtl+mm | MATCH | cycles | 834.400/844.765/880.266 | 600.286/595.588/601.433 | 0.719 | 587.352 | 1.022 |
| rtl | format-string | rtl+mm | MATCH | cycles | 148.190/148.204/148.784 | 13.124/13.181/13.691 | 0.089 | 13.694 | 0.958 |
| rtl | generic-list-add-reserved | rtl | MATCH | cycles | 9.960/10.038/10.149 | 10.693/10.600/10.695 | 1.074 | 9.142 | 1.170 |
| rtl | generic-list-binarysearch | rtl | MATCH | cycles | 109.980/110.034/110.733 | 72.960/72.998/73.202 | 0.663 | 77.654 | 0.940 |
| rtl | generic-list-capacity-512 | rtl+mm | MATCH | cycles | 412.509/414.584/418.552 | 404.091/404.356/406.777 | 0.980 | 400.179 | 1.010 |
| rtl | generic-list-create-free | rtl+mm | MATCH | cycles | 213.836/212.853/213.837 | 198.186/198.869/200.835 | 0.927 | 194.244 | 1.020 |
| rtl | generic-list-delete-front-128 | rtl | MATCH | cycles | 37.795/37.742/38.019 | 37.928/38.770/43.780 | 1.004 | 37.480 | 1.012 |
| rtl | generic-list-delete-tail-512 | rtl | MATCH | cycles | 20.898/21.136/21.731 | 15.087/15.119/15.489 | 0.722 | 14.873 | 1.014 |
| rtl | generic-list-enumerator-512 | rtl | MATCH | cycles | 9.341/9.358/9.677 | 6.315/6.312/6.349 | 0.676 | 6.336 | 0.997 |
| rtl | generic-list-growth-512 | rtl+mm | MATCH | cycles | 14.758/14.863/15.024 | 15.486/15.437/15.488 | 1.049 | 15.869 | 0.976 |
| rtl | generic-list-index-512 | rtl | MATCH | cycles | 3.450/3.460/3.536 | 3.793/3.807/3.917 | 1.099 | 3.800 | 0.998 |
| rtl | generic-list-indexof | rtl | MATCH | cycles | 425.164/425.220/425.426 | 128.039/128.068/128.230 | 0.301 | 131.342 | 0.975 |
| rtl | generic-list-remove-128 | rtl | MATCH | cycles | 140.834/141.168/141.887 | 56.453/56.347/56.912 | 0.401 | 54.733 | 1.031 |
| rtl | generic-list-reserved-512 | rtl+mm | MATCH | cycles | 8.902/8.944/9.073 | 9.421/9.426/9.491 | 1.058 | 9.331 | 1.010 |
| rtl | generic-list-sort-512 | rtl | MATCH | cycles | 61486.967/61634.419/61796.216 | 43743.846/43905.055/44280.962 | 0.711 | 44046.471 | 0.993 |
| rtl | helper-compareto | rtl | MATCH | cycles | 36.942/36.966/37.533 | 34.175/33.931/34.193 | 0.925 | 34.273 | 0.997 |
| rtl | helper-endswith-nocase | rtl+mm | MATCH | cycles | 211.298/211.812/214.152 | 12.067/12.001/12.069 | 0.057 | 11.938 | 1.011 |
| rtl | helper-indexof-string | rtl+mm | MATCH | cycles | 2334.182/2329.891/2337.690 | 1813.680/1818.934/1824.899 | 0.777 | 1827.888 | 0.992 |
| rtl | helper-split-16 | rtl+mm | MATCH | cycles | 92.327/91.883/92.477 | 80.974/81.120/81.937 | 0.877 | 81.867 | 0.989 |
| rtl | helper-startswith | rtl | MATCH | cycles | 15.250/15.261/15.410 | 12.004/11.972/12.004 | 0.787 | 12.010 | 1.000 |
| rtl | helper-startswith-nocase | rtl+mm | MATCH | cycles | 286.064/284.335/286.622 | 18.211/18.255/18.322 | 0.064 | 18.307 | 0.995 |
| rtl | inttohex-int64 | rtl+mm | MATCH | cycles | 42.688/42.623/42.723 | 75.265/75.137/75.456 | 1.763 | 73.749 | 1.021 |
| rtl | inttostr-int32 | rtl+mm | MATCH | cycles | 29.776/29.747/29.804 | 29.695/29.703/29.730 | 0.997 | 31.796 | 0.934 |
| rtl | inttostr-int64 | rtl+mm | MATCH | cycles | 32.963/32.993/33.148 | 35.806/35.847/35.992 | 1.086 | 36.659 | 0.977 |
| rtl | lowercase-short | rtl+mm | MATCH | cycles | 29.897/29.941/30.116 | 34.448/34.448/34.449 | 1.152 | 35.248 | 0.977 |
| rtl | memorystream-64k | rtl+mm | MATCH | cycles | 0.055/0.055/0.055 | 0.055/0.055/0.055 | 0.999 | 0.055 | 0.989 |
| rtl | memorystream-write-small | rtl+mm | MATCH | cycles | 15.604/15.635/15.687 | 14.176/14.156/14.179 | 0.909 | 12.622 | 1.123 |
| rtl | object-alloc-zero-free | mm | MATCH | cycles | 26.577/27.564/30.895 | 28.995/29.066/29.178 | 1.091 | 34.628 | 0.837 |
| rtl | object-create-free | rtl+mm | MATCH | cycles | 99.091/99.806/104.636 | 75.701/76.386/78.103 | 0.764 | 78.099 | 0.969 |
| rtl | object-create-virtual-free | rtl+mm | MATCH | cycles | 105.504/107.142/109.720 | 89.729/89.726/89.730 | 0.850 | 93.427 | 0.960 |
| rtl | object-new-freeinstance | rtl+mm | MATCH | cycles | 63.746/64.512/71.706 | 54.987/55.355/56.131 | 0.863 | 58.480 | 0.940 |
| rtl | object-virtual-call | rtl | MATCH | cycles | 4.831/4.725/4.831 | 4.048/4.051/4.061 | 0.838 | 5.578 | 0.726 |
| rtl | queue-512 | rtl+mm | MATCH | cycles | 20.174/20.220/20.444 | 16.782/16.797/16.882 | 0.832 | 18.401 | 0.912 |
| rtl | queue-reserved-512 | rtl | MATCH | cycles | 18.945/18.961/19.206 | 16.899/16.803/16.966 | 0.892 | 16.899 | 1.000 |
| rtl | sametext-short | rtl | MATCH | cycles | 12.817/12.901/13.097 | 13.111/13.161/13.352 | 1.023 | 13.470 | 0.973 |
| rtl | stack-512 | rtl | MATCH | cycles | 16.893/16.964/17.141 | 15.763/15.729/15.764 | 0.933 | 15.329 | 1.028 |
| rtl | str-double-general | rtl | MATCH | cycles | 405.255/406.057/407.639 | 219.208/219.323/219.922 | 0.541 | 220.476 | 0.994 |
| rtl | string-replace-all | rtl+mm | MATCH | cycles | 304.201/304.474/314.722 | 331.510/331.247/331.970 | 1.090 | 346.165 | 0.958 |
| rtl | stringlist-add-128 | rtl+mm | MATCH | cycles | 83.271/83.904/87.065 | 41.650/41.329/41.923 | 0.500 | 41.463 | 1.005 |
| rtl | stringlist-add-sort-128 | rtl+mm | MATCH | cycles | 2438.934/2435.920/2448.795 | 2394.085/2390.813/2399.598 | 0.982 | 2375.424 | 1.008 |
| rtl | stringlist-delimited | rtl+mm | MATCH | cycles | 237.770/239.464/242.190 | 148.948/148.349/150.591 | 0.626 | 117.014 | 1.273 |
| rtl | stringlist-indexof-128 | rtl | MATCH | cycles | 28605.391/28516.752/28727.109 | 29214.727/29004.900/29218.438 | 1.021 | 29162.031 | 1.002 |
| rtl | stringlist-namevalue | rtl | MATCH | cycles | 26332.273/26443.014/26691.724 | 26432.710/26482.040/26836.395 | 1.004 | 26354.943 | 1.003 |
| rtl | stringlist-values | rtl+mm | MATCH | cycles | 7139.393/7124.715/7141.801 | 7114.980/7151.312/7208.013 | 0.997 | 7070.712 | 1.006 |
| rtl | stringstream-build | rtl+mm | MATCH | cycles | 289.177/289.967/293.510 | 276.169/276.360/277.912 | 0.955 | 285.465 | 0.967 |
| rtl | strtofloat-double | rtl+mm | MATCH | cycles | 279.384/279.056/281.097 | 268.042/269.136/270.502 | 0.959 | 263.150 | 1.019 |
| rtl | strtoint-int64 | rtl+mm | MATCH | cycles | 39.457/39.453/39.470 | 40.259/40.223/40.312 | 1.020 | 40.248 | 1.000 |
| rtl | trim-string | rtl+mm | MATCH | cycles | 60.651/60.581/62.373 | 35.439/35.472/35.654 | 0.584 | 39.254 | 0.903 |
| rtl | trystrtoint | rtl | MATCH | cycles | 39.688/39.636/39.692 | 43.110/42.987/43.111 | 1.086 | 43.454 | 0.992 |
| rtl | trystrtoint-edges | rtl | MATCH | cycles | 30.260/30.455/30.975 | 29.204/29.343/29.889 | 0.965 | 28.726 | 1.017 |
| rtl | unicode-comparetext | rtl | MATCH | cycles | 20.050/20.085/20.246 | 18.910/18.934/19.031 | 0.943 | 19.047 | 0.993 |
| rtl | unicode-concat-32 | rtl+mm | MATCH | cycles | 79.945/80.005/80.284 | 63.599/63.561/64.578 | 0.796 | 79.643 | 0.799 |
| rtl | unicode-copy-96 | rtl+mm | MATCH | cycles | 57.172/56.945/57.484 | 30.770/30.730/30.801 | 0.538 | 33.017 | 0.932 |
| rtl | unicode-lowercase-4k | rtl+mm | MATCH | cycles | 1.590/1.592/1.598 | 1.190/1.192/1.197 | 0.749 | 1.191 | 1.000 |
| rtl | unicode-pos-4k | rtl | MATCH | cycles | 4828.781/4722.043/4857.188 | 3210.856/3203.511/3219.266 | 0.665 | 3237.692 | 0.992 |
| rtl | unicode-uppercase-4k | rtl+mm | MATCH | cycles | 1.597/1.599/1.606 | 1.197/1.195/1.197 | 0.749 | 1.191 | 1.005 |
| rtl | utf8-decode-4k | rtl+mm | MATCH | cycles | 0.651/0.651/0.653 | 0.646/0.648/0.653 | 0.993 | 0.657 | 0.984 |
| rtl | utf8-encode-4k | rtl+mm | MATCH | cycles | 0.636/0.633/0.636 | 0.251/0.252/0.256 | 0.395 | 0.261 | 0.964 |
| rtl | utf8-encode-decode-4k | rtl+mm | MATCH | cycles | 1.294/1.291/1.294 | 0.900/0.899/0.903 | 0.695 | 0.921 | 0.976 |
| rtl-collections | array-binarysearch | rtl | MATCH | cycles | 120.661/120.288/121.408 | 110.493/110.510/110.985 | 0.916 | 107.055 | 1.032 |
| rtl-collections | array-integer-copy | rtl+mm | MATCH | cycles | 0.322/0.323/0.325 | 0.348/0.353/0.374 | 1.081 | 0.584 | 0.597 |
| rtl-collections | array-integer-sort | rtl+mm | MATCH | cycles | 48.345/48.195/48.587 | 33.144/33.123/33.462 | 0.686 | 33.857 | 0.979 |
| rtl-collections | array-string-sort | rtl+mm | MATCH | cycles | 206.557/207.277/208.399 | 158.006/158.472/159.597 | 0.765 | 157.437 | 1.004 |
| rtl-collections | dictionary-addorset | rtl | MATCH | cycles | 49.506/49.481/49.994 | 48.080/48.016/48.152 | 0.971 | 52.642 | 0.913 |
| rtl-collections | dictionary-collision-churn | rtl+mm | MATCH | cycles | 323.746/323.821/325.430 | 315.928/316.673/318.088 | 0.976 | 336.515 | 0.939 |
| rtl-collections | dictionary-contains-key | rtl | MATCH | cycles | 32.399/32.524/32.717 | 29.770/29.719/29.822 | 0.919 | 31.082 | 0.958 |
| rtl-collections | dictionary-contains-value | rtl | MATCH | cycles | 3119.347/3126.788/3136.349 | 1482.310/1490.898/1499.714 | 0.475 | 1799.852 | 0.824 |
| rtl-collections | dictionary-keys | rtl | MATCH | cycles | 38.242/38.261/38.472 | 19.942/19.952/20.024 | 0.521 | 20.047 | 0.995 |
| rtl-collections | dictionary-pairs | rtl | MATCH | cycles | 48.342/48.515/48.854 | 22.290/22.252/22.354 | 0.461 | 22.400 | 0.995 |
| rtl-collections | dictionary-string-add | rtl+mm | MATCH | cycles | 239.686/240.383/242.755 | 249.036/253.274/261.141 | 1.039 | 256.186 | 0.972 |
| rtl-collections | dictionary-string-clear | rtl+mm | MATCH | cycles | 315.191/314.733/317.550 | 344.286/347.054/353.637 | 1.092 | 347.878 | 0.990 |
| rtl-collections | dictionary-string-contains | rtl | MATCH | cycles | 57.282/57.549/58.662 | 39.475/39.537/39.765 | 0.689 | 40.878 | 0.966 |
| rtl-collections | dictionary-tryadd | rtl+mm | MATCH | cycles | 57.011/57.280/58.373 | 51.142/51.539/52.608 | 0.897 | 54.780 | 0.934 |
| rtl-collections | dictionary-values | rtl | MATCH | cycles | 38.067/38.188/38.475 | 19.776/19.773/19.887 | 0.520 | 19.884 | 0.995 |
| rtl-collections | list-exchange-reverse | rtl+mm | MATCH | cycles | 18.845/18.719/18.867 | 14.735/15.341/17.342 | 0.782 | 15.732 | 0.937 |
| rtl-collections | list-integer-addrange-4096 | rtl+mm | MATCH | cycles | 0.469/0.479/0.526 | 0.333/0.335/0.338 | 0.710 | 0.487 | 0.684 |
| rtl-collections | list-integer-clear-4096 | rtl+mm | MATCH | cycles | 0.417/0.418/0.421 | 0.275/0.275/0.275 | 0.659 | 0.417 | 0.658 |
| rtl-collections | list-integer-copy-construct | rtl+mm | MATCH | cycles | 2.488/2.497/2.514 | 1.252/1.258/1.332 | 0.503 | 1.676 | 0.747 |
| rtl-collections | list-integer-delete-insert-range-4096 | rtl+mm | MATCH | cycles | 0.192/0.191/0.192 | 0.159/0.159/0.161 | 0.830 | 0.146 | 1.090 |
| rtl-collections | list-integer-empty-create | rtl+mm | MATCH | cycles | 211.987/209.618/211.994 | 191.856/193.136/195.088 | 0.905 | 211.286 | 0.908 |
| rtl-collections | list-integer-exchange | rtl | MATCH | cycles | 5.052/5.043/5.082 | 5.853/5.869/5.928 | 1.159 | 5.766 | 1.015 |
| rtl-collections | list-integer-indexof | rtl | MATCH | cycles | 179.919/179.985/180.197 | 90.365/90.281/90.365 | 0.502 | 90.353 | 1.000 |
| rtl-collections | list-integer-insertrange-list-4096 | rtl+mm | MATCH | cycles | 1.015/1.016/1.020 | 1.127/1.130/1.136 | 1.110 | 1.410 | 0.799 |
| rtl-collections | list-integer-pack-alternating-4096 | rtl+mm | MATCH | cycles | 25.260/25.523/26.489 | 6.821/6.805/6.826 | 0.270 | 7.297 | 0.935 |
| rtl-collections | list-integer-reverse | rtl | MATCH | cycles | 1.822/1.818/1.838 | 1.747/1.744/1.747 | 0.959 | 1.719 | 1.016 |
| rtl-collections | list-integer-sort | rtl+mm | MATCH | cycles | 50.251/50.260/50.293 | 34.842/34.773/34.842 | 0.693 | 35.817 | 0.973 |
| rtl-collections | list-string-add-reserved | rtl+mm | MATCH | cycles | 26.679/26.788/27.187 | 27.588/27.696/28.551 | 1.034 | 25.856 | 1.067 |
| rtl-collections | list-string-addrange-4096 | rtl+mm | MATCH | cycles | 24.881/24.952/25.182 | 28.267/28.408/28.711 | 1.136 | 27.817 | 1.016 |
| rtl-collections | list-string-clear-4096 | rtl+mm | MATCH | cycles | 24.871/25.035/26.078 | 20.781/20.841/21.127 | 0.836 | 20.065 | 1.036 |
| rtl-collections | list-string-enumerate | rtl | MATCH | cycles | 15.305/15.475/15.972 | 14.466/14.462/14.777 | 0.945 | 14.040 | 1.030 |
| rtl-collections | list-string-indexof | rtl | MATCH | cycles | 1134.062/1141.140/1199.746 | 824.941/826.988/829.469 | 0.727 | 824.570 | 1.000 |
| rtl-collections | list-string-insert-delete | rtl+mm | MATCH | cycles | 73.229/74.669/82.144 | 74.576/74.582/74.905 | 1.018 | 78.420 | 0.951 |
| rtl-collections | list-string-insertrange-2048 | rtl+mm | MATCH | cycles | 62.311/63.619/66.287 | 109.463/110.280/113.122 | 1.757 | 125.360 | 0.873 |
| rtl-collections | list-string-read | rtl | MATCH | cycles | 3.249/3.269/3.381 | 2.466/2.472/2.513 | 0.759 | 3.230 | 0.763 |
| rtl-collections | list-string-sort | rtl+mm | MATCH | cycles | 218.593/219.422/220.355 | 180.155/181.742/186.336 | 0.824 | 179.897 | 1.001 |
| rtl-collections | list-string-toarray | rtl+mm | MATCH | cycles | 12.911/12.957/13.077 | 12.912/12.932/13.051 | 1.000 | 13.149 | 0.982 |
| rtl-collections | objectlist-owned-clear | rtl+mm | MATCH | cycles | 140.792/141.148/142.029 | 115.703/115.920/116.703 | 0.822 | 125.196 | 0.924 |
| rtl-collections | queue-enumerate | rtl | MATCH | cycles | 15.160/15.217/15.655 | 6.670/6.715/6.846 | 0.440 | 7.026 | 0.949 |
| rtl-collections | queue-integer-steady | rtl | MATCH | cycles | 0.141/0.141/0.142 | 0.109/0.109/0.109 | 0.772 | 0.116 | 0.940 |
| rtl-collections | queue-record128-steady | rtl | MATCH | cycles | 72.452/73.310/75.871 | 38.471/38.697/38.942 | 0.531 | 41.052 | 0.937 |
| rtl-collections | queue-string-clear | rtl+mm | MATCH | cycles | 61.532/61.904/62.365 | 49.770/49.932/50.125 | 0.809 | 47.659 | 1.044 |
| rtl-collections | queue-string-roundtrip | rtl+mm | MATCH | cycles | 50.081/50.227/50.731 | 24.772/24.790/24.952 | 0.495 | 23.398 | 1.059 |
| rtl-collections | queue-string-steady | rtl | MATCH | cycles | 50.681/50.713/51.190 | 23.930/23.902/24.011 | 0.472 | 22.276 | 1.074 |
| rtl-collections | stack-enumerate | rtl | MATCH | cycles | 9.916/9.863/9.975 | 6.875/6.894/6.989 | 0.693 | 6.802 | 1.011 |
| rtl-collections | stack-integer-roundtrip | rtl | MATCH | cycles | 17.038/17.122/17.219 | 14.048/14.040/14.106 | 0.825 | 14.802 | 0.949 |
| rtl-collections | stack-string-clear | rtl+mm | MATCH | cycles | 66.477/66.399/68.087 | 55.448/55.579/55.855 | 0.834 | 53.233 | 1.042 |
| rtl-collections | stack-string-roundtrip | rtl+mm | MATCH | cycles | 48.554/48.505/48.666 | 24.342/24.354/24.476 | 0.501 | 22.351 | 1.089 |
| threads | cross-thread-free-4 | mm | MATCH | tsc | 43950.681/41863.206/44038.113 | 4606.681/4417.391/4613.155 | 0.105 | 2730.955 | 1.687 |
| threads | false-sharing-4 | memory | MATCH | tsc | 19.334/19.756/20.893 | 22.230/22.419/23.686 | 1.150 | 23.114 | 0.962 |
| threads | independent-cpu-1 | compiler+os | MATCH | tsc | 3.154/3.187/3.371 | 3.158/3.193/3.365 | 1.001 | 3.145 | 1.004 |
| threads | independent-cpu-2 | compiler+os | MATCH | tsc | 1.850/1.853/1.899 | 1.887/1.875/1.899 | 1.020 | 1.600 | 1.179 |
| threads | independent-cpu-4 | compiler+os | MATCH | tsc | 0.933/0.960/1.123 | 0.961/0.978/1.151 | 1.029 | 0.802 | 1.198 |
| threads | independent-cpu-8 | compiler+os | MATCH | tsc | 0.482/0.501/0.576 | 0.490/0.516/0.597 | 1.018 | 0.415 | 1.181 |
| threads | locked-increment-4 | rtl+os | MATCH | tsc | 106.126/107.019/108.772 | 91.985/91.424/92.004 | 0.867 | 89.785 | 1.024 |
| threads | padded-counters-4 | memory | MATCH | tsc | 0.998/1.025/1.189 | 0.428/0.442/0.524 | 0.429 | 0.428 | 1.000 |
| threads | parallel-alloc-free-1 | mm | MATCH | tsc | 66.758/68.938/79.533 | 65.796/66.027/67.724 | 0.986 | 91.376 | 0.720 |
| threads | parallel-alloc-free-2 | mm | MATCH | tsc | 23159.659/17157.579/28084.347 | 60.911/61.462/63.171 | 0.003 | 83.870 | 0.726 |
| threads | parallel-alloc-free-4 | mm | MATCH | tsc | 38840.966/37804.245/43916.130 | 51.534/58.908/72.507 | 0.001 | 42.005 | 1.227 |
| threads | parallel-alloc-free-8 | mm | MATCH | tsc | 29039.806/29720.897/36278.930 | 107.374/107.046/116.271 | 0.004 | 21.328 | 5.034 |
| threads | parallel-alloc-free-96-4 | mm | MATCH | tsc | 43447.359/43510.806/43683.806 | 15.048/15.166/15.485 | 0.000 | 19.963 | 0.754 |
| threads | parallel-alloc-free-96-8 | mm | MATCH | tsc | 29298.132/28208.169/29373.680 | 93.569/55.395/94.334 | 0.003 | 10.064 | 9.298 |
| threads | producer-consumer | rtl+os | MATCH | tsc | 131.383/130.898/134.234 | 144.415/144.778/148.736 | 1.099 | 132.746 | 1.088 |
| threads | shared-read-4 | compiler+memory | MATCH | tsc | 0.996/0.996/1.007 | 0.827/0.829/0.833 | 0.830 | 0.983 | 0.841 |
| threads | thread-start-join-4 | os+rtl | MATCH | tsc | 144877.375/151329.685/178129.750 | 154124.042/158986.798/174652.750 | 1.064 | 157396.000 | 0.979 |
| workloads | binary-trees-depth-10 | codegen+mm | MATCH | cycles | 37.007/37.030/37.282 | 40.072/40.775/44.160 | 1.083 | 43.001 | 0.932 |
| workloads | convolution-256 | codegen+memory | MATCH | cycles | 3.531/3.532/3.533 | 2.840/2.842/2.854 | 0.804 | 2.839 | 1.000 |
| workloads | fannkuch-8 | codegen | MATCH | cycles | 101.114/101.384/102.196 | 97.677/98.426/99.651 | 0.966 | 97.347 | 1.003 |
| workloads | fft-1024 | codegen+math | MATCH | cycles | 11.178/11.190/11.236 | 13.567/13.533/13.642 | 1.214 | 13.400 | 1.012 |
| workloads | floyd-warshall-64 | codegen+memory | MATCH | cycles | 3.583/3.584/3.591 | 4.476/4.455/4.517 | 1.249 | 4.257 | 1.051 |
| workloads | jacobi-2d-128x4 | codegen+memory | MATCH | cycles | 3.106/3.117/3.163 | 3.595/3.620/3.697 | 1.157 | 4.457 | 0.807 |
| workloads | linked-list-insert-sort-512 | codegen+mm | MATCH | cycles | 454.425/456.575/468.320 | 484.277/476.950/488.359 | 1.066 | 466.053 | 1.039 |
| workloads | mandelbrot-128 | codegen | MATCH | cycles | 182.462/182.446/182.555 | 183.112/183.118/183.181 | 1.004 | 183.228 | 0.999 |
| workloads | nbody-5x100 | codegen+math | MATCH | cycles | 19.748/19.448/19.753 | 18.714/18.355/18.720 | 0.948 | 18.705 | 1.001 |
| workloads | numeric-state-machine | codegen | MATCH | cycles | 7.483/7.546/7.651 | 5.868/5.859/5.898 | 0.784 | 5.447 | 1.077 |
| workloads | spectral-norm-128 | codegen | MATCH | cycles | 4.896/4.896/4.896 | 3.930/3.930/3.931 | 0.803 | 3.918 | 1.003 |
| workloads | stream-add | memory | MATCH | cycles | 0.846/0.843/0.855 | 0.780/0.776/0.780 | 0.922 | 0.772 | 1.010 |
| workloads | stream-copy | memory | MATCH | cycles | 0.907/0.907/0.914 | 0.673/0.673/0.683 | 0.741 | 0.881 | 0.764 |
| workloads | stream-scale | memory | MATCH | cycles | 1.058/1.104/1.224 | 0.897/0.898/0.921 | 0.847 | 0.885 | 1.013 |
| workloads | stream-triad | memory | MATCH | cycles | 0.935/0.946/0.985 | 0.798/0.799/0.811 | 0.854 | 0.801 | 0.997 |
