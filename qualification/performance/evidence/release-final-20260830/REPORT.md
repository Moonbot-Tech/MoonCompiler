# MoonCompiler Pulse result

Mode: `medium`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.
TSC is also used explicitly when scheduled thread cycles are unavailable for either system.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| abi | 24 | 0.718 | 14 | 8 | 2 | 0.966 |
| algorithms | 9 | 0.867 | 4 | 4 | 1 | 1.000 |
| calibration | 4 | 1.000 | 0 | 4 | 0 | 1.004 |
| codegen | 60 | 0.868 | 25 | 26 | 9 | 0.996 |
| dictionary | 30 | 0.879 | 16 | 4 | 10 | 1.109 |
| dispatch | 15 | 0.890 | 6 | 6 | 3 | 0.985 |
| heartbeat | 20 | 0.819 | 18 | 2 | 0 | 0.991 |
| json | 11 | 0.898 | 6 | 1 | 4 | 0.992 |
| kernels | 10 | 0.852 | 6 | 3 | 1 | 0.980 |
| layout | 20 | 0.653 | 12 | 5 | 3 | 1.025 |
| local-pressure | 9 | 0.208 | 7 | 2 | 0 | 1.003 |
| loops | 20 | 0.879 | 9 | 11 | 0 | 0.946 |
| managed | 17 | 0.913 | 7 | 7 | 3 | 0.951 |
| mm | 15 | 0.977 | 6 | 5 | 4 | 0.590 |
| mormot-json | 18 | 0.860 | 13 | 4 | 1 | 0.857 |
| move | 297 | 0.947 | 106 | 155 | 36 | 0.994 |
| numeric | 21 | 0.760 | 10 | 10 | 1 | 1.015 |
| rtl | 77 | 0.691 | 52 | 17 | 8 | 0.988 |
| rtl-collections | 48 | 0.729 | 35 | 7 | 6 | 0.958 |
| threads | 17 | 0.115 | 9 | 5 | 3 | 1.038 |
| workloads | 15 | 0.966 | 5 | 7 | 3 | 0.997 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| abi | 24 | 0.718 | 14 | 8 | 2 |
| app | 1 | 0.865 | 1 | 0 | 0 |
| application | 10 | 0.852 | 6 | 3 | 1 |
| calibration | 4 | 1.000 | 0 | 4 | 0 |
| codegen | 156 | 0.785 | 71 | 67 | 18 |
| compiler | 23 | 0.945 | 11 | 9 | 3 |
| integrated | 1 | 0.837 | 1 | 0 | 0 |
| managed | 11 | 0.238 | 9 | 1 | 1 |
| math | 4 | 0.957 | 2 | 2 | 0 |
| memory | 344 | 0.933 | 127 | 174 | 43 |
| mm | 132 | 0.601 | 87 | 23 | 22 |
| mormot-json | 22 | 0.844 | 17 | 4 | 1 |
| os | 7 | 1.019 | 1 | 4 | 2 |
| rtl | 520 | 0.857 | 255 | 195 | 70 |
| text | 1 | 0.922 | 1 | 0 | 0 |

## Extreme results

### 15 fastest

- `threads/parallel-alloc-free-96-8`: `0.000x`
- `threads/parallel-alloc-free-96-4`: `0.000x`
- `threads/parallel-alloc-free-4`: `0.002x`
- `threads/parallel-alloc-free-2`: `0.002x`
- `threads/parallel-alloc-free-8`: `0.003x`
- `local-pressure/unused-mixed-300`: `0.005x`
- `local-pressure/unused-buffers-100`: `0.010x`
- `local-pressure/unused-strings-100`: `0.026x`
- `rtl/dictionary-capacity-1024`: `0.042x`
- `rtl/helper-endswith-nocase`: `0.062x`
- `rtl/helper-startswith-nocase`: `0.063x`
- `rtl/format-string`: `0.098x`
- `threads/cross-thread-free-4`: `0.100x`
- `abi/string-value`: `0.191x`
- `rtl/datetime-ms-arith`: `0.194x`

### 15 slowest

- `dictionary/u64-string-build-reserved-100`: `1.749x`
- `rtl/inttohex-int64`: `1.736x`
- `codegen/case-dense`: `1.663x`
- `rtl-collections/list-integer-exchange`: `1.633x`
- `rtl-collections/list-string-insertrange-2048`: `1.622x`
- `dispatch/raise-catch`: `1.576x`
- `abi/dynamic-array-value`: `1.550x`
- `managed/managed-exception-cleanup`: `1.492x`
- `mm/alloc-free-256`: `1.450x`
- `mm/alloc-free-1024`: `1.443x`
- `rtl-collections/list-integer-reverse`: `1.412x`
- `dictionary/u64-string-churn-10000`: `1.389x`
- `codegen/try-finally-normal`: `1.379x`
- `codegen/for-runtime-0-255`: `1.350x`
- `dictionary/u64-u64-churn-10000`: `1.349x`
## Diagnostic process-drift paired rows

These cases remain in the table, but the central ratio is calculated from adjacent mirrored processes; drift does not replace a semantic failure.

- `paired/move/hot-a0-a0-n8388608 unavailable (no stable ratio cluster contains at least half of the pairs); using process-balanced diagnostic ratio`
- `paired-mm/threads/cross-thread-free-4 unavailable (no stable ratio cluster contains at least half of the pairs); using process-balanced diagnostic ratio`
- `paired/threads/parallel-alloc-free-4 unavailable (no stable ratio cluster contains at least half of the pairs); using process-balanced diagnostic ratio`
- `paired/threads/parallel-alloc-free-96-4 unavailable (no stable ratio cluster contains at least half of the pairs); using process-balanced diagnostic ratio`
- `paired/threads/parallel-alloc-free-96-8 unavailable (no stable ratio cluster contains at least half of the pairs); using process-balanced diagnostic ratio`

## All cases

| Program | Case | Layer | Oracle | Metric | delphi stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| abi | dynamic-array-const | abi+managed | MATCH | cycles | 4.856/4.856/4.856 | 4.043/4.043/4.047 | 0.832 | 4.830 | 0.837 |
| abi | dynamic-array-value | abi+managed | MATCH | cycles | 15.106/15.173/15.598 | 23.418/23.434/23.538 | 1.550 | 23.429 | 0.999 |
| abi | eight-args | abi | MATCH | cycles | 11.142/11.151/11.202 | 10.025/10.025/10.025 | 0.900 | 12.708 | 0.789 |
| abi | four-args | abi | MATCH | cycles | 6.309/6.313/6.339 | 6.353/6.353/6.354 | 1.007 | 6.275 | 1.012 |
| abi | function-pointer | abi | MATCH | cycles | 4.818/4.808/4.818 | 4.756/4.767/4.781 | 0.987 | 4.756 | 1.000 |
| abi | interface-method | abi+managed | MATCH | cycles | 6.446/6.461/6.480 | 5.637/5.645/5.667 | 0.874 | 5.687 | 0.991 |
| abi | method-pointer | abi | MATCH | cycles | 5.548/5.548/5.549 | 5.548/5.558/5.578 | 1.000 | 5.578 | 0.995 |
| abi | mixed-args | abi | MATCH | cycles | 12.935/12.934/12.935 | 8.297/8.302/8.339 | 0.641 | 8.350 | 0.994 |
| abi | no-args | abi | MATCH | cycles | 0.821/0.821/0.821 | 0.833/0.833/0.833 | 1.015 | 0.821 | 1.015 |
| abi | one-arg | abi | MATCH | cycles | 4.707/4.707/4.711 | 4.707/4.707/4.707 | 1.000 | 4.707 | 1.000 |
| abi | open-array-const | abi | MATCH | cycles | 4.077/4.077/4.080 | 4.818/4.818/4.818 | 1.182 | 4.831 | 0.997 |
| abi | record16-value | abi | MATCH | cycles | 14.056/14.042/14.064 | 5.519/5.523/5.548 | 0.393 | 5.520 | 1.000 |
| abi | record24-value | abi | MATCH | cycles | 15.756/15.761/15.792 | 3.510/3.510/3.510 | 0.223 | 3.371 | 1.041 |
| abi | record32-const | abi | MATCH | cycles | 4.843/4.844/4.844 | 4.856/4.860/4.882 | 1.003 | 4.843 | 1.003 |
| abi | record32-value | abi | MATCH | cycles | 20.694/20.703/20.723 | 7.484/7.484/7.485 | 0.362 | 8.708 | 0.859 |
| abi | record32-var | abi | MATCH | cycles | 4.843/4.844/4.844 | 5.026/5.026/5.026 | 1.038 | 5.042 | 0.997 |
| abi | record8-value | abi | MATCH | cycles | 6.866/6.870/6.902 | 2.702/2.702/2.702 | 0.394 | 2.663 | 1.015 |
| abi | return-record16 | abi | MATCH | cycles | 12.402/12.429/12.490 | 11.584/11.558/11.584 | 0.934 | 18.055 | 0.642 |
| abi | return-record24 | abi | MATCH | cycles | 18.100/18.115/18.196 | 13.424/13.439/13.495 | 0.742 | 18.090 | 0.742 |
| abi | return-record32 | abi | MATCH | cycles | 19.218/19.249/19.322 | 17.422/17.397/17.436 | 0.907 | 14.081 | 1.237 |
| abi | return-record8 | abi | MATCH | cycles | 11.136/11.135/11.155 | 5.491/5.491/5.492 | 0.493 | 5.491 | 1.000 |
| abi | string-const | abi+managed | MATCH | cycles | 4.843/4.847/4.869 | 2.868/2.866/2.868 | 0.592 | 2.587 | 1.109 |
| abi | string-value | abi+managed | MATCH | cycles | 15.044/15.073/15.167 | 2.868/2.868/2.871 | 0.191 | 2.587 | 1.109 |
| abi | virtual-method | abi | MATCH | cycles | 5.578/5.578/5.578 | 5.578/5.590/5.607 | 1.000 | 5.578 | 1.000 |
| algorithms | binary-search-256 | codegen | MATCH | cycles | 150.748/149.858/152.160 | 148.985/148.486/149.216 | 0.988 | 148.763 | 1.001 |
| algorithms | chacha20-block | codegen | MATCH | cycles | 18.540/18.482/18.581 | 7.763/7.774/7.816 | 0.419 | 7.775 | 0.999 |
| algorithms | crc32-bitwise-4k | codegen | MATCH | cycles | 9.567/9.599/9.667 | 9.132/9.151/9.217 | 0.954 | 9.138 | 0.999 |
| algorithms | generic-list-512 | rtl | MATCH | cycles | 7.368/7.441/7.831 | 6.401/6.395/6.432 | 0.869 | 6.656 | 0.962 |
| algorithms | lz-compress-4k | codegen+memory | MATCH | cycles | 138.453/138.686/139.207 | 120.258/120.370/120.907 | 0.869 | 117.729 | 1.021 |
| algorithms | lz-roundtrip-4k | codegen+memory | MATCH | cycles | 72.549/71.891/72.889 | 62.755/62.178/63.445 | 0.865 | 61.115 | 1.027 |
| algorithms | open-hash-4096 | codegen+memory | MATCH | cycles | 6.945/6.975/7.033 | 7.917/7.989/8.070 | 1.140 | 8.226 | 0.962 |
| algorithms | quicksort-4096 | codegen+rtl | MATCH | cycles | 126.636/124.987/126.972 | 125.105/122.648/125.244 | 0.988 | 125.441 | 0.997 |
| algorithms | sha256-4k | codegen | MATCH | cycles | 17.234/17.184/17.241 | 16.422/16.428/16.505 | 0.953 | 15.945 | 1.030 |
| calibration | asm-dependent-add | calibration | MATCH | cycles | 0.841/0.841/0.841 | 0.841/0.841/0.841 | 1.000 | 0.841 | 1.000 |
| calibration | asm-memory-read-64m | calibration | MATCH | cycles | 0.137/0.139/0.145 | 0.136/0.139/0.144 | 0.992 | 0.136 | 1.004 |
| calibration | asm-memory-write-64m | calibration | MATCH | cycles | 0.179/0.178/0.182 | 0.180/0.186/0.222 | 1.006 | 0.178 | 1.012 |
| calibration | asm-mixed-integer | calibration | MATCH | cycles | 1.275/1.313/1.368 | 1.275/1.308/1.367 | 1.000 | 1.275 | 1.000 |
| codegen | abs-int | codegen | MATCH | cycles | 1.785/1.783/1.786 | 1.558/1.557/1.559 | 0.873 | 1.557 | 1.001 |
| codegen | branch-predictable | codegen | MATCH | cycles | 1.650/1.653/1.659 | 1.650/1.650/1.651 | 1.000 | 2.427 | 0.680 |
| codegen | branch-random | codegen | MATCH | cycles | 2.778/2.753/2.785 | 1.989/2.021/2.102 | 0.716 | 2.062 | 0.964 |
| codegen | call-eight-args | codegen | MATCH | cycles | 12.806/12.864/13.209 | 7.844/7.845/7.845 | 0.613 | 7.885 | 0.995 |
| codegen | call-indirect | codegen | MATCH | cycles | 4.022/4.027/4.043 | 4.034/4.031/4.034 | 1.003 | 4.021 | 1.003 |
| codegen | call-inline | codegen | MATCH | cycles | 2.365/2.365/2.378 | 2.353/2.355/2.365 | 0.995 | 2.354 | 1.000 |
| codegen | call-interface | codegen+rtl | MATCH | cycles | 4.869/4.880/4.895 | 5.658/5.666/5.687 | 1.162 | 4.882 | 1.159 |
| codegen | call-unit-direct | codegen | MATCH | cycles | 2.353/2.357/2.366 | 2.354/2.355/2.366 | 1.000 | 2.353 | 1.000 |
| codegen | call-virtual | codegen | MATCH | cycles | 5.645/5.674/5.805 | 4.856/4.877/4.938 | 0.860 | 4.843 | 1.003 |
| codegen | case-dense | codegen | MATCH | cycles | 3.890/3.916/4.012 | 6.467/6.483/6.516 | 1.663 | 5.560 | 1.163 |
| codegen | case-sparse | codegen | MATCH | cycles | 4.290/4.287/4.290 | 4.265/4.276/4.331 | 0.994 | 5.066 | 0.842 |
| codegen | concrete-reverse-int | codegen | MATCH | cycles | 2.858/2.874/2.927 | 3.006/3.011/3.038 | 1.052 | 3.087 | 0.974 |
| codegen | concrete-reverse-rec | codegen | MATCH | cycles | 14.404/14.802/17.671 | 5.241/5.266/5.321 | 0.364 | 5.102 | 1.027 |
| codegen | cse-expression | codegen | MATCH | cycles | 4.896/4.894/4.896 | 3.996/4.007/4.017 | 0.816 | 4.275 | 0.935 |
| codegen | currency-mul-div | codegen+rtl | MATCH | cycles | 201.925/202.375/203.786 | 41.034/41.198/41.441 | 0.203 | 41.093 | 0.999 |
| codegen | dead-store-chain | codegen | MATCH | cycles | 5.033/5.042/5.058 | 3.644/3.648/3.664 | 0.724 | 3.600 | 1.012 |
| codegen | dep-add | codegen | MATCH | cycles | 3.138/3.138/3.138 | 3.138/3.138/3.138 | 1.000 | 3.138 | 1.000 |
| codegen | double-mixed | codegen | MATCH | cycles | 4.237/4.237/4.237 | 4.237/4.237/4.237 | 1.000 | 4.237 | 1.000 |
| codegen | enum-set-membership | codegen | MATCH | cycles | 4.164/4.164/4.165 | 4.007/3.987/4.008 | 0.962 | 4.202 | 0.954 |
| codegen | fillchar-4k | rtl | MATCH | cycles | 0.037/0.037/0.037 | 0.049/0.049/0.050 | 1.326 | 0.049 | 1.000 |
| codegen | for-byte-0-255 | codegen | MATCH | cycles | 1.621/1.621/1.621 | 0.843/0.843/0.843 | 0.520 | 0.843 | 1.000 |
| codegen | for-downto | codegen | MATCH | cycles | 0.833/0.838/0.851 | 0.852/0.854/0.876 | 1.022 | 0.833 | 1.023 |
| codegen | for-length-array | codegen | MATCH | cycles | 1.623/1.623/1.623 | 0.831/0.845/0.885 | 0.512 | 0.831 | 1.000 |
| codegen | for-length-string | codegen | MATCH | cycles | 1.529/1.530/1.540 | 0.848/0.843/0.852 | 0.554 | 0.852 | 0.995 |
| codegen | for-runtime-0-0 | codegen | MATCH | cycles | 2.366/2.366/2.366 | 1.585/1.585/1.585 | 0.670 | 1.577 | 1.005 |
| codegen | for-runtime-0-255 | codegen | MATCH | cycles | 1.639/1.640/1.647 | 2.212/2.212/2.213 | 1.350 | 2.212 | 1.000 |
| codegen | generic-reverse-int | codegen | MATCH | cycles | 2.787/2.791/2.822 | 3.137/3.128/3.153 | 1.125 | 3.004 | 1.044 |
| codegen | generic-reverse-rec | codegen | MATCH | cycles | 14.342/14.257/14.342 | 5.312/5.316/5.341 | 0.370 | 5.119 | 1.038 |
| codegen | ilp-four-lanes | codegen | MATCH | cycles | 0.797/0.795/0.797 | 0.797/0.794/0.797 | 1.000 | 0.793 | 1.005 |
| codegen | int32-div-const | codegen | MATCH | cycles | 2.396/2.395/2.409 | 1.903/1.903/1.903 | 0.794 | 1.882 | 1.011 |
| codegen | int32-mixed | codegen | MATCH | cycles | 4.707/4.721/4.756 | 4.731/4.720/4.731 | 1.005 | 4.707 | 1.005 |
| codegen | int64-div-const | codegen | MATCH | cycles | 2.188/2.186/2.188 | 2.144/2.148/2.159 | 0.980 | 2.222 | 0.965 |
| codegen | int64-mod-latency | codegen | MATCH | cycles | 11.767/11.767/11.767 | 11.767/11.767/11.767 | 1.000 | 11.767 | 1.000 |
| codegen | int8-int16-promotion | codegen | MATCH | cycles | 5.753/5.771/5.813 | 6.275/6.162/6.275 | 1.091 | 6.276 | 1.000 |
| codegen | loop-early-exit | codegen | MATCH | cycles | 1.721/1.721/1.723 | 1.730/1.730/1.732 | 1.006 | 1.724 | 1.004 |
| codegen | math-transcendentals | rtl | MATCH | cycles | 11.315/11.298/11.361 | 8.574/8.609/8.659 | 0.758 | 8.445 | 1.015 |
| codegen | matrix-double-16 | codegen | MATCH | cycles | 4.155/4.150/4.211 | 3.840/3.839/3.844 | 0.924 | 3.787 | 1.014 |
| codegen | minmax-double | codegen+rtl | MATCH | cycles | 5.755/5.766/5.792 | 2.081/2.078/2.084 | 0.362 | 2.081 | 1.000 |
| codegen | minmax-double-special | codegen+rtl | MATCH | cycles | 4.103/4.101/4.103 | 3.268/3.273/3.285 | 0.796 | 3.029 | 1.079 |
| codegen | minmax-int | codegen+rtl | MATCH | cycles | 1.771/1.777/1.789 | 1.589/1.589/1.589 | 0.897 | 1.589 | 1.000 |
| codegen | move-4k | rtl | MATCH | cycles | 0.031/0.031/0.032 | 0.025/0.025/0.025 | 0.805 | 0.025 | 1.000 |
| codegen | mul-lea | codegen | MATCH | cycles | 0.802/0.802/0.802 | 0.839/0.840/0.841 | 1.047 | 0.843 | 0.995 |
| codegen | packed-odd-sizes | codegen | MATCH | cycles | 0.806/0.808/0.811 | 0.812/0.812/0.815 | 1.007 | 0.808 | 1.004 |
| codegen | pointer-alias-update | codegen+memory | MATCH | cycles | 1.662/1.658/1.662 | 1.659/1.659/1.659 | 0.998 | 1.659 | 1.000 |
| codegen | pointer-chase | codegen+memory | MATCH | cycles | 9.618/9.623/9.640 | 9.663/9.670/9.692 | 1.005 | 9.624 | 1.004 |
| codegen | record-aligned | codegen | MATCH | cycles | 3.222/3.222/3.222 | 3.023/3.027/3.040 | 0.938 | 3.034 | 0.997 |
| codegen | record-packed | codegen | MATCH | cycles | 4.115/4.136/4.175 | 4.545/4.568/4.631 | 1.105 | 4.545 | 1.000 |
| codegen | recursion-tree-8 | codegen | MATCH | cycles | 4.509/4.515/4.546 | 4.533/4.533/4.534 | 1.005 | 4.535 | 1.000 |
| codegen | scan-dram | codegen+memory | MATCH | cycles | 1.119/1.121/1.133 | 1.122/1.120/1.136 | 1.002 | 1.108 | 1.013 |
| codegen | scan-l1 | codegen+memory | MATCH | cycles | 0.792/0.793/0.796 | 0.795/0.795/0.795 | 1.004 | 0.792 | 1.004 |
| codegen | scan-l2 | codegen+memory | MATCH | cycles | 0.790/0.794/0.810 | 0.794/0.793/0.794 | 1.005 | 0.794 | 1.000 |
| codegen | scan-llc | codegen+memory | MATCH | cycles | 0.796/0.795/0.799 | 0.796/0.796/0.796 | 0.999 | 0.796 | 1.000 |
| codegen | scan-random | codegen+memory | MATCH | cycles | 2.561/2.635/2.773 | 2.310/2.358/2.468 | 0.902 | 2.554 | 0.905 |
| codegen | scan-strided | codegen+memory | MATCH | cycles | 2.122/2.146/2.244 | 2.107/2.177/2.551 | 0.993 | 2.105 | 1.001 |
| codegen | single-mixed | codegen | MATCH | cycles | 6.281/6.281/6.281 | 6.283/6.283/6.283 | 1.000 | 6.273 | 1.002 |
| codegen | try-finally-normal | compiler+rtl | MATCH | cycles | 3.566/3.556/3.566 | 4.916/4.918/4.941 | 1.379 | 4.850 | 1.014 |
| codegen | uint32-div-const | codegen | MATCH | cycles | 1.762/1.762/1.762 | 1.537/1.540/1.545 | 0.872 | 1.535 | 1.001 |
| codegen | uint64-div-constant | codegen | MATCH | cycles | 2.436/2.434/2.448 | 2.046/2.054/2.068 | 0.840 | 2.046 | 1.000 |
| codegen | uint64-div-runtime | codegen | MATCH | cycles | 7.038/7.038/7.038 | 7.038/7.038/7.038 | 1.000 | 7.038 | 1.000 |
| codegen | uint64-mixed | codegen | MATCH | cycles | 6.275/6.276/6.282 | 4.707/4.707/4.707 | 0.750 | 4.707 | 1.000 |
| dictionary | string-u64-build-grow-100 | rtl+mm | MATCH | cycles | 434.150/433.453/434.275 | 437.712/441.940/449.816 | 1.008 | 440.288 | 0.994 |
| dictionary | string-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 675.459/672.198/683.240 | 426.198/426.531/430.825 | 0.631 | 389.253 | 1.095 |
| dictionary | string-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 266.489/267.002/268.816 | 315.897/314.544/318.646 | 1.185 | 311.086 | 1.015 |
| dictionary | string-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 367.802/366.711/369.132 | 315.258/318.532/333.583 | 0.857 | 189.126 | 1.667 |
| dictionary | string-u64-churn-100 | rtl+mm | MATCH | cycles | 184.990/185.208/185.771 | 103.139/103.322/103.810 | 0.558 | 101.773 | 1.013 |
| dictionary | string-u64-churn-10000 | rtl+mm | MATCH | cycles | 212.439/212.708/214.016 | 184.813/185.538/186.808 | 0.870 | 171.940 | 1.075 |
| dictionary | string-u64-lookup-mixed-100 | rtl | MATCH | cycles | 141.847/141.972/142.809 | 40.403/40.399/40.522 | 0.285 | 39.323 | 1.027 |
| dictionary | string-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 154.266/156.065/160.208 | 73.715/74.084/75.107 | 0.478 | 70.181 | 1.050 |
| dictionary | u64-string-build-grow-100 | rtl+mm | MATCH | cycles | 327.197/328.290/330.111 | 431.065/429.404/432.031 | 1.317 | 434.625 | 0.992 |
| dictionary | u64-string-build-grow-10000 | rtl+mm | MATCH | cycles | 560.956/575.070/606.347 | 415.701/414.482/426.797 | 0.741 | 377.882 | 1.100 |
| dictionary | u64-string-build-reserved-100 | rtl+mm | MATCH | cycles | 175.728/175.310/175.757 | 307.384/303.969/312.225 | 1.749 | 317.661 | 0.968 |
| dictionary | u64-string-build-reserved-10000 | rtl+mm | MATCH | cycles | 273.419/273.025/283.176 | 304.846/302.811/312.417 | 1.115 | 180.044 | 1.693 |
| dictionary | u64-string-churn-100 | rtl+mm | MATCH | cycles | 85.766/86.115/87.974 | 93.767/93.339/94.149 | 1.093 | 92.521 | 1.013 |
| dictionary | u64-string-churn-10000 | rtl+mm | MATCH | cycles | 111.910/111.533/112.233 | 155.496/155.903/156.484 | 1.389 | 150.328 | 1.034 |
| dictionary | u64-string-lookup-halfload-10000 | rtl | MATCH | cycles | 68.590/68.628/68.894 | 52.174/52.345/52.526 | 0.761 | 51.272 | 1.018 |
| dictionary | u64-string-lookup-hit-10000 | rtl | MATCH | cycles | 66.652/66.440/66.665 | 62.073/61.806/62.105 | 0.931 | 59.305 | 1.047 |
| dictionary | u64-string-lookup-miss-10000 | rtl | MATCH | cycles | 67.171/67.171/67.817 | 73.232/73.344/74.543 | 1.090 | 68.026 | 1.077 |
| dictionary | u64-string-lookup-mixed-100 | rtl | MATCH | cycles | 55.566/55.485/55.566 | 37.383/37.486/38.063 | 0.673 | 36.907 | 1.013 |
| dictionary | u64-string-lookup-mixed-10000 | rtl | MATCH | cycles | 68.733/68.566/69.103 | 68.637/68.750/69.445 | 0.999 | 65.189 | 1.053 |
| dictionary | u64-u64-build-grow-100 | rtl+mm | MATCH | cycles | 126.283/126.053/126.715 | 95.295/95.605/96.389 | 0.755 | 95.103 | 1.002 |
| dictionary | u64-u64-build-grow-10000 | rtl+mm | MATCH | cycles | 249.061/247.467/250.040 | 139.840/139.767/140.600 | 0.561 | 116.242 | 1.203 |
| dictionary | u64-u64-build-reserved-100 | rtl+mm | MATCH | cycles | 89.423/89.510/89.769 | 79.953/80.179/80.901 | 0.894 | 81.625 | 0.980 |
| dictionary | u64-u64-build-reserved-10000 | rtl+mm | MATCH | cycles | 143.431/145.548/148.770 | 192.299/196.669/208.373 | 1.341 | 77.834 | 2.471 |
| dictionary | u64-u64-churn-100 | rtl | MATCH | cycles | 62.689/64.053/71.310 | 68.475/68.619/68.838 | 1.092 | 61.292 | 1.117 |
| dictionary | u64-u64-churn-10000 | rtl | MATCH | cycles | 78.546/78.451/78.546 | 105.987/106.893/107.863 | 1.349 | 101.422 | 1.045 |
| dictionary | u64-u64-lookup-halfload-10000 | rtl | MATCH | cycles | 62.349/62.548/62.871 | 45.906/45.864/46.018 | 0.736 | 44.643 | 1.028 |
| dictionary | u64-u64-lookup-hit-10000 | rtl | MATCH | cycles | 55.352/55.544/55.841 | 50.146/50.197/51.100 | 0.906 | 47.471 | 1.056 |
| dictionary | u64-u64-lookup-miss-10000 | rtl | MATCH | cycles | 67.596/67.487/67.646 | 68.289/68.605/69.451 | 1.010 | 62.947 | 1.085 |
| dictionary | u64-u64-lookup-mixed-100 | rtl | MATCH | cycles | 50.684/50.677/50.825 | 33.554/33.589/33.767 | 0.662 | 31.679 | 1.059 |
| dictionary | u64-u64-lookup-mixed-10000 | rtl | MATCH | cycles | 62.653/62.665/63.080 | 61.151/61.355/61.845 | 0.976 | 57.461 | 1.064 |
| dispatch | class-name-rtti | rtl | MATCH | cycles | 35.987/35.931/36.119 | 14.556/14.589/14.643 | 0.404 | 12.292 | 1.184 |
| dispatch | function-pointer | codegen | MATCH | cycles | 4.806/4.806/4.806 | 4.806/4.806/4.806 | 1.000 | 4.806 | 1.000 |
| dispatch | generic-integer | codegen | MATCH | cycles | 5.519/5.532/5.549 | 4.731/4.742/4.760 | 0.857 | 4.731 | 1.000 |
| dispatch | generic-record | codegen | MATCH | cycles | 5.548/5.553/5.578 | 7.058/7.082/7.133 | 1.272 | 7.132 | 0.990 |
| dispatch | interface-monomorphic | compiler+rtl | MATCH | cycles | 7.247/7.256/7.285 | 5.666/5.675/5.697 | 0.782 | 5.717 | 0.991 |
| dispatch | interface-polymorphic | compiler+rtl | MATCH | cycles | 26.998/26.974/27.092 | 27.578/27.574/27.627 | 1.021 | 27.118 | 1.017 |
| dispatch | list-enumerator | rtl+mm | MATCH | cycles | 9.006/8.933/9.068 | 5.426/5.490/5.641 | 0.602 | 5.501 | 0.986 |
| dispatch | list-index | rtl+mm | MATCH | cycles | 2.432/2.438/2.446 | 2.441/2.439/2.443 | 1.004 | 2.446 | 0.998 |
| dispatch | managed-object-create-free | rtl+mm | MATCH | cycles | 470.802/469.933/477.769 | 272.156/278.661/311.528 | 0.578 | 299.965 | 0.907 |
| dispatch | object-create-free | rtl+mm | MATCH | cycles | 118.551/118.568/120.801 | 102.789/102.751/103.538 | 0.867 | 127.512 | 0.806 |
| dispatch | raise-catch | compiler+rtl+mm | MATCH | cycles | 3618.192/3632.718/3665.366 | 5702.005/5688.559/5703.000 | 1.576 | 5712.633 | 0.998 |
| dispatch | static-method | codegen | MATCH | cycles | 5.607/5.620/5.637 | 5.578/5.571/5.674 | 0.995 | 5.549 | 1.005 |
| dispatch | try-except-no-raise | compiler+rtl | MATCH | cycles | 4.756/4.746/4.761 | 4.731/4.735/4.756 | 0.995 | 4.731 | 1.000 |
| dispatch | virtual-monomorphic | codegen | MATCH | cycles | 5.705/5.708/5.787 | 5.637/5.637/5.637 | 0.988 | 5.675 | 0.993 |
| dispatch | virtual-polymorphic | codegen | MATCH | cycles | 25.473/25.578/26.407 | 26.895/26.993/27.206 | 1.056 | 28.650 | 0.939 |
| heartbeat | aggregate-100 | codegen+memory | MATCH | cycles | 13.261/13.289/13.330 | 9.609/9.622/9.660 | 0.725 | 9.592 | 1.002 |
| heartbeat | aggregate-1000 | codegen+memory | MATCH | cycles | 14.235/14.331/14.478 | 9.663/9.676/9.721 | 0.679 | 9.651 | 1.001 |
| heartbeat | binary-session-pipeline | codegen+rtl+memory | MATCH | cycles | 237.842/239.018/246.313 | 215.953/218.919/233.372 | 0.908 | 215.768 | 1.001 |
| heartbeat | correlation-32x256 | codegen+math+memory | MATCH | cycles | 3.004/3.007/3.018 | 2.693/2.693/2.706 | 0.896 | 2.692 | 1.000 |
| heartbeat | end-to-end-100 | app | MATCH | cycles | 477.708/476.339/480.983 | 413.020/414.047/415.822 | 0.865 | 415.756 | 0.993 |
| heartbeat | generate-info-format-100 | rtl+mm | MATCH | cycles | 22.384/22.344/22.388 | 16.795/16.956/18.080 | 0.750 | 18.848 | 0.891 |
| heartbeat | generate-info-format-1000 | rtl+mm | MATCH | cycles | 22.922/22.983/23.383 | 17.486/17.813/18.765 | 0.763 | 17.793 | 0.983 |
| heartbeat | generate-info-mormot-100 | mormot-json+mm | MATCH | cycles | 17.181/17.172/17.247 | 12.066/12.069/12.139 | 0.702 | 12.096 | 0.998 |
| heartbeat | generate-info-mormot-1000 | mormot-json+mm | MATCH | cycles | 17.560/17.503/17.609 | 12.368/12.410/12.576 | 0.704 | 12.112 | 1.021 |
| heartbeat | orderbook-delta-4096 | codegen+rtl+memory | MATCH | cycles | 268.973/268.838/269.646 | 240.492/243.086/247.520 | 0.894 | 243.322 | 0.988 |
| heartbeat | orderbook-sweep-4096 | codegen+memory | MATCH | cycles | 57.123/57.160/57.571 | 55.736/55.760/55.891 | 0.976 | 55.874 | 0.998 |
| heartbeat | parse-markets-100 | mormot-json+rtl+mm | MATCH | cycles | 27.598/27.516/27.655 | 23.512/23.512/23.781 | 0.852 | 24.435 | 0.962 |
| heartbeat | parse-markets-1000 | mormot-json+rtl+mm | MATCH | cycles | 21.872/21.961/22.179 | 19.211/19.235/19.327 | 0.878 | 19.306 | 0.995 |
| heartbeat | rank-1000 | rtl+mm | MATCH | cycles | 183.603/183.868/187.055 | 172.705/173.029/177.191 | 0.941 | 174.968 | 0.987 |
| heartbeat | report-top20 | rtl+mm | MATCH | cycles | 3175.405/3177.933/3185.139 | 2715.146/2717.323/2726.732 | 0.855 | 2757.896 | 0.984 |
| heartbeat | sort-int64-4x8192 | rtl+codegen+mm | MATCH | cycles | 158.895/159.018/159.849 | 134.513/134.658/135.298 | 0.847 | 135.310 | 0.994 |
| heartbeat | spectrum-fft-32x1024 | codegen+math | MATCH | cycles | 11.563/11.601/11.707 | 11.352/11.384/11.429 | 0.982 | 11.423 | 0.994 |
| heartbeat | timer-heap-8192 | codegen+memory | MATCH | cycles | 277.572/277.992/279.062 | 147.985/148.162/149.319 | 0.533 | 147.533 | 1.003 |
| heartbeat | trade-scan-100 | codegen+rtl | MATCH | cycles | 465.418/466.506/470.285 | 408.102/406.650/409.142 | 0.877 | 402.715 | 1.013 |
| heartbeat | trade-scan-1000 | codegen+rtl | MATCH | cycles | 479.750/480.052/482.668 | 437.169/435.041/437.189 | 0.911 | 432.951 | 1.010 |
| json | builder-append-prepared-floats-64 | rtl | MATCH | cycles | 28.669/28.777/29.375 | 27.471/27.401/27.523 | 0.958 | 26.666 | 1.030 |
| json | builder-growth-64k | rtl | MATCH | cycles | 0.463/0.496/0.572 | 0.571/0.590/0.712 | 1.232 | 0.611 | 0.934 |
| json | byte-scan-large-4096 | codegen | MATCH | cycles | 4.298/4.282/4.302 | 4.855/4.800/4.870 | 1.130 | 4.564 | 1.064 |
| json | byte-scan-medium-256 | codegen | MATCH | cycles | 4.284/4.294/4.307 | 4.834/4.819/4.920 | 1.128 | 4.556 | 1.061 |
| json | byte-scan-small-16 | codegen | MATCH | cycles | 4.332/4.324/4.346 | 4.704/4.759/4.883 | 1.086 | 4.605 | 1.021 |
| json | generate-64 | rtl | MATCH | cycles | 11800.781/11708.750/11894.792 | 5113.460/5049.117/5119.397 | 0.433 | 5059.386 | 1.011 |
| json | parse-large-custom-double | compiler+rtl | MATCH | cycles | 2335.757/2352.847/2439.014 | 1991.475/1997.777/2064.766 | 0.853 | 2168.765 | 0.918 |
| json | parse-medium-custom-double | compiler+rtl | MATCH | cycles | 2445.013/2447.381/2458.125 | 2059.478/2061.346/2074.971 | 0.842 | 2135.830 | 0.964 |
| json | parse-medium-strtofloat | rtl | MATCH | cycles | 5501.836/5633.203/5802.422 | 4619.375/4730.491/4891.016 | 0.840 | 4663.906 | 0.990 |
| json | parse-small-custom-double | compiler+rtl | MATCH | cycles | 2354.783/2352.532/2370.646 | 2015.272/2026.826/2043.179 | 0.856 | 2093.143 | 0.963 |
| json | pipeline-parse-vwap-format | integrated | MATCH | cycles | 2465.299/2467.738/2472.474 | 2064.395/2065.243/2075.527 | 0.837 | 2145.850 | 0.962 |
| kernels | base64-encode-4096 | application+text | MATCH | cycles | 2.966/2.967/2.969 | 2.736/2.738/2.743 | 0.922 | 2.737 | 1.000 |
| kernels | correlation-128x32 | application | MATCH | cycles | 7.758/7.759/7.761 | 7.731/7.736/7.771 | 0.996 | 7.684 | 1.006 |
| kernels | dijkstra-64 | application | MATCH | cycles | 13.129/13.125/13.176 | 11.515/11.509/11.537 | 0.877 | 11.497 | 1.002 |
| kernels | huffman-lengths-256 | application | MATCH | cycles | 4.724/4.719/4.750 | 3.920/3.926/3.942 | 0.830 | 3.911 | 1.002 |
| kernels | lu-decomposition-32 | application | MATCH | cycles | 1.653/1.654/1.661 | 1.655/1.656/1.661 | 1.001 | 1.705 | 0.971 |
| kernels | monte-carlo-4096 | application | MATCH | cycles | 14.770/14.827/14.932 | 6.276/6.295/6.342 | 0.425 | 6.647 | 0.944 |
| kernels | neural-dense-32x32 | application | MATCH | cycles | 1.686/1.688/1.705 | 1.514/1.513/1.519 | 0.898 | 1.716 | 0.882 |
| kernels | pixel-transform-4096 | application | MATCH | cycles | 4.732/4.729/4.733 | 4.975/4.972/4.975 | 1.051 | 4.949 | 1.005 |
| kernels | prime-sieve-16384 | application | MATCH | cycles | 5.320/5.316/5.345 | 4.007/4.017/4.047 | 0.753 | 4.026 | 0.995 |
| kernels | sparse-matvec-512x8 | application | MATCH | cycles | 1.816/1.814/1.816 | 1.816/1.816/1.816 | 1.000 | 1.806 | 1.006 |
| layout | aligned-read | codegen+memory | MATCH | cycles | 1.904/1.903/1.906 | 0.850/0.849/0.850 | 0.447 | 0.850 | 1.000 |
| layout | aos-all-fields | codegen+memory | MATCH | cycles | 4.785/4.793/4.810 | 4.821/4.839/4.871 | 1.008 | 4.821 | 1.000 |
| layout | aos-one-field | codegen+memory | MATCH | cycles | 1.604/1.611/1.619 | 1.605/1.615/1.634 | 1.000 | 1.598 | 1.004 |
| layout | dynamic-array | codegen+memory | MATCH | cycles | 1.596/1.590/1.597 | 0.840/0.838/0.842 | 0.526 | 0.834 | 1.007 |
| layout | fill-1024 | rtl | MATCH | cycles | 0.116/0.116/0.116 | 0.049/0.049/0.049 | 0.427 | 0.049 | 1.000 |
| layout | fill-16 | rtl | MATCH | cycles | 0.394/0.395/0.398 | 0.099/0.099/0.099 | 0.251 | 0.099 | 1.005 |
| layout | fill-256 | rtl | MATCH | cycles | 0.068/0.068/0.068 | 0.049/0.050/0.050 | 0.723 | 0.050 | 0.990 |
| layout | fill-64 | rtl | MATCH | cycles | 0.136/0.136/0.137 | 0.049/0.049/0.049 | 0.362 | 0.050 | 0.995 |
| layout | indexed-walk | codegen+memory | MATCH | cycles | 0.790/0.790/0.790 | 0.855/0.854/0.856 | 1.081 | 0.857 | 0.997 |
| layout | move-1024 | rtl | MATCH | cycles | 0.033/0.033/0.033 | 0.027/0.027/0.027 | 0.799 | 0.027 | 1.000 |
| layout | move-16 | rtl | MATCH | cycles | 0.297/0.298/0.300 | 0.099/0.099/0.100 | 0.333 | 0.067 | 1.484 |
| layout | move-256 | rtl | MATCH | cycles | 0.047/0.047/0.047 | 0.047/0.047/0.047 | 0.989 | 0.047 | 1.000 |
| layout | move-64 | rtl | MATCH | cycles | 0.099/0.099/0.100 | 0.066/0.067/0.067 | 0.670 | 0.066 | 1.000 |
| layout | packed-record | codegen+memory | MATCH | cycles | 4.557/4.557/4.560 | 4.460/4.461/4.464 | 0.979 | 4.460 | 1.000 |
| layout | pointer-walk | codegen+memory | MATCH | cycles | 0.790/0.790/0.790 | 0.856/0.857/0.862 | 1.083 | 0.851 | 1.006 |
| layout | soa-all-fields | codegen+memory | MATCH | cycles | 4.707/4.708/4.711 | 4.707/4.715/4.732 | 1.000 | 4.707 | 1.000 |
| layout | soa-one-field | codegen+memory | MATCH | cycles | 1.579/1.585/1.595 | 0.908/0.909/0.913 | 0.575 | 0.914 | 0.994 |
| layout | static-array | codegen+memory | MATCH | cycles | 0.786/0.788/0.795 | 0.857/0.855/0.857 | 1.089 | 0.846 | 1.013 |
| layout | unaligned-read | codegen+memory | MATCH | cycles | 1.910/1.915/1.922 | 0.847/0.847/0.850 | 0.444 | 0.843 | 1.005 |
| layout | variant-record | codegen+memory | MATCH | cycles | 6.048/6.039/6.048 | 3.189/3.189/3.189 | 0.527 | 2.940 | 1.085 |
| local-pressure | empty | codegen | MATCH | cycles | 4.707/4.757/4.832 | 3.942/3.975/4.026 | 0.838 | 3.943 | 1.000 |
| local-pressure | unused-buffers-100 | codegen+managed | MATCH | cycles | 378.492/378.983/382.924 | 3.963/3.960/3.967 | 0.010 | 3.963 | 1.000 |
| local-pressure | unused-mixed-300 | codegen+managed | MATCH | cycles | 718.538/719.215/722.299 | 3.942/3.951/3.984 | 0.005 | 3.942 | 1.000 |
| local-pressure | unused-plain-100 | codegen | MATCH | cycles | 4.707/4.710/4.731 | 3.942/3.942/3.942 | 0.838 | 3.942 | 1.000 |
| local-pressure | unused-strings-100 | codegen+managed | MATCH | cycles | 149.808/150.040/150.602 | 3.963/3.973/3.984 | 0.026 | 3.963 | 1.000 |
| local-pressure | used-buffers-100 | codegen+managed | MATCH | cycles | 2222.141/2230.960/2275.749 | 1707.358/1707.069/1707.865 | 0.768 | 1691.304 | 1.009 |
| local-pressure | used-mixed-300 | codegen+managed | MATCH | cycles | 3767.397/3823.769/4146.450 | 3477.346/3480.340/3507.009 | 0.923 | 3441.271 | 1.010 |
| local-pressure | used-plain-100 | codegen | MATCH | cycles | 115.125/116.395/123.397 | 111.575/111.733/112.028 | 0.969 | 111.575 | 1.000 |
| local-pressure | used-strings-100 | codegen+managed | MATCH | cycles | 1418.076/1420.704/1433.342 | 1406.245/1402.697/1406.303 | 0.992 | 1394.959 | 1.008 |
| loops | aliased-update | codegen | MATCH | cycles | 3.300/3.300/3.318 | 2.822/2.820/2.836 | 0.855 | 3.064 | 0.921 |
| loops | break-continue | codegen | MATCH | cycles | 1.965/1.964/1.966 | 1.662/1.665/1.672 | 0.846 | 1.665 | 0.998 |
| loops | for-down | codegen | MATCH | cycles | 1.736/1.742/1.755 | 1.633/1.636/1.650 | 0.941 | 1.570 | 1.040 |
| loops | for-up | codegen | MATCH | cycles | 1.645/1.666/1.700 | 1.632/1.633/1.634 | 0.992 | 1.546 | 1.056 |
| loops | histogram-random | codegen+memory | MATCH | cycles | 2.787/2.779/2.814 | 1.655/1.726/1.904 | 0.594 | 1.947 | 0.850 |
| loops | invariant-expression | codegen | MATCH | cycles | 2.084/2.091/2.105 | 1.644/1.646/1.653 | 0.789 | 1.839 | 0.894 |
| loops | loop-try-finally | compiler+rtl | MATCH | cycles | 4.575/4.572/4.598 | 4.088/4.080/4.093 | 0.893 | 4.856 | 0.842 |
| loops | loop-with-call | codegen | MATCH | cycles | 5.520/5.508/5.520 | 5.492/5.491/5.492 | 0.995 | 5.492 | 1.000 |
| loops | manual-copy-8192 | codegen+memory | MATCH | cycles | 0.809/0.808/0.810 | 0.795/0.795/0.799 | 0.982 | 0.794 | 1.000 |
| loops | nested-column-major | codegen+memory | MATCH | cycles | 1.627/1.625/1.636 | 1.585/1.587/1.593 | 0.974 | 1.585 | 1.000 |
| loops | nested-row-major | codegen+memory | MATCH | cycles | 1.585/1.585/1.585 | 0.837/0.837/0.838 | 0.529 | 1.327 | 0.631 |
| loops | nonaliased-update | codegen | MATCH | cycles | 3.298/3.301/3.316 | 3.328/3.367/3.533 | 1.009 | 3.552 | 0.937 |
| loops | prefix-dependency | codegen+memory | MATCH | cycles | 1.664/1.669/1.679 | 1.650/1.650/1.658 | 0.991 | 1.641 | 1.005 |
| loops | reduction-four-lanes | codegen | MATCH | cycles | 0.921/0.923/0.931 | 0.666/0.668/0.673 | 0.723 | 0.791 | 0.843 |
| loops | reduction-sum | codegen | MATCH | cycles | 2.353/2.354/2.356 | 2.353/2.353/2.354 | 1.000 | 2.354 | 1.000 |
| loops | repeat-runtime | codegen | MATCH | cycles | 1.666/1.664/1.667 | 1.705/1.703/1.705 | 1.023 | 1.674 | 1.019 |
| loops | strength-multiply-index | codegen | MATCH | cycles | 1.647/1.649/1.656 | 1.624/1.628/1.633 | 0.986 | 1.629 | 0.997 |
| loops | vector-add-8192 | codegen+memory | MATCH | cycles | 1.604/1.608/1.613 | 1.153/1.154/1.159 | 0.719 | 1.153 | 1.000 |
| loops | vector-dot-8192 | codegen+memory | MATCH | cycles | 2.354/2.354/2.354 | 2.354/2.354/2.354 | 1.000 | 2.354 | 1.000 |
| loops | while-runtime | codegen | MATCH | cycles | 1.666/1.666/1.666 | 1.689/1.691/1.696 | 1.014 | 1.689 | 1.000 |
| managed | closure-create-invoke | compiler+rtl | MATCH | cycles | 227.667/228.903/232.578 | 144.332/146.958/150.013 | 0.634 | 149.987 | 0.962 |
| managed | dynamic-array-assign | rtl | MATCH | cycles | 16.003/15.888/16.042 | 13.994/13.876/14.008 | 0.874 | 13.748 | 1.018 |
| managed | dynamic-array-deep-copy | rtl | MATCH | cycles | 57.743/58.808/63.486 | 64.394/64.619/66.095 | 1.115 | 51.686 | 1.246 |
| managed | ignored-interface-result | compiler+rtl | MATCH | cycles | 25.765/25.305/25.817 | 23.782/23.729/23.786 | 0.923 | 23.081 | 1.030 |
| managed | ignored-string-result | compiler+rtl | MATCH | cycles | 19.225/19.206/19.264 | 15.793/15.804/15.877 | 0.821 | 15.631 | 1.010 |
| managed | interface-copy-call | compiler+rtl | MATCH | cycles | 20.315/20.298/20.341 | 20.611/20.580/20.611 | 1.015 | 54.818 | 0.376 |
| managed | managed-early-exit | compiler+rtl | MATCH | cycles | 75.050/75.412/77.799 | 69.625/71.466/77.704 | 0.928 | 65.671 | 1.060 |
| managed | managed-exception-cleanup | compiler+rtl | MATCH | cycles | 573.142/569.683/579.824 | 855.075/843.289/855.150 | 1.492 | 840.890 | 1.017 |
| managed | managed-record-return | compiler+rtl | MATCH | cycles | 229.960/226.759/231.213 | 116.235/113.799/116.406 | 0.505 | 123.319 | 0.943 |
| managed | out-string-forwarding | compiler+rtl | MATCH | cycles | 24.655/24.724/24.876 | 23.614/23.659/24.380 | 0.958 | 22.641 | 1.043 |
| managed | rawbytestring-assign | rtl | MATCH | cycles | 13.253/13.254/13.263 | 13.438/13.439/13.446 | 1.014 | 13.444 | 1.000 |
| managed | rawbytestring-assign-mt | rtl | MATCH | cycles | 13.252/13.255/13.259 | 13.444/13.441/13.452 | 1.015 | 13.450 | 1.000 |
| managed | unicode-assign | rtl | MATCH | cycles | 12.487/12.505/12.549 | 12.618/12.625/12.677 | 1.011 | 12.612 | 1.000 |
| managed | unicode-assign-mt | rtl | MATCH | cycles | 13.242/13.246/13.251 | 13.456/13.460/13.472 | 1.016 | 13.445 | 1.001 |
| managed | unicode-concat | rtl | MATCH | cycles | 87.529/90.137/99.577 | 43.953/43.987/44.076 | 0.502 | 50.554 | 0.869 |
| managed | unicode-return-ppu | compiler+rtl | MATCH | cycles | 13.251/13.258/13.272 | 13.354/13.354/13.359 | 1.008 | 13.426 | 0.995 |
| managed | variant-numeric | rtl | MATCH | cycles | 136.768/137.057/137.493 | 171.801/172.117/172.706 | 1.256 | 176.563 | 0.973 |
| mm | alloc-free-100500 | mm | MATCH | cycles | 52.319/52.318/52.816 | 39.642/39.776/39.972 | 0.758 | 67.202 | 0.590 |
| mm | alloc-free-1024 | mm | MATCH | cycles | 45.558/45.992/46.711 | 65.724/66.443/69.704 | 1.443 | 82.948 | 0.792 |
| mm | alloc-free-16 | mm | MATCH | cycles | 23.601/24.101/25.226 | 27.336/27.582/28.528 | 1.158 | 27.580 | 0.991 |
| mm | alloc-free-16k | mm | MATCH | cycles | 52.488/52.927/56.288 | 39.714/39.721/39.891 | 0.757 | 79.358 | 0.500 |
| mm | alloc-free-17408 | mm | MATCH | cycles | 52.769/53.074/54.798 | 39.925/39.745/39.929 | 0.757 | 79.341 | 0.503 |
| mm | alloc-free-17409 | mm | MATCH | cycles | 52.749/52.731/53.009 | 39.671/39.787/39.925 | 0.752 | 78.918 | 0.503 |
| mm | alloc-free-1m | mm | MATCH | cycles | 28028.519/26167.520/30460.988 | 27684.390/27168.425/29067.564 | 0.988 | 65823.824 | 0.421 |
| mm | alloc-free-256 | mm | MATCH | cycles | 45.830/47.137/55.957 | 66.471/66.067/66.478 | 1.450 | 39.930 | 1.665 |
| mm | alloc-free-2m | mm | MATCH | cycles | 36152.343/36473.622/39560.714 | 34557.240/35885.553/39869.464 | 0.956 | 72751.613 | 0.475 |
| mm | alloc-free-64 | mm | MATCH | cycles | 24.287/24.091/24.287 | 25.362/25.322/25.440 | 1.044 | 27.496 | 0.922 |
| mm | fragmented-mixed | mm | MATCH | cycles | 1036.187/1095.959/1281.758 | 1072.183/1049.652/1166.812 | 1.035 | 1860.107 | 0.576 |
| mm | realloc-grow | mm | MATCH | cycles | 56.222/56.856/59.166 | 59.121/59.490/60.171 | 1.052 | 110.425 | 0.535 |
| mm | realloc-shrink | mm | MATCH | cycles | 30.451/30.692/31.322 | 28.243/29.537/31.307 | 0.927 | 113.226 | 0.249 |
| mm | ring-mixed-16-to-1m | mm | MATCH | cycles | 1913.730/1958.580/2107.441 | 1636.895/1653.965/1728.555 | 0.855 | 4709.922 | 0.348 |
| mm | ring-same-class-96 | mm | MATCH | cycles | 12.740/12.901/13.200 | 13.262/13.232/13.399 | 1.041 | 17.375 | 0.763 |
| mormot-json | docvariant-load-large | mormot-json | MATCH | cycles | 2.692/2.697/2.718 | 1.844/1.847/1.860 | 0.685 | 1.857 | 0.993 |
| mormot-json | docvariant-load-medium | mormot-json | MATCH | cycles | 3.219/3.221/3.233 | 2.274/2.274/2.275 | 0.707 | 2.307 | 0.986 |
| mormot-json | docvariant-load-small | mormot-json | MATCH | cycles | 20.213/20.352/20.875 | 16.253/16.260/16.572 | 0.804 | 16.601 | 0.979 |
| mormot-json | docvariant-roundtrip-large | mormot-json | MATCH | cycles | 3.667/3.675/3.704 | 2.796/2.805/2.822 | 0.762 | 4.395 | 0.636 |
| mormot-json | docvariant-roundtrip-medium | mormot-json | MATCH | cycles | 4.881/4.887/4.907 | 3.806/3.802/3.811 | 0.780 | 3.916 | 0.972 |
| mormot-json | docvariant-roundtrip-small | mormot-json | MATCH | cycles | 41.736/41.734/41.858 | 34.668/34.872/35.396 | 0.831 | 35.421 | 0.979 |
| mormot-json | object-load-large | mormot-json | MATCH | cycles | 0.988/0.989/0.992 | 0.978/0.987/1.002 | 0.990 | 1.827 | 0.535 |
| mormot-json | object-load-medium | mormot-json | MATCH | cycles | 1.264/1.265/1.271 | 1.191/1.191/1.193 | 0.942 | 1.192 | 0.999 |
| mormot-json | object-load-small | mormot-json | MATCH | cycles | 10.729/10.783/10.860 | 8.091/8.105/8.135 | 0.754 | 8.458 | 0.957 |
| mormot-json | object-roundtrip-large | mormot-json | MATCH | cycles | 1.964/1.966/1.980 | 2.072/2.050/2.085 | 1.055 | 5.817 | 0.356 |
| mormot-json | object-roundtrip-medium | mormot-json | MATCH | cycles | 2.930/2.927/2.946 | 2.681/2.688/2.707 | 0.915 | 2.690 | 0.997 |
| mormot-json | object-roundtrip-small | mormot-json | MATCH | cycles | 31.125/31.300/31.916 | 25.805/25.888/26.001 | 0.829 | 25.276 | 1.021 |
| mormot-json | record-load-large | mormot-json | MATCH | cycles | 0.985/0.988/0.994 | 0.981/0.982/0.985 | 0.995 | 0.987 | 0.993 |
| mormot-json | record-load-medium | mormot-json | MATCH | cycles | 1.210/1.212/1.217 | 1.152/1.152/1.153 | 0.952 | 1.173 | 0.982 |
| mormot-json | record-load-small | mormot-json | MATCH | cycles | 9.219/9.229/9.303 | 7.432/7.442/7.508 | 0.806 | 7.258 | 1.024 |
| mormot-json | record-roundtrip-large | mormot-json | MATCH | cycles | 1.956/1.960/1.966 | 1.930/1.931/1.943 | 0.987 | 3.329 | 0.580 |
| mormot-json | record-roundtrip-medium | mormot-json | MATCH | cycles | 2.832/2.836/2.849 | 2.656/2.654/2.657 | 0.938 | 2.691 | 0.987 |
| mormot-json | record-roundtrip-small | mormot-json | MATCH | cycles | 29.429/29.489/29.904 | 25.251/24.987/25.440 | 0.858 | 24.832 | 1.017 |
| move | hot-a0-a0-n0 | rtl+memory | MATCH | tsc | 7.052/7.067/7.088 | 7.052/7.057/7.088 | 1.000 | 7.052 | 1.000 |
| move | hot-a0-a0-n1 | rtl+memory | MATCH | tsc | 7.052/7.084/7.125 | 7.052/7.057/7.088 | 0.995 | 7.835 | 0.900 |
| move | hot-a0-a0-n1023 | rtl+memory | MATCH | tsc | 32.001/34.547/39.268 | 28.954/29.079/29.251 | 0.907 | 28.954 | 1.000 |
| move | hot-a0-a0-n1024 | rtl+memory | MATCH | tsc | 32.001/31.977/32.002 | 27.345/27.345/27.345 | 0.855 | 27.345 | 1.000 |
| move | hot-a0-a0-n1025 | rtl+memory | MATCH | tsc | 32.801/32.801/32.801 | 29.758/29.796/29.920 | 0.907 | 29.758 | 1.000 |
| move | hot-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 69705.062/69204.429/69711.000 | 69933.062/69482.043/69953.844 | 1.007 | 66856.910 | 1.041 |
| move | hot-a0-a0-n127 | rtl+memory | MATCH | tsc | 8.515/8.502/8.526 | 8.709/8.722/8.754 | 1.028 | 9.500 | 0.917 |
| move | hot-a0-a0-n128 | rtl+memory | MATCH | tsc | 8.130/8.116/8.162 | 8.709/8.777/8.992 | 1.077 | 9.500 | 0.917 |
| move | hot-a0-a0-n1280 | rtl+memory | MATCH | tsc | 38.402/39.212/44.476 | 32.975/33.000/33.151 | 0.859 | 32.975 | 1.000 |
| move | hot-a0-a0-n129 | rtl+memory | MATCH | tsc | 9.576/9.582/9.636 | 9.600/9.579/9.600 | 1.003 | 9.600 | 1.000 |
| move | hot-a0-a0-n131072 | rtl+memory | MATCH | tsc | 6733.874/6798.818/6960.566 | 6654.387/6784.301/6986.439 | 1.020 | 6666.276 | 1.022 |
| move | hot-a0-a0-n15 | rtl+memory | MATCH | tsc | 4.802/4.813/4.828 | 4.776/4.774/4.789 | 0.989 | 4.776 | 1.000 |
| move | hot-a0-a0-n1535 | rtl+memory | MATCH | tsc | 44.802/45.213/46.483 | 41.823/41.835/41.909 | 0.933 | 41.823 | 1.000 |
| move | hot-a0-a0-n1536 | rtl+memory | MATCH | tsc | 44.568/45.966/53.654 | 39.410/39.440/39.619 | 0.884 | 39.619 | 1.000 |
| move | hot-a0-a0-n1537 | rtl+memory | MATCH | tsc | 45.602/45.562/45.603 | 42.627/42.627/42.627 | 0.935 | 42.627 | 1.000 |
| move | hot-a0-a0-n16 | rtl+memory | MATCH | tsc | 4.800/4.797/4.826 | 4.775/4.775/4.800 | 0.995 | 4.750 | 1.000 |
| move | hot-a0-a0-n160 | rtl+memory | MATCH | tsc | 8.942/8.921/8.942 | 9.550/9.555/9.586 | 1.074 | 9.550 | 1.000 |
| move | hot-a0-a0-n16384 | rtl+memory | MATCH | tsc | 443.159/442.233/443.349 | 455.512/451.147/458.110 | 1.028 | 455.404 | 0.996 |
| move | hot-a0-a0-n17 | rtl+memory | MATCH | tsc | 4.269/4.269/4.283 | 4.785/4.552/4.845 | 1.121 | 4.785 | 0.880 |
| move | hot-a0-a0-n192 | rtl+memory | MATCH | tsc | 9.807/10.203/10.612 | 9.651/9.629/9.651 | 0.984 | 10.400 | 0.928 |
| move | hot-a0-a0-n2 | rtl+memory | MATCH | tsc | 7.125/7.115/7.125 | 6.301/6.399/7.052 | 0.880 | 7.088 | 0.884 |
| move | hot-a0-a0-n2048 | rtl+memory | MATCH | tsc | 57.301/57.431/57.604 | 52.279/52.278/52.279 | 0.912 | 52.279 | 1.000 |
| move | hot-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 130916.147/131438.630/139346.000 | 127652.618/133196.571/144337.933 | 1.022 | 125416.765 | 1.016 |
| move | hot-a0-a0-n24 | rtl+memory | MATCH | tsc | 4.000/4.004/4.021 | 4.750/4.428/4.786 | 1.188 | 4.750 | 1.000 |
| move | hot-a0-a0-n255 | rtl+memory | MATCH | tsc | 14.226/14.364/17.623 | 17.561/16.015/17.875 | 1.234 | 12.064 | 1.455 |
| move | hot-a0-a0-n256 | rtl+memory | MATCH | tsc | 11.320/11.407/11.618 | 11.938/11.979/12.102 | 1.055 | 11.938 | 0.995 |
| move | hot-a0-a0-n257 | rtl+memory | MATCH | tsc | 12.272/13.203/14.996 | 12.000/12.037/12.128 | 0.983 | 13.600 | 0.887 |
| move | hot-a0-a0-n262144 | rtl+memory | MATCH | tsc | 15298.037/15161.146/15616.127 | 15199.681/15027.381/15296.551 | 0.997 | 14883.799 | 1.005 |
| move | hot-a0-a0-n3 | rtl+memory | MATCH | tsc | 7.125/7.124/7.125 | 6.301/6.287/6.301 | 0.884 | 7.052 | 0.889 |
| move | hot-a0-a0-n3072 | rtl+memory | MATCH | tsc | 82.770/83.827/90.174 | 78.015/78.243/80.427 | 0.943 | 78.017 | 1.000 |
| move | hot-a0-a0-n31 | rtl+memory | MATCH | tsc | 4.115/4.113/4.126 | 4.192/4.373/4.785 | 1.020 | 4.784 | 0.876 |
| move | hot-a0-a0-n32 | rtl+memory | MATCH | tsc | 4.000/4.009/4.021 | 4.000/4.327/4.785 | 1.000 | 4.750 | 1.000 |
| move | hot-a0-a0-n320 | rtl+memory | MATCH | tsc | 12.938/12.868/12.968 | 11.200/11.463/12.837 | 0.870 | 12.734 | 0.880 |
| move | hot-a0-a0-n32768 | rtl+memory | MATCH | tsc | 1655.826/1646.640/1680.538 | 1611.531/1617.624/1630.222 | 0.973 | 1648.407 | 0.982 |
| move | hot-a0-a0-n33 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.367/6.367/6.367 | 1.000 | 6.367 | 1.000 |
| move | hot-a0-a0-n384 | rtl+memory | MATCH | tsc | 14.554/14.554/14.632 | 15.201/15.235/15.281 | 1.044 | 15.281 | 1.000 |
| move | hot-a0-a0-n4 | rtl+memory | MATCH | tsc | 6.334/6.327/6.351 | 6.268/6.296/6.351 | 1.000 | 5.513 | 1.137 |
| move | hot-a0-a0-n4096 | rtl+memory | MATCH | tsc | 131.425/131.426/131.428 | 103.207/103.285/103.755 | 0.785 | 103.208 | 1.000 |
| move | hot-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 312239.214/292767.863/341702.333 | 452284.075/491562.617/573622.667 | 1.166 | 250497.056 | 1.792 |
| move | hot-a0-a0-n48 | rtl+memory | MATCH | tsc | 6.367/6.379/6.400 | 6.367/6.367/6.400 | 1.000 | 6.367 | 1.000 |
| move | hot-a0-a0-n5 | rtl+memory | MATCH | tsc | 6.334/6.329/6.334 | 6.301/6.296/6.333 | 0.995 | 5.542 | 1.137 |
| move | hot-a0-a0-n511 | rtl+memory | MATCH | tsc | 18.495/18.217/18.620 | 17.694/18.127/19.428 | 0.954 | 17.694 | 1.000 |
| move | hot-a0-a0-n512 | rtl+memory | MATCH | tsc | 17.694/17.728/17.837 | 17.327/17.473/17.635 | 0.979 | 17.601 | 0.990 |
| move | hot-a0-a0-n513 | rtl+memory | MATCH | tsc | 18.878/18.967/19.247 | 18.498/18.476/18.538 | 0.980 | 19.302 | 0.958 |
| move | hot-a0-a0-n524288 | rtl+memory | MATCH | tsc | 34761.795/34793.442/35358.712 | 34380.262/34616.279/35201.446 | 0.979 | 34315.259 | 1.002 |
| move | hot-a0-a0-n63 | rtl+memory | MATCH | tsc | 6.367/6.376/6.400 | 6.367/6.376/6.400 | 1.000 | 6.367 | 1.000 |
| move | hot-a0-a0-n64 | rtl+memory | MATCH | tsc | 6.367/6.415/6.601 | 6.367/6.365/6.400 | 1.000 | 6.367 | 1.000 |
| move | hot-a0-a0-n640 | rtl+memory | MATCH | tsc | 21.715/21.781/21.931 | 20.107/20.137/20.214 | 0.926 | 20.107 | 1.000 |
| move | hot-a0-a0-n65 | rtl+memory | MATCH | tsc | 8.785/8.809/8.916 | 6.410/6.428/6.456 | 0.727 | 6.410 | 1.000 |
| move | hot-a0-a0-n65536 | rtl+memory | MATCH | tsc | 3372.483/3481.836/4150.202 | 3355.354/3458.713/4135.931 | 0.992 | 3373.088 | 0.993 |
| move | hot-a0-a0-n7 | rtl+memory | MATCH | tsc | 6.334/6.338/6.367 | 6.268/6.294/6.334 | 0.995 | 5.880 | 1.060 |
| move | hot-a0-a0-n768 | rtl+memory | MATCH | tsc | 24.128/24.128/24.128 | 22.519/22.519/22.520 | 0.933 | 22.520 | 1.000 |
| move | hot-a0-a0-n8 | rtl+memory | MATCH | tsc | 6.334/6.329/6.334 | 6.301/6.294/6.319 | 0.995 | 5.513 | 1.137 |
| move | hot-a0-a0-n80 | rtl+memory | MATCH | tsc | 7.353/7.357/7.379 | 6.400/6.405/6.421 | 0.871 | 6.400 | 1.000 |
| move | hot-a0-a0-n8192 | rtl+memory | MATCH | tsc | 233.990/235.873/245.933 | 206.712/206.711/206.715 | 0.883 | 206.712 | 1.000 |
| move | hot-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 817427.500/877687.056/1074526.000 | 939388.500/891765.000/942827.500 | 1.149 | 647159.000 | 1.305 |
| move | hot-a0-a0-n896 | rtl+memory | MATCH | tsc | 28.954/29.879/35.521 | 24.932/24.951/25.065 | 0.866 | 24.932 | 1.000 |
| move | hot-a0-a0-n9 | rtl+memory | MATCH | tsc | 4.802/4.806/4.828 | 4.776/4.776/4.776 | 0.994 | 4.789 | 0.997 |
| move | hot-a0-a0-n96 | rtl+memory | MATCH | tsc | 7.277/7.282/7.316 | 7.163/7.181/7.200 | 0.989 | 6.400 | 1.119 |
| move | hot-a0-a1-n1024 | rtl+memory | MATCH | tsc | 35.175/35.620/38.069 | 29.925/29.918/29.929 | 0.850 | 29.932 | 1.000 |
| move | hot-a0-a1-n127 | rtl+memory | MATCH | tsc | 8.594/8.630/8.674 | 8.754/8.751/8.777 | 1.011 | 9.500 | 0.921 |
| move | hot-a0-a1-n128 | rtl+memory | MATCH | tsc | 9.717/9.670/9.749 | 8.754/8.751/8.778 | 0.905 | 9.500 | 0.921 |
| move | hot-a0-a1-n129 | rtl+memory | MATCH | tsc | 10.220/10.248/10.383 | 10.871/10.817/10.897 | 1.063 | 11.059 | 0.978 |
| move | hot-a0-a1-n1536 | rtl+memory | MATCH | tsc | 49.276/49.175/49.368 | 42.864/42.804/42.933 | 0.876 | 42.869 | 1.001 |
| move | hot-a0-a1-n16 | rtl+memory | MATCH | tsc | 4.800/4.828/4.851 | 4.801/4.804/4.826 | 0.995 | 4.801 | 1.005 |
| move | hot-a0-a1-n256 | rtl+memory | MATCH | tsc | 13.287/13.870/15.531 | 12.001/12.029/12.069 | 0.908 | 12.067 | 1.000 |
| move | hot-a0-a1-n31 | rtl+memory | MATCH | tsc | 4.150/4.340/4.828 | 4.807/4.729/4.817 | 1.164 | 4.833 | 1.130 |
| move | hot-a0-a1-n32 | rtl+memory | MATCH | tsc | 4.851/4.829/4.851 | 4.800/4.811/4.833 | 0.995 | 4.800 | 1.000 |
| move | hot-a0-a1-n33 | rtl+memory | MATCH | tsc | 9.272/9.336/9.484 | 8.889/8.869/8.889 | 0.959 | 8.919 | 0.997 |
| move | hot-a0-a1-n4096 | rtl+memory | MATCH | tsc | 167.128/167.252/168.846 | 136.947/137.162/137.430 | 0.821 | 137.279 | 1.000 |
| move | hot-a0-a1-n512 | rtl+memory | MATCH | tsc | 20.839/20.933/21.430 | 18.414/18.412/18.601 | 0.884 | 18.508 | 0.990 |
| move | hot-a0-a1-n63 | rtl+memory | MATCH | tsc | 6.400/6.401/6.422 | 6.400/6.400/6.400 | 1.000 | 6.400 | 1.000 |
| move | hot-a0-a1-n64 | rtl+memory | MATCH | tsc | 6.989/6.991/7.031 | 6.885/6.885/6.932 | 0.985 | 6.858 | 1.000 |
| move | hot-a0-a1-n65 | rtl+memory | MATCH | tsc | 9.004/9.028/9.133 | 7.032/7.018/7.033 | 0.783 | 6.955 | 1.007 |
| move | hot-a0-a128-n1024 | rtl+memory | MATCH | tsc | 31.834/31.834/31.834 | 27.345/27.345/27.346 | 0.859 | 27.345 | 1.000 |
| move | hot-a0-a128-n127 | rtl+memory | MATCH | tsc | 10.871/10.100/10.942 | 8.709/8.709/8.709 | 0.801 | 9.500 | 0.917 |
| move | hot-a0-a128-n128 | rtl+memory | MATCH | tsc | 8.043/8.353/9.142 | 8.709/8.709/8.709 | 1.083 | 9.451 | 0.921 |
| move | hot-a0-a128-n129 | rtl+memory | MATCH | tsc | 8.978/8.980/9.026 | 9.500/9.500/9.500 | 1.058 | 9.500 | 1.000 |
| move | hot-a0-a128-n1536 | rtl+memory | MATCH | tsc | 44.568/44.601/44.802 | 39.410/39.440/39.619 | 0.884 | 39.410 | 1.000 |
| move | hot-a0-a128-n16 | rtl+memory | MATCH | tsc | 4.750/4.753/4.767 | 4.750/4.750/4.750 | 1.000 | 4.750 | 1.000 |
| move | hot-a0-a128-n256 | rtl+memory | MATCH | tsc | 11.320/11.311/11.320 | 11.938/11.947/12.000 | 1.055 | 11.938 | 1.000 |
| move | hot-a0-a128-n31 | rtl+memory | MATCH | tsc | 4.783/4.725/4.790 | 4.395/4.556/4.816 | 0.994 | 4.789 | 0.918 |
| move | hot-a0-a128-n32 | rtl+memory | MATCH | tsc | 4.750/4.547/4.800 | 4.750/4.647/4.775 | 1.000 | 4.750 | 1.000 |
| move | hot-a0-a128-n33 | rtl+memory | MATCH | tsc | 6.334/6.334/6.334 | 6.334/6.348/6.367 | 1.000 | 6.334 | 1.002 |
| move | hot-a0-a128-n4096 | rtl+memory | MATCH | tsc | 128.379/128.477/129.051 | 103.208/103.208/103.208 | 0.804 | 103.207 | 1.000 |
| move | hot-a0-a128-n512 | rtl+memory | MATCH | tsc | 17.601/17.638/17.694 | 17.601/17.587/17.648 | 0.995 | 17.601 | 0.997 |
| move | hot-a0-a128-n63 | rtl+memory | MATCH | tsc | 6.367/6.385/6.452 | 6.367/6.384/6.400 | 1.005 | 6.367 | 1.000 |
| move | hot-a0-a128-n64 | rtl+memory | MATCH | tsc | 6.367/6.362/6.367 | 6.367/6.371/6.400 | 1.000 | 6.367 | 1.000 |
| move | hot-a0-a128-n65 | rtl+memory | MATCH | tsc | 8.052/8.057/8.102 | 6.400/6.405/6.434 | 0.795 | 7.200 | 0.889 |
| move | hot-a0-a2048-n1024 | rtl+memory | MATCH | tsc | 31.834/31.829/31.834 | 27.201/27.263/27.346 | 0.854 | 27.345 | 1.000 |
| move | hot-a0-a2048-n127 | rtl+memory | MATCH | tsc | 8.085/8.085/8.086 | 8.709/8.709/8.709 | 1.077 | 9.500 | 0.917 |
| move | hot-a0-a2048-n128 | rtl+memory | MATCH | tsc | 8.043/8.043/8.043 | 8.709/8.693/8.709 | 1.083 | 9.451 | 0.921 |
| move | hot-a0-a2048-n129 | rtl+memory | MATCH | tsc | 8.901/8.907/8.925 | 9.500/9.500/9.500 | 1.067 | 9.500 | 1.000 |
| move | hot-a0-a2048-n1536 | rtl+memory | MATCH | tsc | 44.568/44.468/44.568 | 39.202/39.202/39.202 | 0.880 | 39.202 | 0.995 |
| move | hot-a0-a2048-n16 | rtl+memory | MATCH | tsc | 4.750/4.750/4.750 | 4.750/4.754/4.775 | 1.000 | 4.750 | 1.000 |
| move | hot-a0-a2048-n256 | rtl+memory | MATCH | tsc | 11.260/11.260/11.260 | 11.938/11.933/11.938 | 1.060 | 11.938 | 1.000 |
| move | hot-a0-a2048-n31 | rtl+memory | MATCH | tsc | 4.786/4.607/4.805 | 4.789/4.730/4.807 | 0.998 | 4.789 | 0.999 |
| move | hot-a0-a2048-n32 | rtl+memory | MATCH | tsc | 4.750/4.648/4.775 | 4.750/4.530/4.750 | 1.000 | 4.750 | 1.000 |
| move | hot-a0-a2048-n33 | rtl+memory | MATCH | tsc | 6.334/6.338/6.367 | 6.367/6.357/6.367 | 1.005 | 6.334 | 1.000 |
| move | hot-a0-a2048-n4096 | rtl+memory | MATCH | tsc | 126.018/126.317/126.805 | 103.205/103.284/103.752 | 0.819 | 103.207 | 1.000 |
| move | hot-a0-a2048-n512 | rtl+memory | MATCH | tsc | 17.601/17.601/17.601 | 17.509/17.516/17.601 | 0.995 | 17.601 | 0.995 |
| move | hot-a0-a2048-n63 | rtl+memory | MATCH | tsc | 6.400/6.405/6.434 | 6.400/6.408/6.434 | 1.000 | 6.400 | 1.000 |
| move | hot-a0-a2048-n64 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.367/6.383/6.400 | 1.000 | 6.367 | 1.000 |
| move | hot-a0-a2048-n65 | rtl+memory | MATCH | tsc | 8.271/8.072/8.323 | 6.400/6.436/6.513 | 0.774 | 6.434 | 1.000 |
| move | hot-a1-a0-n1024 | rtl+memory | MATCH | tsc | 32.006/32.070/32.184 | 27.492/27.470/27.492 | 0.854 | 27.491 | 1.000 |
| move | hot-a1-a0-n127 | rtl+memory | MATCH | tsc | 9.248/9.282/9.365 | 8.709/8.725/8.754 | 0.937 | 9.500 | 0.917 |
| move | hot-a1-a0-n128 | rtl+memory | MATCH | tsc | 8.146/8.144/8.190 | 8.754/8.774/8.966 | 1.075 | 9.550 | 0.917 |
| move | hot-a1-a0-n129 | rtl+memory | MATCH | tsc | 10.464/10.736/12.409 | 9.550/9.564/9.600 | 0.913 | 9.550 | 1.000 |
| move | hot-a1-a0-n1536 | rtl+memory | MATCH | tsc | 44.844/45.443/48.860 | 39.626/39.597/39.629 | 0.883 | 39.627 | 1.000 |
| move | hot-a1-a0-n16 | rtl+memory | MATCH | tsc | 4.826/4.821/4.826 | 4.800/4.807/4.842 | 0.995 | 4.800 | 1.000 |
| move | hot-a1-a0-n256 | rtl+memory | MATCH | tsc | 11.901/11.703/12.017 | 12.000/12.015/12.064 | 1.000 | 12.001 | 1.000 |
| move | hot-a1-a0-n31 | rtl+memory | MATCH | tsc | 4.134/4.330/4.831 | 4.810/4.820/4.860 | 1.165 | 4.810 | 1.000 |
| move | hot-a1-a0-n32 | rtl+memory | MATCH | tsc | 4.800/4.800/4.800 | 4.000/4.333/4.775 | 0.995 | 4.775 | 0.838 |
| move | hot-a1-a0-n33 | rtl+memory | MATCH | tsc | 6.401/6.408/6.435 | 6.400/6.406/6.474 | 1.000 | 6.400 | 1.000 |
| move | hot-a1-a0-n4096 | rtl+memory | MATCH | tsc | 131.426/131.858/132.676 | 103.755/103.755/103.757 | 0.789 | 103.755 | 1.000 |
| move | hot-a1-a0-n512 | rtl+memory | MATCH | tsc | 18.204/18.086/18.259 | 17.694/17.687/17.788 | 0.972 | 17.601 | 1.005 |
| move | hot-a1-a0-n63 | rtl+memory | MATCH | tsc | 6.400/6.400/6.400 | 6.400/6.395/6.400 | 1.000 | 6.400 | 1.000 |
| move | hot-a1-a0-n64 | rtl+memory | MATCH | tsc | 6.400/6.405/6.434 | 6.400/6.407/6.434 | 1.000 | 6.400 | 1.000 |
| move | hot-a1-a0-n65 | rtl+memory | MATCH | tsc | 9.232/9.221/9.299 | 6.446/6.446/6.492 | 0.698 | 7.201 | 0.888 |
| move | hot-a1-a1-n1024 | rtl+memory | MATCH | tsc | 32.984/32.930/32.984 | 29.917/29.871/29.917 | 0.907 | 29.917 | 1.000 |
| move | hot-a1-a1-n127 | rtl+memory | MATCH | tsc | 8.229/8.257/8.294 | 8.754/8.735/8.754 | 1.055 | 9.500 | 0.921 |
| move | hot-a1-a1-n128 | rtl+memory | MATCH | tsc | 9.816/9.849/10.067 | 8.789/8.823/8.872 | 0.899 | 9.551 | 0.925 |
| move | hot-a1-a1-n129 | rtl+memory | MATCH | tsc | 9.824/9.833/9.971 | 11.179/11.202/11.526 | 1.137 | 11.204 | 0.991 |
| move | hot-a1-a1-n1536 | rtl+memory | MATCH | tsc | 45.602/45.602/45.603 | 42.627/42.659/42.853 | 0.935 | 42.627 | 1.000 |
| move | hot-a1-a1-n16 | rtl+memory | MATCH | tsc | 4.826/4.830/4.852 | 4.801/4.812/4.826 | 1.000 | 4.801 | 1.000 |
| move | hot-a1-a1-n256 | rtl+memory | MATCH | tsc | 12.423/13.278/15.410 | 12.423/12.435/12.559 | 0.996 | 12.394 | 1.002 |
| move | hot-a1-a1-n31 | rtl+memory | MATCH | tsc | 4.827/4.587/4.827 | 4.806/4.812/4.832 | 0.996 | 4.806 | 1.000 |
| move | hot-a1-a1-n32 | rtl+memory | MATCH | tsc | 4.800/4.802/4.807 | 4.800/4.796/4.800 | 1.000 | 4.800 | 1.000 |
| move | hot-a1-a1-n33 | rtl+memory | MATCH | tsc | 9.467/9.453/9.541 | 8.862/8.866/8.956 | 0.939 | 8.931 | 0.992 |
| move | hot-a1-a1-n4096 | rtl+memory | MATCH | tsc | 163.037/163.037/163.037 | 125.749/125.749/125.751 | 0.771 | 125.749 | 1.000 |
| move | hot-a1-a1-n512 | rtl+memory | MATCH | tsc | 18.964/19.211/19.759 | 18.498/18.433/18.524 | 0.970 | 18.498 | 1.000 |
| move | hot-a1-a1-n63 | rtl+memory | MATCH | tsc | 6.367/6.378/6.412 | 6.367/6.367/6.367 | 1.000 | 6.367 | 1.000 |
| move | hot-a1-a1-n64 | rtl+memory | MATCH | tsc | 7.090/7.099/7.117 | 7.045/7.034/7.068 | 0.989 | 6.929 | 1.013 |
| move | hot-a1-a1-n65 | rtl+memory | MATCH | tsc | 9.039/9.051/9.177 | 6.994/7.045/7.178 | 0.770 | 7.401 | 0.957 |
| move | hot-a128-a0-n1024 | rtl+memory | MATCH | tsc | 31.834/31.834/31.834 | 27.201/27.222/27.345 | 0.854 | 27.345 | 1.000 |
| move | hot-a128-a0-n127 | rtl+memory | MATCH | tsc | 8.342/8.351/8.458 | 8.709/8.730/8.754 | 1.049 | 9.500 | 0.917 |
| move | hot-a128-a0-n128 | rtl+memory | MATCH | tsc | 8.085/8.085/8.086 | 8.709/8.709/8.709 | 1.077 | 9.500 | 0.917 |
| move | hot-a128-a0-n129 | rtl+memory | MATCH | tsc | 9.352/9.445/9.590 | 9.550/9.527/9.550 | 1.008 | 9.550 | 0.995 |
| move | hot-a128-a0-n1536 | rtl+memory | MATCH | tsc | 44.568/44.568/44.568 | 39.410/39.326/39.410 | 0.884 | 39.410 | 1.000 |
| move | hot-a128-a0-n16 | rtl+memory | MATCH | tsc | 4.775/4.777/4.786 | 4.750/4.752/4.763 | 0.995 | 4.750 | 1.000 |
| move | hot-a128-a0-n256 | rtl+memory | MATCH | tsc | 11.320/11.349/11.522 | 11.938/11.938/11.938 | 1.055 | 11.938 | 1.000 |
| move | hot-a128-a0-n31 | rtl+memory | MATCH | tsc | 4.779/4.625/4.807 | 4.789/4.673/4.800 | 1.002 | 4.788 | 1.000 |
| move | hot-a128-a0-n32 | rtl+memory | MATCH | tsc | 4.800/4.691/4.810 | 4.775/4.764/4.775 | 0.995 | 4.775 | 1.000 |
| move | hot-a128-a0-n33 | rtl+memory | MATCH | tsc | 6.367/6.381/6.400 | 6.367/6.361/6.386 | 1.000 | 6.367 | 1.000 |
| move | hot-a128-a0-n4096 | rtl+memory | MATCH | tsc | 130.743/130.744/130.745 | 102.666/102.946/103.208 | 0.785 | 103.208 | 0.995 |
| move | hot-a128-a0-n512 | rtl+memory | MATCH | tsc | 17.694/17.694/17.694 | 17.509/17.522/17.601 | 0.990 | 17.509 | 0.995 |
| move | hot-a128-a0-n63 | rtl+memory | MATCH | tsc | 6.400/6.410/6.434 | 6.400/6.400/6.400 | 1.000 | 6.400 | 1.000 |
| move | hot-a128-a0-n64 | rtl+memory | MATCH | tsc | 6.400/6.395/6.400 | 6.367/6.376/6.400 | 0.995 | 6.367 | 1.000 |
| move | hot-a128-a0-n65 | rtl+memory | MATCH | tsc | 8.652/8.641/8.863 | 6.400/6.410/6.434 | 0.745 | 6.434 | 1.000 |
| move | hot-a15-a31-n1024 | rtl+memory | MATCH | tsc | 33.862/33.826/34.040 | 29.921/29.926/29.943 | 0.883 | 29.920 | 1.000 |
| move | hot-a15-a31-n127 | rtl+memory | MATCH | tsc | 9.806/9.969/10.426 | 8.823/8.840/8.875 | 0.905 | 9.579 | 0.923 |
| move | hot-a15-a31-n128 | rtl+memory | MATCH | tsc | 9.990/9.860/9.997 | 8.794/8.801/8.825 | 0.880 | 9.551 | 0.924 |
| move | hot-a15-a31-n129 | rtl+memory | MATCH | tsc | 8.990/9.006/9.046 | 9.550/9.572/9.600 | 1.063 | 9.600 | 1.000 |
| move | hot-a15-a31-n1536 | rtl+memory | MATCH | tsc | 48.409/48.335/48.606 | 42.647/42.722/42.943 | 0.881 | 42.861 | 0.995 |
| move | hot-a15-a31-n16 | rtl+memory | MATCH | tsc | 4.826/4.826/4.826 | 4.826/4.838/4.941 | 1.000 | 4.800 | 1.000 |
| move | hot-a15-a31-n256 | rtl+memory | MATCH | tsc | 12.803/13.973/15.310 | 12.327/12.395/12.682 | 0.968 | 12.331 | 0.994 |
| move | hot-a15-a31-n31 | rtl+memory | MATCH | tsc | 4.800/4.811/4.826 | 4.800/4.800/4.800 | 1.000 | 4.800 | 1.000 |
| move | hot-a15-a31-n32 | rtl+memory | MATCH | tsc | 4.800/4.800/4.800 | 4.775/4.782/4.801 | 0.995 | 4.775 | 1.000 |
| move | hot-a15-a31-n33 | rtl+memory | MATCH | tsc | 6.367/6.357/6.367 | 6.367/6.374/6.400 | 1.005 | 6.367 | 1.000 |
| move | hot-a15-a31-n4096 | rtl+memory | MATCH | tsc | 167.075/166.665/167.508 | 142.503/142.741/143.282 | 0.856 | 143.000 | 0.997 |
| move | hot-a15-a31-n512 | rtl+memory | MATCH | tsc | 19.956/20.149/20.662 | 18.617/18.591/18.673 | 0.934 | 18.500 | 1.002 |
| move | hot-a15-a31-n63 | rtl+memory | MATCH | tsc | 6.827/6.827/6.864 | 6.990/6.998/7.041 | 1.025 | 6.925 | 1.012 |
| move | hot-a15-a31-n64 | rtl+memory | MATCH | tsc | 6.857/6.852/6.877 | 7.004/7.002/7.024 | 1.024 | 6.937 | 1.006 |
| move | hot-a15-a31-n65 | rtl+memory | MATCH | tsc | 7.883/7.980/8.165 | 6.475/6.473/6.510 | 0.822 | 6.460 | 1.000 |
| move | hot-a2048-a0-n1024 | rtl+memory | MATCH | tsc | 31.834/32.636/37.451 | 27.202/27.233/27.345 | 0.854 | 27.201 | 1.000 |
| move | hot-a2048-a0-n127 | rtl+memory | MATCH | tsc | 8.346/8.356/8.390 | 8.709/8.713/8.729 | 1.046 | 9.500 | 0.917 |
| move | hot-a2048-a0-n128 | rtl+memory | MATCH | tsc | 8.085/8.092/8.129 | 8.709/8.722/8.754 | 1.077 | 9.500 | 0.917 |
| move | hot-a2048-a0-n129 | rtl+memory | MATCH | tsc | 9.489/9.487/9.539 | 9.550/9.555/9.585 | 1.006 | 9.550 | 1.000 |
| move | hot-a2048-a0-n1536 | rtl+memory | MATCH | tsc | 44.568/44.568/44.568 | 39.202/39.231/39.315 | 0.880 | 39.202 | 1.000 |
| move | hot-a2048-a0-n16 | rtl+memory | MATCH | tsc | 4.775/4.784/4.800 | 4.750/4.754/4.775 | 0.995 | 4.750 | 1.000 |
| move | hot-a2048-a0-n256 | rtl+memory | MATCH | tsc | 11.320/11.368/11.515 | 11.938/11.938/11.938 | 1.055 | 11.938 | 1.000 |
| move | hot-a2048-a0-n31 | rtl+memory | MATCH | tsc | 4.805/4.597/4.805 | 4.789/4.736/4.793 | 0.997 | 4.789 | 1.000 |
| move | hot-a2048-a0-n32 | rtl+memory | MATCH | tsc | 4.775/4.517/4.775 | 4.750/4.420/4.750 | 0.995 | 4.750 | 1.000 |
| move | hot-a2048-a0-n33 | rtl+memory | MATCH | tsc | 6.367/6.383/6.400 | 6.367/6.367/6.367 | 1.000 | 6.367 | 1.000 |
| move | hot-a2048-a0-n4096 | rtl+memory | MATCH | tsc | 130.744/131.133/132.112 | 103.205/103.283/103.752 | 0.789 | 103.205 | 1.000 |
| move | hot-a2048-a0-n512 | rtl+memory | MATCH | tsc | 17.694/17.681/17.694 | 17.509/17.501/17.601 | 0.984 | 17.509 | 1.000 |
| move | hot-a2048-a0-n63 | rtl+memory | MATCH | tsc | 6.434/6.615/7.835 | 6.400/6.390/6.425 | 0.995 | 6.400 | 1.000 |
| move | hot-a2048-a0-n64 | rtl+memory | MATCH | tsc | 6.400/6.400/6.400 | 6.367/6.370/6.390 | 0.995 | 6.367 | 1.000 |
| move | hot-a2048-a0-n65 | rtl+memory | MATCH | tsc | 8.684/8.678/8.757 | 6.400/6.405/6.434 | 0.737 | 6.400 | 1.000 |
| move | hot-a31-a15-n1024 | rtl+memory | MATCH | tsc | 33.253/33.276/33.498 | 29.933/29.912/29.933 | 0.899 | 29.947 | 1.000 |
| move | hot-a31-a15-n127 | rtl+memory | MATCH | tsc | 10.286/10.276/10.453 | 8.772/8.786/8.803 | 0.853 | 9.532 | 0.921 |
| move | hot-a31-a15-n128 | rtl+memory | MATCH | tsc | 10.260/10.176/10.263 | 8.771/9.011/9.600 | 0.869 | 9.551 | 0.920 |
| move | hot-a31-a15-n129 | rtl+memory | MATCH | tsc | 8.969/9.009/9.118 | 9.550/9.563/9.601 | 1.065 | 9.666 | 0.993 |
| move | hot-a31-a15-n1536 | rtl+memory | MATCH | tsc | 45.991/45.990/46.128 | 42.637/42.674/42.855 | 0.927 | 42.869 | 0.995 |
| move | hot-a31-a15-n16 | rtl+memory | MATCH | tsc | 4.800/4.800/4.826 | 4.800/4.801/4.809 | 1.000 | 4.800 | 1.000 |
| move | hot-a31-a15-n256 | rtl+memory | MATCH | tsc | 13.433/14.258/15.439 | 12.322/12.353/12.627 | 0.916 | 12.341 | 0.994 |
| move | hot-a31-a15-n31 | rtl+memory | MATCH | tsc | 4.826/4.822/4.826 | 4.800/4.809/4.826 | 0.995 | 4.800 | 1.000 |
| move | hot-a31-a15-n32 | rtl+memory | MATCH | tsc | 4.800/4.817/4.851 | 4.800/4.804/4.826 | 1.000 | 4.800 | 1.000 |
| move | hot-a31-a15-n33 | rtl+memory | MATCH | tsc | 6.400/6.385/6.400 | 6.400/6.400/6.400 | 1.000 | 6.400 | 1.000 |
| move | hot-a31-a15-n4096 | rtl+memory | MATCH | tsc | 163.039/163.595/164.684 | 125.750/125.583/125.979 | 0.766 | 125.611 | 1.001 |
| move | hot-a31-a15-n512 | rtl+memory | MATCH | tsc | 20.084/19.924/20.242 | 18.492/18.495/18.615 | 0.911 | 18.510 | 1.003 |
| move | hot-a31-a15-n63 | rtl+memory | MATCH | tsc | 7.010/7.024/7.127 | 7.055/7.065/7.105 | 1.009 | 6.913 | 1.019 |
| move | hot-a31-a15-n64 | rtl+memory | MATCH | tsc | 6.972/7.014/7.090 | 7.059/7.058/7.067 | 1.013 | 6.886 | 1.026 |
| move | hot-a31-a15-n65 | rtl+memory | MATCH | tsc | 8.037/8.092/8.378 | 6.400/6.415/6.434 | 0.801 | 6.400 | 1.000 |
| move | overlap-backward-d1-n1024 | rtl+memory | MATCH | tsc | 47.858/47.951/48.560 | 48.143/48.164/48.326 | 1.007 | 48.329 | 0.998 |
| move | overlap-backward-d1-n128 | rtl+memory | MATCH | tsc | 25.122/25.894/30.489 | 21.155/21.155/21.155 | 0.842 | 21.920 | 0.965 |
| move | overlap-backward-d1-n1536 | rtl+memory | MATCH | tsc | 61.432/61.432/61.433 | 59.857/59.914/60.562 | 0.974 | 59.858 | 0.993 |
| move | overlap-backward-d1-n2048 | rtl+memory | MATCH | tsc | 73.247/73.331/74.620 | 72.840/73.049/73.316 | 1.006 | 72.852 | 1.006 |
| move | overlap-backward-d1-n256 | rtl+memory | MATCH | tsc | 29.396/29.251/29.487 | 29.147/29.148/29.447 | 1.001 | 29.016 | 0.997 |
| move | overlap-backward-d1-n33 | rtl+memory | MATCH | tsc | 22.723/22.723/22.723 | 22.722/22.722/22.723 | 1.000 | 22.804 | 0.996 |
| move | overlap-backward-d1-n4096 | rtl+memory | MATCH | tsc | 163.821/163.824/164.199 | 144.059/143.799/144.444 | 0.877 | 144.171 | 0.999 |
| move | overlap-backward-d1-n512 | rtl+memory | MATCH | tsc | 36.615/37.380/38.612 | 36.484/36.498/36.688 | 0.986 | 36.718 | 0.997 |
| move | overlap-backward-d1-n64 | rtl+memory | MATCH | tsc | 21.347/21.310/21.354 | 21.292/21.344/21.440 | 1.005 | 21.425 | 0.999 |
| move | overlap-backward-d1-n65 | rtl+memory | MATCH | tsc | 23.506/23.506/23.506 | 21.575/21.605/21.673 | 0.918 | 21.669 | 0.995 |
| move | overlap-backward-d1-n65536 | rtl+memory | MATCH | tsc | 2683.951/2686.458/2692.047 | 2624.341/2627.074/2636.162 | 0.975 | 2629.061 | 0.998 |
| move | overlap-backward-d16-n1024 | rtl+memory | MATCH | tsc | 41.091/41.008/41.193 | 41.022/41.006/41.090 | 0.997 | 40.996 | 1.003 |
| move | overlap-backward-d16-n128 | rtl+memory | MATCH | tsc | 18.021/18.021/18.021 | 16.566/16.550/16.566 | 0.919 | 16.454 | 1.007 |
| move | overlap-backward-d16-n1536 | rtl+memory | MATCH | tsc | 52.770/52.983/53.682 | 52.770/54.420/63.794 | 1.000 | 52.769 | 1.000 |
| move | overlap-backward-d16-n2048 | rtl+memory | MATCH | tsc | 66.232/65.947/66.238 | 65.892/65.992/66.110 | 1.002 | 65.372 | 1.003 |
| move | overlap-backward-d16-n256 | rtl+memory | MATCH | tsc | 21.602/21.638/21.720 | 21.852/22.007/22.680 | 1.012 | 21.846 | 1.001 |
| move | overlap-backward-d16-n33 | rtl+memory | MATCH | tsc | 21.939/21.939/21.939 | 21.939/21.939/21.939 | 1.000 | 21.939 | 1.000 |
| move | overlap-backward-d16-n4096 | rtl+memory | MATCH | tsc | 162.247/162.371/162.723 | 135.468/135.269/135.471 | 0.835 | 134.681 | 1.001 |
| move | overlap-backward-d16-n512 | rtl+memory | MATCH | tsc | 28.775/28.809/29.096 | 28.795/28.757/29.307 | 1.000 | 28.878 | 1.018 |
| move | overlap-backward-d16-n64 | rtl+memory | MATCH | tsc | 6.334/6.343/6.367 | 6.334/6.340/6.367 | 1.000 | 6.334 | 1.000 |
| move | overlap-backward-d16-n65 | rtl+memory | MATCH | tsc | 23.506/23.506/23.506 | 14.887/14.887/14.887 | 0.633 | 14.887 | 1.000 |
| move | overlap-backward-d16-n65536 | rtl+memory | MATCH | tsc | 2679.034/2679.825/2689.212 | 2622.513/2624.891/2633.387 | 0.979 | 2629.276 | 0.995 |
| move | overlap-backward-d63-n1024 | rtl+memory | MATCH | tsc | 34.599/34.662/34.795 | 36.157/36.194/36.322 | 1.047 | 36.731 | 0.986 |
| move | overlap-backward-d63-n128 | rtl+memory | MATCH | tsc | 24.246/24.314/24.715 | 19.588/19.588/19.588 | 0.808 | 19.775 | 0.991 |
| move | overlap-backward-d63-n1536 | rtl+memory | MATCH | tsc | 47.224/47.723/49.016 | 48.713/48.799/49.210 | 1.031 | 49.368 | 0.988 |
| move | overlap-backward-d63-n2048 | rtl+memory | MATCH | tsc | 59.879/59.876/60.030 | 61.347/61.379/61.495 | 1.025 | 62.093 | 0.987 |
| move | overlap-backward-d63-n256 | rtl+memory | MATCH | tsc | 25.471/25.660/26.079 | 25.594/26.053/26.912 | 1.009 | 25.266 | 0.988 |
| move | overlap-backward-d63-n4096 | rtl+memory | MATCH | tsc | 125.089/124.927/125.090 | 127.464/127.370/127.465 | 1.019 | 127.464 | 1.000 |
| move | overlap-backward-d63-n512 | rtl+memory | MATCH | tsc | 28.807/28.689/30.526 | 27.740/27.654/27.985 | 0.916 | 27.837 | 1.002 |
| move | overlap-backward-d63-n64 | rtl+memory | MATCH | tsc | 19.693/19.685/19.693 | 19.745/19.765/19.847 | 1.003 | 19.588 | 1.008 |
| move | overlap-backward-d63-n65 | rtl+memory | MATCH | tsc | 24.289/24.289/24.290 | 21.155/21.155/21.155 | 0.871 | 21.155 | 1.000 |
| move | overlap-backward-d63-n65536 | rtl+memory | MATCH | tsc | 2632.624/2635.427/2645.295 | 2630.251/2627.025/2630.561 | 0.998 | 2630.036 | 0.998 |
| move | overlap-forward-d1-n1024 | rtl+memory | MATCH | tsc | 41.925/41.977/42.291 | 27.347/27.528/27.970 | 0.657 | 27.348 | 1.003 |
| move | overlap-forward-d1-n128 | rtl+memory | MATCH | tsc | 19.252/19.262/19.309 | 17.797/17.797/17.798 | 0.924 | 17.984 | 0.990 |
| move | overlap-forward-d1-n1536 | rtl+memory | MATCH | tsc | 53.558/53.557/53.558 | 39.420/39.401/39.438 | 0.736 | 39.424 | 1.000 |
| move | overlap-forward-d1-n2048 | rtl+memory | MATCH | tsc | 67.040/66.639/67.047 | 52.002/52.002/52.002 | 0.776 | 52.002 | 1.000 |
| move | overlap-forward-d1-n256 | rtl+memory | MATCH | tsc | 24.122/23.709/24.144 | 20.280/20.190/21.091 | 0.842 | 20.303 | 0.999 |
| move | overlap-forward-d1-n33 | rtl+memory | MATCH | tsc | 21.547/21.547/21.547 | 21.547/21.547/21.547 | 1.000 | 21.547 | 1.000 |
| move | overlap-forward-d1-n4096 | rtl+memory | MATCH | tsc | 130.744/131.044/131.427 | 102.667/102.821/103.206 | 0.785 | 103.206 | 1.000 |
| move | overlap-forward-d1-n512 | rtl+memory | MATCH | tsc | 30.051/30.082/30.453 | 22.672/22.621/23.059 | 0.742 | 22.846 | 0.990 |
| move | overlap-forward-d1-n64 | rtl+memory | MATCH | tsc | 16.454/16.483/16.540 | 16.454/16.470/16.540 | 1.000 | 16.480 | 0.999 |
| move | overlap-forward-d1-n65 | rtl+memory | MATCH | tsc | 24.681/24.699/24.809 | 16.460/16.459/16.463 | 0.667 | 16.462 | 1.000 |
| move | overlap-forward-d1-n65536 | rtl+memory | MATCH | tsc | 2618.217/2615.188/2618.270 | 2559.896/2557.991/2564.594 | 0.978 | 2558.503 | 1.000 |
| move | overlap-forward-d16-n1024 | rtl+memory | MATCH | tsc | 42.311/42.160/42.331 | 27.791/27.806/28.052 | 0.656 | 27.442 | 1.012 |
| move | overlap-forward-d16-n128 | rtl+memory | MATCH | tsc | 19.327/19.317/19.338 | 17.797/17.798/17.910 | 0.921 | 18.068 | 0.986 |
| move | overlap-forward-d16-n1536 | rtl+memory | MATCH | tsc | 53.557/53.686/53.899 | 39.424/39.439/39.508 | 0.736 | 39.426 | 1.000 |
| move | overlap-forward-d16-n2048 | rtl+memory | MATCH | tsc | 66.997/67.062/68.245 | 52.002/52.042/52.277 | 0.776 | 52.003 | 1.000 |
| move | overlap-forward-d16-n256 | rtl+memory | MATCH | tsc | 23.833/23.538/23.938 | 20.687/20.327/21.396 | 0.868 | 20.324 | 0.999 |
| move | overlap-forward-d16-n33 | rtl+memory | MATCH | tsc | 22.722/22.722/22.723 | 22.402/22.498/22.722 | 0.986 | 22.330 | 1.000 |
| move | overlap-forward-d16-n4096 | rtl+memory | MATCH | tsc | 131.423/131.326/132.214 | 103.206/103.082/103.208 | 0.785 | 103.205 | 1.000 |
| move | overlap-forward-d16-n512 | rtl+memory | MATCH | tsc | 30.237/30.513/32.133 | 22.461/22.436/22.586 | 0.735 | 22.541 | 0.991 |
| move | overlap-forward-d16-n64 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.367/6.355/6.367 | 1.000 | 6.334 | 1.000 |
| move | overlap-forward-d16-n65 | rtl+memory | MATCH | tsc | 25.912/25.918/25.952 | 16.454/16.454/16.454 | 0.635 | 16.454 | 1.000 |
| move | overlap-forward-d16-n65536 | rtl+memory | MATCH | tsc | 2624.970/2621.191/2633.968 | 2562.650/2563.669/2570.306 | 0.976 | 2560.512 | 1.000 |
| move | overlap-forward-d63-n1024 | rtl+memory | MATCH | tsc | 32.169/32.196/32.235 | 28.023/28.092/28.592 | 0.868 | 28.407 | 0.988 |
| move | overlap-forward-d63-n128 | rtl+memory | MATCH | tsc | 18.544/18.581/18.805 | 18.693/18.645/18.693 | 1.001 | 18.880 | 0.991 |
| move | overlap-forward-d63-n1536 | rtl+memory | MATCH | tsc | 44.802/44.869/45.075 | 39.633/39.637/39.650 | 0.884 | 39.635 | 1.000 |
| move | overlap-forward-d63-n2048 | rtl+memory | MATCH | tsc | 57.682/57.710/57.804 | 52.277/52.278/52.279 | 0.906 | 52.278 | 1.000 |
| move | overlap-forward-d63-n256 | rtl+memory | MATCH | tsc | 20.033/20.950/22.796 | 20.497/20.352/20.895 | 0.999 | 20.550 | 0.996 |
| move | overlap-forward-d63-n4096 | rtl+memory | MATCH | tsc | 131.422/131.662/132.112 | 103.755/103.757/103.759 | 0.790 | 103.753 | 1.000 |
| move | overlap-forward-d63-n512 | rtl+memory | MATCH | tsc | 25.244/25.540/26.409 | 23.057/23.191/24.133 | 0.913 | 23.416 | 0.985 |
| move | overlap-forward-d63-n64 | rtl+memory | MATCH | tsc | 17.594/17.607/17.685 | 17.594/17.607/17.685 | 1.000 | 17.594 | 1.000 |
| move | overlap-forward-d63-n65 | rtl+memory | MATCH | tsc | 24.625/24.625/24.625 | 18.449/18.449/18.449 | 0.749 | 18.449 | 1.000 |
| move | overlap-forward-d63-n65536 | rtl+memory | MATCH | tsc | 2640.121/2638.366/2643.658 | 2616.817/2614.649/2617.092 | 0.989 | 2615.681 | 0.998 |
| move | same-a0-n0 | rtl+memory | MATCH | tsc | 7.052/7.052/7.052 | 7.052/7.052/7.052 | 1.000 | 7.052 | 1.000 |
| move | same-a0-n1 | rtl+memory | MATCH | tsc | 7.052/7.079/7.133 | 7.052/7.057/7.088 | 1.000 | 7.835 | 0.900 |
| move | same-a0-n1048576 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 6.268 | 1.000 |
| move | same-a0-n127 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 6.268 | 1.000 |
| move | same-a0-n128 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 6.268 | 1.000 |
| move | same-a0-n129 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 6.268 | 1.000 |
| move | same-a0-n16 | rtl+memory | MATCH | tsc | 4.750/4.754/4.775 | 4.726/4.726/4.726 | 0.995 | 4.726 | 1.000 |
| move | same-a0-n192 | rtl+memory | MATCH | tsc | 5.485/5.508/5.649 | 6.268/6.273/6.301 | 1.143 | 6.268 | 1.000 |
| move | same-a0-n256 | rtl+memory | MATCH | tsc | 5.513/5.501/5.513 | 6.268/6.278/6.301 | 1.143 | 6.268 | 1.000 |
| move | same-a0-n32 | rtl+memory | MATCH | tsc | 7.052/7.066/7.105 | 7.052/7.052/7.052 | 1.000 | 7.052 | 1.000 |
| move | same-a0-n33 | rtl+memory | MATCH | tsc | 21.939/21.939/21.939 | 6.268/6.268/6.268 | 0.286 | 7.052 | 0.889 |
| move | same-a0-n4096 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.273/6.301 | 1.143 | 6.268 | 1.000 |
| move | same-a0-n64 | rtl+memory | MATCH | tsc | 7.125/7.126/7.126 | 6.268/6.268/6.268 | 0.880 | 7.052 | 0.889 |
| move | same-a0-n65 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 5.485/5.485/5.485 | 1.000 | 5.485 | 1.000 |
| move | same-a0-n80 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 5.485/5.485/5.485 | 1.000 | 5.485 | 1.000 |
| move | same-a0-n96 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 5.485/5.485/5.485 | 1.000 | 5.485 | 1.000 |
| move | same-a0-n97 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 6.268 | 1.000 |
| move | stream-a0-a0-n1024 | rtl+memory | MATCH | tsc | 304.092/302.032/337.700 | 304.932/301.515/311.095 | 1.020 | 304.623 | 1.014 |
| move | stream-a0-a0-n1048575 | rtl+memory | MATCH | tsc | 261828.016/267933.844/288878.078 | 257826.586/265609.949/296017.625 | 0.999 | 259117.992 | 1.011 |
| move | stream-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 293040.711/289693.042/328106.844 | 262948.273/272381.286/297147.531 | 0.949 | 258027.867 | 1.025 |
| move | stream-a0-a0-n131072 | rtl+memory | MATCH | tsc | 38029.335/40348.228/43220.473 | 42953.285/42910.938/52939.418 | 1.001 | 43176.331 | 0.978 |
| move | stream-a0-a0-n1536 | rtl+memory | MATCH | tsc | 455.977/465.302/505.331 | 453.544/458.977/474.138 | 0.997 | 466.359 | 1.007 |
| move | stream-a0-a0-n16384 | rtl+memory | MATCH | tsc | 4349.219/4523.659/4825.921 | 4334.289/4463.457/4996.805 | 1.008 | 4374.713 | 1.016 |
| move | stream-a0-a0-n16777216 | rtl+memory | MATCH | tsc | 4440566.000/4858985.357/5856740.500 | 3037140.500/3034151.393/3443441.250 | 0.624 | 3033164.750 | 1.002 |
| move | stream-a0-a0-n2048 | rtl+memory | MATCH | tsc | 643.951/616.874/644.884 | 588.089/596.231/632.094 | 0.989 | 618.790 | 1.009 |
| move | stream-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 518130.000/572719.474/658576.219 | 591358.078/591957.073/664034.562 | 1.006 | 520070.078 | 1.018 |
| move | stream-a0-a0-n256 | rtl+memory | MATCH | tsc | 67.885/68.405/69.461 | 68.074/68.737/70.201 | 1.002 | 68.122 | 1.010 |
| move | stream-a0-a0-n262144 | rtl+memory | MATCH | tsc | 64814.938/69545.588/79264.734 | 64898.582/70007.515/78730.953 | 1.016 | 70555.461 | 1.000 |
| move | stream-a0-a0-n32768 | rtl+memory | MATCH | tsc | 10112.031/9948.330/10322.112 | 9686.215/10082.642/11071.165 | 0.981 | 10096.992 | 0.897 |
| move | stream-a0-a0-n33554432 | rtl+memory | MATCH | tsc | 5934099.000/5849692.857/6421886.000 | 6360872.250/6044327.500/6364506.000 | 1.093 | 6104429.250 | 1.013 |
| move | stream-a0-a0-n4096 | rtl+memory | MATCH | tsc | 1268.335/1296.457/1465.660 | 1359.279/1271.668/1360.135 | 1.000 | 1127.138 | 1.003 |
| move | stream-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 1287701.250/1185707.723/1298995.562 | 1213367.906/1184087.804/1354232.125 | 1.015 | 1019814.906 | 1.026 |
| move | stream-a0-a0-n512 | rtl+memory | MATCH | tsc | 136.572/136.301/136.713 | 137.966/138.054/142.599 | 1.016 | 136.861 | 1.008 |
| move | stream-a0-a0-n524288 | rtl+memory | MATCH | tsc | 131327.852/132570.592/143675.477 | 132308.801/136830.175/155063.602 | 1.007 | 129351.703 | 1.003 |
| move | stream-a0-a0-n65536 | rtl+memory | MATCH | tsc | 17364.757/18571.702/20930.096 | 17599.548/18462.959/21899.708 | 1.020 | 17550.480 | 1.016 |
| move | stream-a0-a0-n67108864 | rtl+memory | MATCH | tsc | 14705382.500/13187921.714/14929497.000 | 11542804.000/11982195.286/13435926.000 | 0.852 | 11702679.500 | 0.996 |
| move | stream-a0-a0-n786432 | rtl+memory | MATCH | tsc | 239739.541/229375.855/263461.824 | 197273.759/214298.243/248628.188 | 0.970 | 203385.947 | 1.000 |
| move | stream-a0-a0-n8192 | rtl+memory | MATCH | tsc | 2413.394/2421.716/2648.737 | 2335.103/2487.781/2694.588 | 1.023 | 2305.473 | 1.011 |
| move | stream-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 2064246.688/2175904.768/2436811.750 | 2159545.938/2169452.571/2401904.000 | 1.004 | 2069330.375 | 1.044 |
| numeric | bit-boolean | codegen | MATCH | cycles | 9.217/9.220/9.225 | 6.275/6.275/6.276 | 0.681 | 6.275 | 1.000 |
| numeric | double-arithmetic | codegen | MATCH | cycles | 5.488/5.488/5.489 | 5.490/5.491/5.495 | 1.000 | 5.491 | 1.000 |
| numeric | int-double-convert | codegen+rtl | MATCH | cycles | 8.032/8.283/9.832 | 2.982/2.991/3.013 | 0.371 | 3.009 | 0.991 |
| numeric | int32-add-mul | codegen | MATCH | cycles | 3.616/3.614/3.635 | 3.922/3.934/3.963 | 1.085 | 3.923 | 1.000 |
| numeric | int32-div-runtime | codegen | MATCH | cycles | 9.413/9.413/9.414 | 9.414/9.422/9.462 | 1.000 | 9.413 | 1.000 |
| numeric | int64-add-mul | codegen | MATCH | cycles | 3.943/3.947/3.963 | 3.943/3.943/3.943 | 1.000 | 3.942 | 1.000 |
| numeric | int64-div-runtime | codegen | MATCH | cycles | 14.040/14.043/14.052 | 14.040/14.040/14.042 | 1.000 | 14.040 | 1.000 |
| numeric | min-max-mixed | codegen | MATCH | cycles | 3.277/3.270/3.278 | 2.130/2.127/2.132 | 0.650 | 2.060 | 1.034 |
| numeric | overflow-checked | codegen | MATCH | cycles | 3.242/3.242/3.242 | 2.476/2.476/2.476 | 0.764 | 3.242 | 0.764 |
| numeric | overflow-unchecked | codegen | MATCH | cycles | 2.353/2.355/2.366 | 2.353/2.353/2.353 | 1.000 | 2.353 | 1.000 |
| numeric | range-checked-index | codegen | MATCH | cycles | 2.464/2.470/2.477 | 2.482/2.481/2.496 | 1.007 | 1.715 | 1.447 |
| numeric | rotate-mix | codegen | MATCH | cycles | 6.275/6.280/6.309 | 4.706/4.707/4.708 | 0.750 | 4.706 | 1.000 |
| numeric | shift-constant | codegen | MATCH | cycles | 2.378/2.453/2.943 | 2.381/2.378/2.382 | 1.001 | 2.353 | 1.012 |
| numeric | shift-variable | codegen | MATCH | cycles | 2.514/2.518/2.527 | 2.477/2.493/2.515 | 0.985 | 2.489 | 0.995 |
| numeric | single-arithmetic | codegen | MATCH | cycles | 10.138/10.138/10.140 | 10.139/10.146/10.192 | 1.000 | 10.138 | 1.000 |
| numeric | single-double-convert | codegen | MATCH | cycles | 4.855/4.859/4.881 | 2.526/2.527/2.537 | 0.520 | 2.342 | 1.079 |
| numeric | small-set-ops | codegen | MATCH | cycles | 2.805/2.939/3.247 | 0.745/0.748/0.756 | 0.265 | 0.665 | 1.120 |
| numeric | uint32-div-constant | codegen | MATCH | cycles | 5.509/5.513/5.538 | 4.137/4.137/4.137 | 0.751 | 4.116 | 1.005 |
| numeric | uint64-div-constant | codegen | MATCH | cycles | 4.830/4.830/4.830 | 4.284/4.268/4.306 | 0.887 | 4.314 | 0.993 |
| numeric | unchecked-index | codegen | MATCH | cycles | 1.703/1.700/1.703 | 1.679/1.684/1.697 | 0.986 | 1.688 | 0.995 |
| numeric | wide-set-ops | codegen+rtl | MATCH | cycles | 89.921/89.997/90.382 | 30.456/30.489/30.628 | 0.339 | 30.505 | 0.998 |
| rtl | datetime-encode-decode | rtl | MATCH | cycles | 248.582/248.844/250.052 | 141.027/141.022/141.027 | 0.567 | 140.700 | 1.002 |
| rtl | datetime-format | rtl+mm | MATCH | cycles | 2095.983/2097.323/2100.847 | 1305.269/1305.263/1309.054 | 0.623 | 1263.728 | 1.033 |
| rtl | datetime-ms-arith | rtl | MATCH | cycles | 171.132/171.227/171.775 | 33.121/33.095/33.289 | 0.194 | 30.122 | 1.100 |
| rtl | datetime-now | rtl | MATCH | cycles | 194.782/195.700/198.948 | 212.898/213.039/213.480 | 1.093 | 215.260 | 0.989 |
| rtl | dictionary-512 | rtl+mm | MATCH | cycles | 65.323/65.317/66.088 | 54.908/54.767/55.042 | 0.841 | 56.758 | 0.967 |
| rtl | dictionary-add-512 | rtl+mm | MATCH | cycles | 90.108/90.151/90.623 | 75.754/76.026/76.708 | 0.841 | 79.149 | 0.957 |
| rtl | dictionary-add-reserved-512 | rtl+mm | MATCH | cycles | 94.457/94.380/94.581 | 61.308/61.366/61.828 | 0.649 | 63.616 | 0.964 |
| rtl | dictionary-capacity-1024 | rtl+mm | MATCH | cycles | 18089.206/18110.979/18185.280 | 765.494/767.740/772.984 | 0.042 | 1068.695 | 0.716 |
| rtl | dictionary-create-free | rtl+mm | MATCH | cycles | 292.296/293.327/295.614 | 277.313/277.231/280.275 | 0.949 | 285.297 | 0.972 |
| rtl | dictionary-get | rtl | MATCH | cycles | 43.074/43.029/43.317 | 33.376/34.566/36.442 | 0.775 | 33.392 | 1.000 |
| rtl | dictionary-string-get | rtl | MATCH | cycles | 66.807/67.392/68.066 | 40.000/39.933/40.023 | 0.599 | 40.644 | 0.984 |
| rtl | dictionary-update-remove-256 | rtl+mm | MATCH | cycles | 91.792/91.888/92.279 | 91.931/92.047/92.557 | 1.002 | 93.887 | 0.979 |
| rtl | dynamic-array-capacity-512 | rtl+mm | MATCH | cycles | 193.207/194.143/201.601 | 216.465/216.851/221.238 | 1.120 | 186.880 | 1.158 |
| rtl | dynamic-array-copy-512 | rtl+mm | MATCH | cycles | 0.227/0.228/0.236 | 0.288/0.291/0.297 | 1.268 | 0.268 | 1.076 |
| rtl | floattostr-double | rtl+mm | MATCH | cycles | 463.036/460.646/468.326 | 424.864/423.515/425.009 | 0.918 | 433.712 | 0.980 |
| rtl | format-float | rtl+mm | MATCH | cycles | 676.216/678.061/691.705 | 357.184/357.771/359.669 | 0.528 | 363.368 | 0.983 |
| rtl | format-integer | rtl+mm | MATCH | cycles | 225.863/226.256/228.687 | 71.061/71.017/71.117 | 0.315 | 69.988 | 1.015 |
| rtl | format-literal | rtl+mm | MATCH | cycles | 133.834/134.039/134.718 | 109.962/109.943/111.351 | 0.822 | 99.605 | 1.104 |
| rtl | format-mixed | rtl+mm | MATCH | cycles | 826.874/827.753/836.626 | 528.385/528.615/530.021 | 0.639 | 576.700 | 0.916 |
| rtl | format-string | rtl+mm | MATCH | cycles | 147.426/147.693/148.534 | 14.420/14.914/16.313 | 0.098 | 13.694 | 1.053 |
| rtl | generic-list-add-reserved | rtl | MATCH | cycles | 9.980/10.155/10.382 | 9.767/9.749/9.804 | 0.979 | 8.187 | 1.193 |
| rtl | generic-list-binarysearch | rtl | MATCH | cycles | 110.483/110.560/111.287 | 85.629/89.604/98.971 | 0.775 | 92.540 | 0.925 |
| rtl | generic-list-capacity-512 | rtl+mm | MATCH | cycles | 415.851/414.114/417.000 | 390.141/390.955/392.587 | 0.938 | 413.421 | 0.944 |
| rtl | generic-list-create-free | rtl+mm | MATCH | cycles | 213.264/212.758/214.036 | 191.052/191.048/191.065 | 0.896 | 211.246 | 0.904 |
| rtl | generic-list-delete-front-128 | rtl | MATCH | cycles | 37.917/38.319/40.435 | 38.820/38.946/39.148 | 1.024 | 39.460 | 0.984 |
| rtl | generic-list-delete-tail-512 | rtl | MATCH | cycles | 21.127/21.369/22.728 | 24.089/24.121/24.216 | 1.140 | 24.947 | 0.966 |
| rtl | generic-list-enumerator-512 | rtl | MATCH | cycles | 9.390/9.433/9.573 | 5.446/5.447/5.481 | 0.580 | 5.430 | 1.003 |
| rtl | generic-list-growth-512 | rtl+mm | MATCH | cycles | 14.866/14.882/14.978 | 12.223/12.261/12.318 | 0.822 | 12.634 | 0.967 |
| rtl | generic-list-index-512 | rtl | MATCH | cycles | 3.462/3.495/3.726 | 2.469/2.480/2.568 | 0.713 | 2.452 | 1.007 |
| rtl | generic-list-indexof | rtl | MATCH | cycles | 426.939/427.999/431.564 | 123.804/123.750/124.229 | 0.290 | 122.857 | 1.008 |
| rtl | generic-list-remove-128 | rtl | MATCH | cycles | 141.499/141.365/141.510 | 61.676/61.827/63.218 | 0.436 | 61.468 | 1.003 |
| rtl | generic-list-reserved-512 | rtl+mm | MATCH | cycles | 8.864/8.878/8.902 | 8.119/8.120/8.150 | 0.916 | 8.142 | 0.997 |
| rtl | generic-list-sort-512 | rtl | MATCH | cycles | 61607.500/61774.127/62077.222 | 48458.261/48434.206/48483.043 | 0.787 | 44448.824 | 1.090 |
| rtl | helper-compareto | rtl | MATCH | cycles | 37.016/37.022/37.171 | 14.817/14.799/14.900 | 0.400 | 15.596 | 0.950 |
| rtl | helper-endswith-nocase | rtl+mm | MATCH | cycles | 211.041/211.463/218.589 | 13.085/13.128/13.339 | 0.062 | 12.626 | 1.036 |
| rtl | helper-indexof-string | rtl+mm | MATCH | cycles | 2338.512/2333.431/2345.590 | 1820.296/1816.664/1821.501 | 0.778 | 1832.960 | 0.993 |
| rtl | helper-split-16 | rtl+mm | MATCH | cycles | 92.261/92.092/92.271 | 76.902/77.034/77.254 | 0.834 | 77.404 | 0.994 |
| rtl | helper-startswith | rtl | MATCH | cycles | 15.178/15.176/15.179 | 13.070/13.074/13.079 | 0.861 | 12.578 | 1.039 |
| rtl | helper-startswith-nocase | rtl+mm | MATCH | cycles | 277.063/277.991/279.708 | 17.413/17.441/17.508 | 0.063 | 18.200 | 0.957 |
| rtl | inttohex-int64 | rtl+mm | MATCH | cycles | 42.270/42.381/42.588 | 73.382/74.225/80.470 | 1.736 | 76.439 | 0.960 |
| rtl | inttostr-int32 | rtl+mm | MATCH | cycles | 29.620/29.596/29.703 | 30.755/30.982/31.551 | 1.038 | 28.568 | 1.077 |
| rtl | inttostr-int64 | rtl+mm | MATCH | cycles | 32.866/33.135/33.855 | 34.144/34.150/34.176 | 1.039 | 35.612 | 0.959 |
| rtl | lowercase-short | rtl+mm | MATCH | cycles | 29.850/29.870/29.978 | 33.642/33.603/33.670 | 1.127 | 36.048 | 0.933 |
| rtl | memorystream-64k | rtl+mm | MATCH | cycles | 0.055/0.055/0.055 | 0.056/0.056/0.056 | 1.017 | 0.056 | 0.999 |
| rtl | memorystream-write-small | rtl+mm | MATCH | cycles | 15.687/15.723/15.784 | 11.043/11.042/11.045 | 0.704 | 10.986 | 1.005 |
| rtl | object-alloc-zero-free | mm | MATCH | cycles | 26.437/27.057/30.504 | 27.470/27.511/27.626 | 1.039 | 34.443 | 0.798 |
| rtl | object-create-free | rtl+mm | MATCH | cycles | 98.291/98.179/98.297 | 76.098/75.076/76.098 | 0.774 | 80.847 | 0.941 |
| rtl | object-create-virtual-free | rtl+mm | MATCH | cycles | 108.371/107.635/109.155 | 86.408/86.411/86.865 | 0.797 | 89.249 | 0.968 |
| rtl | object-new-freeinstance | rtl+mm | MATCH | cycles | 63.409/63.410/63.416 | 53.899/53.899/53.899 | 0.850 | 58.965 | 0.914 |
| rtl | object-virtual-call | rtl | MATCH | cycles | 4.052/4.061/4.093 | 4.005/4.011/4.026 | 0.988 | 4.005 | 1.000 |
| rtl | queue-512 | rtl+mm | MATCH | cycles | 20.002/20.077/20.644 | 17.865/17.869/17.893 | 0.893 | 16.263 | 1.098 |
| rtl | queue-reserved-512 | rtl | MATCH | cycles | 18.732/18.750/18.876 | 16.685/16.684/16.716 | 0.891 | 15.109 | 1.104 |
| rtl | sametext-short | rtl | MATCH | cycles | 12.751/12.770/12.817 | 13.377/13.445/13.750 | 1.049 | 13.296 | 1.006 |
| rtl | stack-512 | rtl | MATCH | cycles | 16.743/16.868/17.174 | 15.182/15.172/15.187 | 0.907 | 15.896 | 0.955 |
| rtl | str-double-general | rtl | MATCH | cycles | 405.441/406.374/408.770 | 251.551/251.631/252.916 | 0.620 | 249.165 | 1.010 |
| rtl | string-replace-all | rtl+mm | MATCH | cycles | 298.000/299.246/306.199 | 323.581/323.957/325.330 | 1.086 | 335.179 | 0.965 |
| rtl | stringlist-add-128 | rtl+mm | MATCH | cycles | 81.770/82.621/85.784 | 43.183/43.185/43.317 | 0.528 | 43.758 | 0.987 |
| rtl | stringlist-add-sort-128 | rtl+mm | MATCH | cycles | 2423.560/2431.406/2484.844 | 2454.732/2449.098/2455.580 | 1.013 | 2462.578 | 0.997 |
| rtl | stringlist-delimited | rtl+mm | MATCH | cycles | 239.334/237.887/240.274 | 149.616/149.905/154.025 | 0.625 | 124.393 | 1.203 |
| rtl | stringlist-indexof-128 | rtl | MATCH | cycles | 28623.945/28571.038/28979.453 | 29479.688/29604.799/29944.297 | 1.030 | 28882.969 | 1.021 |
| rtl | stringlist-namevalue | rtl | MATCH | cycles | 26399.080/26362.543/26458.046 | 26340.876/26282.902/26403.448 | 0.998 | 26261.023 | 1.003 |
| rtl | stringlist-values | rtl+mm | MATCH | cycles | 7122.713/7121.211/7145.705 | 7136.425/7146.701/7175.647 | 1.002 | 7120.190 | 1.002 |
| rtl | stringstream-build | rtl+mm | MATCH | cycles | 289.360/290.243/293.013 | 281.687/281.420/282.718 | 0.973 | 286.840 | 0.982 |
| rtl | strtofloat-double | rtl+mm | MATCH | cycles | 290.331/295.021/323.200 | 268.053/269.016/271.255 | 0.923 | 273.593 | 0.980 |
| rtl | strtoint-int64 | rtl+mm | MATCH | cycles | 39.244/39.405/39.674 | 39.031/39.199/39.492 | 0.995 | 37.963 | 1.028 |
| rtl | trim-string | rtl+mm | MATCH | cycles | 60.931/61.016/62.124 | 32.100/32.283/32.595 | 0.527 | 35.248 | 0.911 |
| rtl | trystrtoint | rtl | MATCH | cycles | 39.663/39.674/39.696 | 45.007/45.001/45.045 | 1.135 | 44.488 | 1.012 |
| rtl | trystrtoint-edges | rtl | MATCH | cycles | 30.539/30.550/31.240 | 28.118/28.034/28.913 | 0.921 | 27.723 | 1.014 |
| rtl | unicode-comparetext | rtl | MATCH | cycles | 20.368/20.329/20.390 | 20.305/20.521/21.393 | 0.997 | 19.267 | 1.054 |
| rtl | unicode-concat-32 | rtl+mm | MATCH | cycles | 80.566/80.773/81.112 | 65.018/65.317/65.978 | 0.807 | 74.308 | 0.875 |
| rtl | unicode-copy-96 | rtl+mm | MATCH | cycles | 56.674/57.018/57.482 | 25.904/25.945/26.046 | 0.457 | 28.184 | 0.919 |
| rtl | unicode-lowercase-4k | rtl+mm | MATCH | cycles | 1.607/1.604/1.609 | 1.203/1.205/1.209 | 0.748 | 1.209 | 0.995 |
| rtl | unicode-pos-4k | rtl | MATCH | cycles | 4036.501/4402.776/4923.093 | 3242.641/3255.011/3289.581 | 0.803 | 3278.998 | 0.989 |
| rtl | unicode-uppercase-4k | rtl+mm | MATCH | cycles | 1.614/1.610/1.614 | 1.203/1.201/1.203 | 0.745 | 1.203 | 1.000 |
| rtl | utf8-decode-4k | rtl+mm | MATCH | cycles | 0.656/0.655/0.656 | 0.649/0.649/0.652 | 0.990 | 0.721 | 0.900 |
| rtl | utf8-encode-4k | rtl+mm | MATCH | cycles | 0.634/0.634/0.634 | 0.242/0.242/0.242 | 0.381 | 0.270 | 0.895 |
| rtl | utf8-encode-decode-4k | rtl+mm | MATCH | cycles | 1.294/1.297/1.301 | 0.894/0.894/0.898 | 0.690 | 0.991 | 0.902 |
| rtl-collections | array-binarysearch | rtl | MATCH | cycles | 120.580/120.582/122.997 | 124.158/124.360/125.085 | 1.030 | 123.072 | 1.009 |
| rtl-collections | array-integer-copy | rtl+mm | MATCH | cycles | 0.320/0.327/0.369 | 0.304/0.301/0.320 | 0.949 | 0.587 | 0.518 |
| rtl-collections | array-integer-sort | rtl+mm | MATCH | cycles | 47.937/48.092/48.331 | 30.903/31.046/31.297 | 0.645 | 35.359 | 0.874 |
| rtl-collections | array-string-sort | rtl+mm | MATCH | cycles | 206.691/207.336/208.837 | 161.284/161.465/161.905 | 0.780 | 162.979 | 0.990 |
| rtl-collections | dictionary-addorset | rtl | MATCH | cycles | 49.664/49.703/50.022 | 51.019/51.116/51.565 | 1.027 | 46.901 | 1.088 |
| rtl-collections | dictionary-collision-churn | rtl+mm | MATCH | cycles | 325.126/324.712/325.430 | 310.333/310.439/311.072 | 0.955 | 310.185 | 1.000 |
| rtl-collections | dictionary-contains-key | rtl | MATCH | cycles | 32.518/32.688/32.973 | 30.977/30.999/31.021 | 0.953 | 29.614 | 1.046 |
| rtl-collections | dictionary-contains-value | rtl | MATCH | cycles | 3118.537/3122.894/3138.778 | 1486.602/1492.437/1514.310 | 0.477 | 1581.669 | 0.940 |
| rtl-collections | dictionary-keys | rtl | MATCH | cycles | 38.516/38.555/38.835 | 13.802/13.880/14.076 | 0.358 | 13.918 | 0.992 |
| rtl-collections | dictionary-pairs | rtl | MATCH | cycles | 48.553/48.827/49.438 | 17.100/17.117/17.222 | 0.352 | 16.512 | 1.036 |
| rtl-collections | dictionary-string-add | rtl+mm | MATCH | cycles | 241.200/240.638/241.953 | 264.962/264.513/267.842 | 1.099 | 272.428 | 0.973 |
| rtl-collections | dictionary-string-clear | rtl+mm | MATCH | cycles | 317.414/314.554/317.436 | 350.431/358.789/371.650 | 1.104 | 358.744 | 0.977 |
| rtl-collections | dictionary-string-contains | rtl | MATCH | cycles | 57.524/57.442/57.524 | 40.527/40.629/40.882 | 0.705 | 38.816 | 1.044 |
| rtl-collections | dictionary-tryadd | rtl+mm | MATCH | cycles | 56.378/56.556/57.272 | 56.030/55.985/56.477 | 0.994 | 55.706 | 1.006 |
| rtl-collections | dictionary-values | rtl | MATCH | cycles | 38.359/38.460/39.076 | 13.781/13.815/13.914 | 0.359 | 13.838 | 0.996 |
| rtl-collections | list-exchange-reverse | rtl+mm | MATCH | cycles | 18.824/18.885/18.963 | 17.887/17.880/17.915 | 0.950 | 17.982 | 0.995 |
| rtl-collections | list-integer-addrange-4096 | rtl+mm | MATCH | cycles | 0.477/0.479/0.484 | 0.338/0.340/0.344 | 0.708 | 0.449 | 0.753 |
| rtl-collections | list-integer-clear-4096 | rtl+mm | MATCH | cycles | 0.421/0.420/0.422 | 0.269/0.270/0.272 | 0.639 | 0.375 | 0.717 |
| rtl-collections | list-integer-copy-construct | rtl+mm | MATCH | cycles | 2.576/2.579/2.598 | 1.209/1.226/1.313 | 0.469 | 1.586 | 0.762 |
| rtl-collections | list-integer-delete-insert-range-4096 | rtl+mm | MATCH | cycles | 0.205/0.205/0.206 | 0.112/0.113/0.114 | 0.549 | 0.112 | 1.002 |
| rtl-collections | list-integer-empty-create | rtl+mm | MATCH | cycles | 212.811/212.426/213.604 | 195.689/195.473/196.533 | 0.920 | 200.574 | 0.976 |
| rtl-collections | list-integer-exchange | rtl | MATCH | cycles | 5.006/5.016/5.049 | 8.174/8.186/8.217 | 1.633 | 7.443 | 1.098 |
| rtl-collections | list-integer-indexof | rtl | MATCH | cycles | 180.846/181.240/181.836 | 91.207/91.661/92.204 | 0.504 | 91.805 | 0.993 |
| rtl-collections | list-integer-insertrange-list-4096 | rtl+mm | MATCH | cycles | 1.017/1.031/1.062 | 1.101/1.113/1.150 | 1.083 | 1.380 | 0.798 |
| rtl-collections | list-integer-pack-alternating-4096 | rtl+mm | MATCH | cycles | 26.696/26.869/27.939 | 7.083/7.117/7.178 | 0.265 | 7.204 | 0.983 |
| rtl-collections | list-integer-reverse | rtl | MATCH | cycles | 1.776/1.787/1.819 | 2.509/2.511/2.522 | 1.412 | 2.289 | 1.096 |
| rtl-collections | list-integer-sort | rtl+mm | MATCH | cycles | 50.532/50.758/51.623 | 32.962/33.034/33.390 | 0.652 | 36.608 | 0.900 |
| rtl-collections | list-string-add-reserved | rtl+mm | MATCH | cycles | 26.768/26.890/27.574 | 22.812/22.894/23.111 | 0.852 | 20.655 | 1.104 |
| rtl-collections | list-string-addrange-4096 | rtl+mm | MATCH | cycles | 27.248/27.007/27.299 | 24.901/24.989/25.354 | 0.914 | 23.921 | 1.041 |
| rtl-collections | list-string-clear-4096 | rtl+mm | MATCH | cycles | 24.823/25.050/26.521 | 20.753/20.765/20.892 | 0.836 | 20.044 | 1.035 |
| rtl-collections | list-string-enumerate | rtl | MATCH | cycles | 15.406/15.530/15.784 | 14.153/14.170/14.280 | 0.919 | 14.399 | 0.983 |
| rtl-collections | list-string-indexof | rtl | MATCH | cycles | 1146.574/1172.505/1231.395 | 830.862/835.861/842.960 | 0.725 | 830.211 | 1.001 |
| rtl-collections | list-string-insert-delete | rtl+mm | MATCH | cycles | 72.801/73.668/75.970 | 58.557/58.365/58.672 | 0.804 | 59.122 | 0.990 |
| rtl-collections | list-string-insertrange-2048 | rtl+mm | MATCH | cycles | 62.906/63.672/65.738 | 102.042/101.691/103.275 | 1.622 | 97.480 | 1.047 |
| rtl-collections | list-string-read | rtl | MATCH | cycles | 3.230/3.238/3.247 | 2.469/2.467/2.474 | 0.764 | 2.464 | 1.002 |
| rtl-collections | list-string-sort | rtl+mm | MATCH | cycles | 221.803/221.732/226.577 | 178.229/178.167/178.659 | 0.804 | 180.458 | 0.988 |
| rtl-collections | list-string-toarray | rtl+mm | MATCH | cycles | 12.911/12.959/13.056 | 12.781/12.783/12.798 | 0.990 | 13.037 | 0.980 |
| rtl-collections | objectlist-owned-clear | rtl+mm | MATCH | cycles | 141.327/142.144/143.529 | 110.871/113.430/118.639 | 0.784 | 121.546 | 0.912 |
| rtl-collections | queue-enumerate | rtl | MATCH | cycles | 15.204/15.200/15.267 | 5.712/5.709/5.739 | 0.376 | 5.740 | 0.995 |
| rtl-collections | queue-integer-steady | rtl | MATCH | cycles | 0.142/0.142/0.143 | 0.100/0.100/0.100 | 0.701 | 0.118 | 0.845 |
| rtl-collections | queue-record128-steady | rtl | MATCH | cycles | 72.816/73.869/75.999 | 36.940/37.102/37.766 | 0.507 | 39.135 | 0.944 |
| rtl-collections | queue-string-clear | rtl+mm | MATCH | cycles | 61.998/61.983/62.417 | 50.665/50.897/51.538 | 0.817 | 49.272 | 1.028 |
| rtl-collections | queue-string-roundtrip | rtl+mm | MATCH | cycles | 50.473/50.942/52.753 | 25.203/25.206/25.336 | 0.499 | 23.982 | 1.051 |
| rtl-collections | queue-string-steady | rtl | MATCH | cycles | 52.122/51.804/52.152 | 26.112/26.281/27.336 | 0.501 | 25.933 | 1.007 |
| rtl-collections | stack-enumerate | rtl | MATCH | cycles | 9.892/9.942/10.278 | 5.644/5.651/5.677 | 0.571 | 5.775 | 0.977 |
| rtl-collections | stack-integer-roundtrip | rtl | MATCH | cycles | 17.085/17.064/17.093 | 14.605/14.628/14.686 | 0.855 | 14.608 | 1.000 |
| rtl-collections | stack-string-clear | rtl+mm | MATCH | cycles | 64.641/65.104/66.697 | 52.320/52.599/53.126 | 0.809 | 56.777 | 0.921 |
| rtl-collections | stack-string-roundtrip | rtl+mm | MATCH | cycles | 48.605/49.167/51.066 | 22.665/22.655/22.693 | 0.466 | 24.530 | 0.924 |
| threads | cross-thread-free-4 | mm | MATCH | tsc | 44260.282/40864.247/44260.862 | 4398.421/4500.881/4631.320 | 0.100 | 7957.389 | 0.553 |
| threads | false-sharing-4 | memory | MATCH | tsc | 19.072/19.489/20.476 | 22.024/22.139/22.864 | 1.185 | 21.764 | 1.017 |
| threads | independent-cpu-1 | compiler+os | MATCH | tsc | 3.162/3.197/3.374 | 3.168/3.192/3.365 | 0.997 | 3.156 | 1.005 |
| threads | independent-cpu-2 | compiler+os | MATCH | tsc | 1.851/1.866/1.901 | 1.881/1.885/1.909 | 1.016 | 1.594 | 1.199 |
| threads | independent-cpu-4 | compiler+os | MATCH | tsc | 0.938/0.960/1.123 | 0.955/0.980/1.151 | 1.022 | 0.799 | 1.199 |
| threads | independent-cpu-8 | compiler+os | MATCH | tsc | 0.479/0.493/0.582 | 0.489/0.503/0.592 | 1.018 | 0.416 | 1.178 |
| threads | locked-increment-4 | rtl+os | MATCH | tsc | 107.407/106.799/108.064 | 87.859/89.033/90.744 | 0.832 | 96.692 | 0.907 |
| threads | padded-counters-4 | memory | MATCH | tsc | 0.997/1.034/1.201 | 0.428/0.442/0.530 | 0.429 | 0.428 | 1.000 |
| threads | parallel-alloc-free-1 | mm | MATCH | tsc | 66.850/67.122/68.013 | 63.720/64.048/64.828 | 0.957 | 92.023 | 0.694 |
| threads | parallel-alloc-free-2 | mm | MATCH | tsc | 29011.117/29042.729/29149.869 | 60.014/60.855/62.586 | 0.002 | 83.850 | 0.713 |
| threads | parallel-alloc-free-4 | mm | MATCH | tsc | 43989.817/39035.417/44086.095 | 77.005/61.677/80.768 | 0.002 | 42.423 | 1.821 |
| threads | parallel-alloc-free-8 | mm | MATCH | tsc | 29311.267/30263.263/34817.310 | 102.460/107.642/118.038 | 0.003 | 21.304 | 4.810 |
| threads | parallel-alloc-free-96-4 | mm | MATCH | tsc | 29588.729/30760.506/34801.682 | 14.517/15.026/16.519 | 0.000 | 19.862 | 0.730 |
| threads | parallel-alloc-free-96-8 | mm | MATCH | tsc | 21905.338/22251.076/23221.430 | 7.857/7.652/7.860 | 0.000 | 10.025 | 0.777 |
| threads | producer-consumer | rtl+os | MATCH | tsc | 133.118/137.066/153.603 | 154.605/152.692/156.145 | 1.152 | 149.619 | 1.035 |
| threads | shared-read-4 | compiler+memory | MATCH | tsc | 0.992/0.990/0.993 | 0.827/0.827/0.828 | 0.834 | 0.978 | 0.846 |
| threads | thread-start-join-4 | os+rtl | MATCH | tsc | 146499.500/152043.542/169627.250 | 164993.625/165780.202/173653.667 | 1.126 | 162290.083 | 1.016 |
| workloads | binary-trees-depth-10 | codegen+mm | MATCH | cycles | 37.168/37.214/37.358 | 38.702/38.908/39.892 | 1.041 | 43.952 | 0.881 |
| workloads | convolution-256 | codegen+memory | MATCH | cycles | 3.570/3.569/3.570 | 2.805/2.805/2.821 | 0.786 | 2.805 | 1.000 |
| workloads | fannkuch-8 | codegen | MATCH | cycles | 102.733/102.531/102.874 | 98.848/99.415/100.843 | 0.962 | 99.293 | 0.996 |
| workloads | fft-1024 | codegen+math | MATCH | cycles | 11.238/11.301/11.422 | 11.340/11.347/11.371 | 1.009 | 11.147 | 1.017 |
| workloads | floyd-warshall-64 | codegen+memory | MATCH | cycles | 3.649/3.636/3.656 | 3.399/3.379/3.407 | 0.932 | 3.373 | 1.008 |
| workloads | jacobi-2d-128x4 | codegen+memory | MATCH | cycles | 3.097/3.120/3.147 | 3.045/3.055/3.079 | 0.983 | 3.230 | 0.943 |
| workloads | linked-list-insert-sort-512 | codegen+mm | MATCH | cycles | 458.631/457.352/462.465 | 487.143/490.280/494.297 | 1.062 | 463.311 | 1.051 |
| workloads | mandelbrot-128 | codegen | MATCH | cycles | 184.341/184.473/185.292 | 185.848/186.223/187.889 | 1.008 | 185.129 | 1.004 |
| workloads | nbody-5x100 | codegen+math | MATCH | cycles | 19.724/19.444/19.773 | 18.657/18.381/18.664 | 0.946 | 18.664 | 1.000 |
| workloads | numeric-state-machine | codegen | MATCH | cycles | 7.606/7.610/7.706 | 6.598/6.648/6.785 | 0.868 | 6.637 | 0.994 |
| workloads | spectral-norm-128 | codegen | MATCH | cycles | 4.896/4.896/4.896 | 3.915/3.914/3.915 | 0.800 | 3.912 | 1.001 |
| workloads | stream-add | memory | MATCH | cycles | 1.032/1.130/1.290 | 1.010/0.997/1.084 | 0.979 | 0.999 | 1.011 |
| workloads | stream-copy | memory | MATCH | cycles | 0.979/1.004/1.119 | 1.007/1.012/1.096 | 1.028 | 1.006 | 1.001 |
| workloads | stream-scale | memory | MATCH | cycles | 1.109/1.193/1.398 | 1.188/1.210/1.271 | 1.071 | 1.139 | 1.043 |
| workloads | stream-triad | memory | MATCH | cycles | 1.101/1.096/1.135 | 1.186/1.218/1.390 | 1.077 | 1.170 | 1.013 |
