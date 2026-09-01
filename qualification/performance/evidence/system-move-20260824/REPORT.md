# MoonCompiler Pulse result

Mode: `medium`. Baseline: `delphi`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| move | 297 | 0.936 | 124 | 144 | 29 | 0.000 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| memory | 297 | 0.936 | 124 | 144 | 29 |
| rtl | 297 | 0.936 | 124 | 144 | 29 |

## Extreme results

### 15 fastest

- `move/same-a0-n33`: `0.287x`
- `move/overlap-backward-d16-n65`: `0.633x`
- `move/overlap-forward-d16-n65`: `0.635x`
- `move/stream-a0-a0-n16777216`: `0.653x`
- `move/overlap-forward-d1-n1024`: `0.657x`
- `move/overlap-forward-d16-n1024`: `0.658x`
- `move/overlap-forward-d1-n65`: `0.667x`
- `move/hot-a1-a0-n65`: `0.705x`
- `move/hot-a0-a0-n65`: `0.723x`
- `move/overlap-forward-d1-n1536`: `0.735x`
- `move/hot-a2048-a0-n65`: `0.735x`
- `move/overlap-forward-d16-n1536`: `0.736x`
- `move/hot-a0-a0-n8388608`: `0.740x`
- `move/overlap-forward-d16-n512`: `0.747x`
- `move/overlap-forward-d63-n65`: `0.749x`

### 15 slowest

- `move/hot-a1-a1-n129`: `1.148x`
- `move/same-a0-n129`: `1.143x`
- `move/same-a0-n97`: `1.143x`
- `move/same-a0-n128`: `1.143x`
- `move/same-a0-n4096`: `1.143x`
- `move/same-a0-n256`: `1.143x`
- `move/same-a0-n192`: `1.143x`
- `move/same-a0-n127`: `1.143x`
- `move/same-a0-n1048576`: `1.143x`
- `move/stream-a0-a0-n1048576`: `1.099x`
- `move/hot-a0-a2048-n128`: `1.083x`
- `move/hot-a0-a2048-n127`: `1.083x`
- `move/hot-a2048-a0-n128`: `1.077x`
- `move/hot-a0-a128-n128`: `1.077x`
- `move/hot-a128-a0-n128`: `1.077x`
## Diagnostic Move process drift

These cases remain in the table, but the central ratio is calculated from adjacent mirrored processes; drift does not replace a semantic failure.

- `paired/move/hot-a0-a0-n2097152 ratio drift 1.331x`
- `paired/move/hot-a0-a0-n255 ratio drift 2.255x`
- `paired/move/hot-a0-a0-n257 ratio drift 1.359x`
- `paired/move/hot-a0-a0-n320 ratio drift 1.291x`
- `paired/move/hot-a0-a0-n33 ratio drift 1.753x`
- `paired/move/hot-a0-a0-n4194304 ratio drift 1.705x`
- `paired/move/hot-a0-a0-n64 ratio drift 1.251x`
- `paired/move/hot-a0-a0-n640 ratio drift 1.300x`
- `paired/move/hot-a0-a128-n127 ratio drift 1.410x`
- `paired/move/hot-a0-a128-n65 ratio drift 1.540x`
- `paired/move/hot-a128-a0-n65 ratio drift 2.174x`
- `paired/move/hot-a15-a31-n512 ratio drift 1.477x`
- `paired/move/hot-a2048-a0-n512 ratio drift 1.529x`
- `paired/move/hot-a2048-a0-n65 ratio drift 2.122x`
- `paired/move/hot-a31-a15-n512 ratio drift 1.666x`
- `paired/move/overlap-backward-d63-n512 ratio drift 1.815x`
- `paired/move/stream-a0-a0-n1048575 ratio drift 1.363x`
- `paired/move/stream-a0-a0-n16777216 ratio drift 1.393x`
- `paired/move/stream-a0-a0-n262144 ratio drift 1.323x`
- `paired/move/stream-a0-a0-n4194304 ratio drift 1.387x`
- `paired/move/stream-a0-a0-n8388608 ratio drift 1.329x`

## All cases

| Program | Case | Layer | Oracle | Metric | delphi stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| move | hot-a0-a0-n0 | rtl+memory | MATCH | tsc | 7.558/7.561/7.576 | 7.558/7.558/7.558 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a0-n1 | rtl+memory | MATCH | tsc | 7.558/7.558/7.558 | 7.558/7.558/7.558 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a0-n1023 | rtl+memory | MATCH | tsc | 32.001/32.074/32.171 | 29.108/29.058/29.108 | 0.905 | 0.000 | 0.000 |
| move | hot-a0-a0-n1024 | rtl+memory | MATCH | tsc | 32.171/32.140/32.292 | 27.491/27.480/27.557 | 0.855 | 0.000 | 0.000 |
| move | hot-a0-a0-n1025 | rtl+memory | MATCH | tsc | 32.975/32.951/32.976 | 29.917/30.037/31.077 | 0.907 | 0.000 | 0.000 |
| move | hot-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 64161.100/65300.338/68970.576 | 64028.575/63760.221/64616.206 | 1.005 | 0.000 | 0.000 |
| move | hot-a0-a0-n127 | rtl+memory | MATCH | tsc | 8.563/8.571/8.601 | 8.800/8.803/8.818 | 1.028 | 0.000 | 0.000 |
| move | hot-a0-a0-n128 | rtl+memory | MATCH | tsc | 8.130/8.136/8.173 | 8.754/8.754/8.754 | 1.077 | 0.000 | 0.000 |
| move | hot-a0-a0-n1280 | rtl+memory | MATCH | tsc | 38.402/38.402/38.402 | 33.151/33.168/33.270 | 0.863 | 0.000 | 0.000 |
| move | hot-a0-a0-n129 | rtl+memory | MATCH | tsc | 9.547/9.615/9.769 | 9.651/9.627/9.651 | 1.006 | 0.000 | 0.000 |
| move | hot-a0-a0-n131072 | rtl+memory | MATCH | tsc | 6722.328/6750.259/6904.277 | 6719.783/6757.367/6901.216 | 0.997 | 0.000 | 0.000 |
| move | hot-a0-a0-n15 | rtl+memory | MATCH | tsc | 4.828/4.840/4.854 | 4.801/4.806/4.833 | 0.994 | 0.000 | 0.000 |
| move | hot-a0-a0-n1535 | rtl+memory | MATCH | tsc | 44.802/44.886/45.039 | 41.823/41.959/42.186 | 0.933 | 0.000 | 0.000 |
| move | hot-a0-a0-n1536 | rtl+memory | MATCH | tsc | 44.802/44.802/44.803 | 39.619/39.619/39.620 | 0.884 | 0.000 | 0.000 |
| move | hot-a0-a0-n1537 | rtl+memory | MATCH | tsc | 45.603/45.681/45.843 | 42.627/42.659/42.854 | 0.935 | 0.000 | 0.000 |
| move | hot-a0-a0-n16 | rtl+memory | MATCH | tsc | 4.826/4.822/4.826 | 4.800/4.800/4.800 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n160 | rtl+memory | MATCH | tsc | 8.942/8.960/8.990 | 9.550/9.583/9.677 | 1.068 | 0.000 | 0.000 |
| move | hot-a0-a0-n16384 | rtl+memory | MATCH | tsc | 442.683/447.445/460.824 | 458.560/455.820/467.371 | 1.037 | 0.000 | 0.000 |
| move | hot-a0-a0-n17 | rtl+memory | MATCH | tsc | 4.278/4.283/4.298 | 4.254/4.257/4.286 | 0.992 | 0.000 | 0.000 |
| move | hot-a0-a0-n192 | rtl+memory | MATCH | tsc | 10.628/10.261/10.630 | 9.651/9.644/9.651 | 0.908 | 0.000 | 0.000 |
| move | hot-a0-a0-n2 | rtl+memory | MATCH | tsc | 7.558/7.558/7.558 | 6.718/6.718/6.718 | 0.889 | 0.000 | 0.000 |
| move | hot-a0-a0-n2048 | rtl+memory | MATCH | tsc | 57.603/57.603/57.604 | 52.557/52.477/52.557 | 0.912 | 0.000 | 0.000 |
| move | hot-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 124433.546/128197.436/147650.188 | 125374.139/131488.205/150339.176 | 1.032 | 0.000 | 0.000 |
| move | hot-a0-a0-n24 | rtl+memory | MATCH | tsc | 4.043/4.042/4.053 | 4.021/4.021/4.021 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n255 | rtl+memory | MATCH | tsc | 14.165/13.746/14.316 | 12.064/12.085/12.208 | 0.852 | 0.000 | 0.000 |
| move | hot-a0-a0-n256 | rtl+memory | MATCH | tsc | 11.320/11.362/11.554 | 11.938/11.947/12.001 | 1.055 | 0.000 | 0.000 |
| move | hot-a0-a0-n257 | rtl+memory | MATCH | tsc | 14.991/14.069/16.655 | 12.064/12.073/12.128 | 0.805 | 0.000 | 0.000 |
| move | hot-a0-a0-n262144 | rtl+memory | MATCH | tsc | 15915.566/15664.520/17151.967 | 14610.741/14976.679/15860.347 | 0.938 | 0.000 | 0.000 |
| move | hot-a0-a0-n3 | rtl+memory | MATCH | tsc | 7.558/7.558/7.558 | 6.718/6.708/6.718 | 0.889 | 0.000 | 0.000 |
| move | hot-a0-a0-n3072 | rtl+memory | MATCH | tsc | 83.206/83.125/83.206 | 78.016/78.816/80.420 | 0.938 | 0.000 | 0.000 |
| move | hot-a0-a0-n31 | rtl+memory | MATCH | tsc | 4.127/4.125/4.135 | 4.259/4.260/4.275 | 1.032 | 0.000 | 0.000 |
| move | hot-a0-a0-n32 | rtl+memory | MATCH | tsc | 4.043/4.043/4.043 | 4.021/4.021/4.021 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n320 | rtl+memory | MATCH | tsc | 12.984/12.873/13.062 | 11.260/11.285/11.320 | 0.867 | 0.000 | 0.000 |
| move | hot-a0-a0-n32768 | rtl+memory | MATCH | tsc | 1626.373/1636.444/1653.220 | 1636.176/1624.288/1641.341 | 0.994 | 0.000 | 0.000 |
| move | hot-a0-a0-n33 | rtl+memory | MATCH | tsc | 6.435/6.435/6.435 | 6.400/6.419/6.443 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n384 | rtl+memory | MATCH | tsc | 14.632/14.638/14.674 | 15.362/15.328/15.362 | 1.044 | 0.000 | 0.000 |
| move | hot-a0-a0-n4 | rtl+memory | MATCH | tsc | 6.367/6.406/6.573 | 6.334/6.390/6.557 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n4096 | rtl+memory | MATCH | tsc | 132.557/132.651/134.219 | 103.755/104.626/106.584 | 0.783 | 0.000 | 0.000 |
| move | hot-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 249075.222/257917.664/276222.000 | 251315.111/256786.772/267175.625 | 1.024 | 0.000 | 0.000 |
| move | hot-a0-a0-n48 | rtl+memory | MATCH | tsc | 6.400/6.402/6.415 | 6.400/6.400/6.400 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a0-n5 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.334/6.343/6.367 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n511 | rtl+memory | MATCH | tsc | 17.906/18.192/18.650 | 17.509/17.614/17.694 | 0.977 | 0.000 | 0.000 |
| move | hot-a0-a0-n512 | rtl+memory | MATCH | tsc | 17.790/17.776/17.790 | 17.509/17.549/17.694 | 0.984 | 0.000 | 0.000 |
| move | hot-a0-a0-n513 | rtl+memory | MATCH | tsc | 18.849/19.056/19.415 | 18.498/18.509/18.596 | 0.979 | 0.000 | 0.000 |
| move | hot-a0-a0-n524288 | rtl+memory | MATCH | tsc | 31786.732/32300.642/33182.924 | 31945.029/32753.871/36199.156 | 1.006 | 0.000 | 0.000 |
| move | hot-a0-a0-n63 | rtl+memory | MATCH | tsc | 6.434/6.432/6.434 | 6.434/6.430/6.440 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a0-n64 | rtl+memory | MATCH | tsc | 6.400/6.408/6.434 | 6.400/6.405/6.434 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a0-n640 | rtl+memory | MATCH | tsc | 22.111/22.689/27.471 | 20.322/20.387/20.943 | 0.918 | 0.000 | 0.000 |
| move | hot-a0-a0-n65 | rtl+memory | MATCH | tsc | 8.871/9.183/10.869 | 6.443/6.463/6.501 | 0.723 | 0.000 | 0.000 |
| move | hot-a0-a0-n65536 | rtl+memory | MATCH | tsc | 3364.937/3383.502/3454.077 | 3359.861/3370.183/3470.592 | 0.993 | 0.000 | 0.000 |
| move | hot-a0-a0-n7 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.334/6.338/6.367 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n768 | rtl+memory | MATCH | tsc | 24.128/24.165/24.257 | 22.639/22.605/22.640 | 0.933 | 0.000 | 0.000 |
| move | hot-a0-a0-n8 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.334/6.334/6.334 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a0-n80 | rtl+memory | MATCH | tsc | 7.391/7.400/7.432 | 6.434/6.451/6.468 | 0.871 | 0.000 | 0.000 |
| move | hot-a0-a0-n8192 | rtl+memory | MATCH | tsc | 233.994/235.114/239.853 | 206.711/207.829/214.528 | 0.883 | 0.000 | 0.000 |
| move | hot-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 688015.333/634643.881/705064.667 | 508554.000/521705.393/561815.750 | 0.740 | 0.000 | 0.000 |
| move | hot-a0-a0-n896 | rtl+memory | MATCH | tsc | 28.801/28.801/28.802 | 24.933/24.980/25.065 | 0.866 | 0.000 | 0.000 |
| move | hot-a0-a0-n9 | rtl+memory | MATCH | tsc | 4.854/4.844/4.854 | 4.801/4.806/4.826 | 0.992 | 0.000 | 0.000 |
| move | hot-a0-a0-n96 | rtl+memory | MATCH | tsc | 7.355/7.347/7.355 | 7.238/7.238/7.238 | 0.984 | 0.000 | 0.000 |
| move | hot-a0-a1-n1024 | rtl+memory | MATCH | tsc | 34.825/34.900/35.196 | 29.759/29.762/29.766 | 0.855 | 0.000 | 0.000 |
| move | hot-a0-a1-n127 | rtl+memory | MATCH | tsc | 8.600/8.601/8.625 | 8.754/8.751/8.754 | 1.018 | 0.000 | 0.000 |
| move | hot-a0-a1-n128 | rtl+memory | MATCH | tsc | 9.775/9.743/9.789 | 8.800/8.816/8.847 | 0.904 | 0.000 | 0.000 |
| move | hot-a0-a1-n129 | rtl+memory | MATCH | tsc | 10.324/10.380/10.558 | 10.889/10.936/11.167 | 1.054 | 0.000 | 0.000 |
| move | hot-a0-a1-n1536 | rtl+memory | MATCH | tsc | 48.723/48.789/49.255 | 42.634/42.637/42.643 | 0.875 | 0.000 | 0.000 |
| move | hot-a0-a1-n16 | rtl+memory | MATCH | tsc | 4.826/4.817/4.826 | 4.801/4.809/4.821 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a1-n256 | rtl+memory | MATCH | tsc | 13.188/13.767/15.486 | 12.001/12.002/12.003 | 0.910 | 0.000 | 0.000 |
| move | hot-a0-a1-n31 | rtl+memory | MATCH | tsc | 4.803/4.805/4.816 | 4.259/4.257/4.271 | 0.887 | 0.000 | 0.000 |
| move | hot-a0-a1-n32 | rtl+memory | MATCH | tsc | 4.801/4.808/4.826 | 4.800/4.803/4.812 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a1-n33 | rtl+memory | MATCH | tsc | 9.272/9.350/9.463 | 8.880/8.908/9.021 | 0.945 | 0.000 | 0.000 |
| move | hot-a0-a1-n4096 | rtl+memory | MATCH | tsc | 167.058/167.810/169.141 | 137.952/137.561/137.967 | 0.822 | 0.000 | 0.000 |
| move | hot-a0-a1-n512 | rtl+memory | MATCH | tsc | 21.016/20.885/21.072 | 18.390/18.401/18.583 | 0.880 | 0.000 | 0.000 |
| move | hot-a0-a1-n63 | rtl+memory | MATCH | tsc | 6.400/6.432/6.604 | 6.400/6.451/6.691 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a1-n64 | rtl+memory | MATCH | tsc | 6.995/6.994/7.097 | 6.855/6.885/6.981 | 0.980 | 0.000 | 0.000 |
| move | hot-a0-a1-n65 | rtl+memory | MATCH | tsc | 8.982/9.006/9.045 | 6.975/6.982/7.024 | 0.777 | 0.000 | 0.000 |
| move | hot-a0-a128-n1024 | rtl+memory | MATCH | tsc | 32.001/31.954/32.002 | 27.346/27.392/27.491 | 0.859 | 0.000 | 0.000 |
| move | hot-a0-a128-n127 | rtl+memory | MATCH | tsc | 8.090/8.091/8.093 | 8.709/8.715/8.754 | 1.077 | 0.000 | 0.000 |
| move | hot-a0-a128-n128 | rtl+memory | MATCH | tsc | 8.086/8.377/9.141 | 8.709/8.709/8.709 | 1.077 | 0.000 | 0.000 |
| move | hot-a0-a128-n129 | rtl+memory | MATCH | tsc | 11.649/10.508/11.664 | 9.500/9.519/9.550 | 0.816 | 0.000 | 0.000 |
| move | hot-a0-a128-n1536 | rtl+memory | MATCH | tsc | 44.567/44.651/44.963 | 39.619/39.590/39.734 | 0.889 | 0.000 | 0.000 |
| move | hot-a0-a128-n16 | rtl+memory | MATCH | tsc | 4.750/4.754/4.775 | 4.750/4.750/4.750 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a128-n256 | rtl+memory | MATCH | tsc | 11.320/11.311/11.320 | 12.000/11.983/12.001 | 1.060 | 0.000 | 0.000 |
| move | hot-a0-a128-n31 | rtl+memory | MATCH | tsc | 4.785/4.730/4.803 | 4.429/4.400/4.429 | 0.923 | 0.000 | 0.000 |
| move | hot-a0-a128-n32 | rtl+memory | MATCH | tsc | 4.750/4.761/4.775 | 3.979/4.089/4.750 | 0.838 | 0.000 | 0.000 |
| move | hot-a0-a128-n33 | rtl+memory | MATCH | tsc | 6.334/6.334/6.334 | 6.367/6.362/6.367 | 1.005 | 0.000 | 0.000 |
| move | hot-a0-a128-n4096 | rtl+memory | MATCH | tsc | 129.050/129.050/129.052 | 103.753/103.839/104.088 | 0.804 | 0.000 | 0.000 |
| move | hot-a0-a128-n512 | rtl+memory | MATCH | tsc | 17.694/17.700/17.737 | 17.643/17.627/17.695 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a128-n63 | rtl+memory | MATCH | tsc | 6.367/6.430/6.867 | 6.367/6.367/6.367 | 1.005 | 0.000 | 0.000 |
| move | hot-a0-a128-n64 | rtl+memory | MATCH | tsc | 6.334/6.334/6.334 | 6.334/6.347/6.383 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a128-n65 | rtl+memory | MATCH | tsc | 8.377/8.216/8.377 | 6.367/6.415/6.602 | 0.786 | 0.000 | 0.000 |
| move | hot-a0-a2048-n1024 | rtl+memory | MATCH | tsc | 31.834/31.882/32.001 | 27.345/27.345/27.346 | 0.859 | 0.000 | 0.000 |
| move | hot-a0-a2048-n127 | rtl+memory | MATCH | tsc | 8.086/8.092/8.129 | 8.709/8.741/8.800 | 1.083 | 0.000 | 0.000 |
| move | hot-a0-a2048-n128 | rtl+memory | MATCH | tsc | 8.043/8.049/8.085 | 8.709/8.712/8.729 | 1.083 | 0.000 | 0.000 |
| move | hot-a0-a2048-n129 | rtl+memory | MATCH | tsc | 8.901/8.913/8.940 | 9.550/9.531/9.550 | 1.073 | 0.000 | 0.000 |
| move | hot-a0-a2048-n1536 | rtl+memory | MATCH | tsc | 44.567/44.567/44.568 | 39.410/39.409/39.410 | 0.884 | 0.000 | 0.000 |
| move | hot-a0-a2048-n16 | rtl+memory | MATCH | tsc | 4.750/4.754/4.775 | 4.750/4.754/4.775 | 1.000 | 0.000 | 0.000 |
| move | hot-a0-a2048-n256 | rtl+memory | MATCH | tsc | 11.260/11.263/11.285 | 11.938/11.938/11.938 | 1.060 | 0.000 | 0.000 |
| move | hot-a0-a2048-n31 | rtl+memory | MATCH | tsc | 4.786/4.727/4.808 | 4.408/4.451/4.792 | 0.912 | 0.000 | 0.000 |
| move | hot-a0-a2048-n32 | rtl+memory | MATCH | tsc | 4.750/4.754/4.775 | 3.979/4.095/4.750 | 0.838 | 0.000 | 0.000 |
| move | hot-a0-a2048-n33 | rtl+memory | MATCH | tsc | 6.334/6.338/6.367 | 6.367/6.362/6.367 | 1.005 | 0.000 | 0.000 |
| move | hot-a0-a2048-n4096 | rtl+memory | MATCH | tsc | 126.674/126.675/126.677 | 103.753/103.796/104.055 | 0.819 | 0.000 | 0.000 |
| move | hot-a0-a2048-n512 | rtl+memory | MATCH | tsc | 17.601/17.645/17.694 | 17.601/17.561/17.601 | 0.995 | 0.000 | 0.000 |
| move | hot-a0-a2048-n63 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.400/6.386/6.400 | 1.005 | 0.000 | 0.000 |
| move | hot-a0-a2048-n64 | rtl+memory | MATCH | tsc | 6.334/6.334/6.334 | 6.367/6.360/6.388 | 1.005 | 0.000 | 0.000 |
| move | hot-a0-a2048-n65 | rtl+memory | MATCH | tsc | 8.283/7.979/8.310 | 6.367/6.381/6.400 | 0.793 | 0.000 | 0.000 |
| move | hot-a1-a0-n1024 | rtl+memory | MATCH | tsc | 32.004/32.035/32.171 | 27.346/27.388/27.494 | 0.854 | 0.000 | 0.000 |
| move | hot-a1-a0-n127 | rtl+memory | MATCH | tsc | 9.272/9.295/9.436 | 8.709/8.728/8.754 | 0.939 | 0.000 | 0.000 |
| move | hot-a1-a0-n128 | rtl+memory | MATCH | tsc | 8.147/8.174/8.229 | 8.800/8.793/8.800 | 1.077 | 0.000 | 0.000 |
| move | hot-a1-a0-n129 | rtl+memory | MATCH | tsc | 10.495/10.521/10.617 | 9.600/9.600/9.601 | 0.915 | 0.000 | 0.000 |
| move | hot-a1-a0-n1536 | rtl+memory | MATCH | tsc | 44.601/46.340/50.783 | 39.413/39.415/39.417 | 0.884 | 0.000 | 0.000 |
| move | hot-a1-a0-n16 | rtl+memory | MATCH | tsc | 4.800/4.829/4.960 | 4.775/4.804/4.962 | 0.995 | 0.000 | 0.000 |
| move | hot-a1-a0-n256 | rtl+memory | MATCH | tsc | 11.322/11.563/11.866 | 12.001/12.001/12.001 | 1.060 | 0.000 | 0.000 |
| move | hot-a1-a0-n31 | rtl+memory | MATCH | tsc | 4.806/4.722/4.840 | 4.252/4.255/4.299 | 0.885 | 0.000 | 0.000 |
| move | hot-a1-a0-n32 | rtl+memory | MATCH | tsc | 4.800/4.591/4.826 | 4.021/4.136/4.800 | 0.838 | 0.000 | 0.000 |
| move | hot-a1-a0-n33 | rtl+memory | MATCH | tsc | 6.401/6.404/6.422 | 6.400/6.400/6.400 | 1.000 | 0.000 | 0.000 |
| move | hot-a1-a0-n4096 | rtl+memory | MATCH | tsc | 132.117/132.116/132.117 | 103.755/103.821/104.210 | 0.785 | 0.000 | 0.000 |
| move | hot-a1-a0-n512 | rtl+memory | MATCH | tsc | 18.140/18.083/18.378 | 17.601/17.548/17.601 | 0.970 | 0.000 | 0.000 |
| move | hot-a1-a0-n63 | rtl+memory | MATCH | tsc | 6.400/6.405/6.434 | 6.400/6.405/6.434 | 1.000 | 0.000 | 0.000 |
| move | hot-a1-a0-n64 | rtl+memory | MATCH | tsc | 6.400/6.400/6.434 | 6.400/6.409/6.434 | 1.000 | 0.000 | 0.000 |
| move | hot-a1-a0-n65 | rtl+memory | MATCH | tsc | 9.086/9.119/9.223 | 6.410/6.410/6.411 | 0.705 | 0.000 | 0.000 |
| move | hot-a1-a1-n1024 | rtl+memory | MATCH | tsc | 32.803/32.766/32.811 | 29.758/29.691/29.759 | 0.907 | 0.000 | 0.000 |
| move | hot-a1-a1-n127 | rtl+memory | MATCH | tsc | 8.323/8.325/8.361 | 8.800/8.794/8.847 | 1.058 | 0.000 | 0.000 |
| move | hot-a1-a1-n128 | rtl+memory | MATCH | tsc | 9.818/9.895/10.077 | 8.822/8.844/8.905 | 0.897 | 0.000 | 0.000 |
| move | hot-a1-a1-n129 | rtl+memory | MATCH | tsc | 9.859/9.847/10.143 | 11.317/11.247/11.336 | 1.148 | 0.000 | 0.000 |
| move | hot-a1-a1-n1536 | rtl+memory | MATCH | tsc | 45.364/45.364/45.364 | 42.402/42.456/42.627 | 0.935 | 0.000 | 0.000 |
| move | hot-a1-a1-n16 | rtl+memory | MATCH | tsc | 4.826/4.827/4.859 | 4.801/4.823/4.965 | 0.995 | 0.000 | 0.000 |
| move | hot-a1-a1-n256 | rtl+memory | MATCH | tsc | 15.229/14.441/15.292 | 12.254/12.408/12.610 | 0.821 | 0.000 | 0.000 |
| move | hot-a1-a1-n31 | rtl+memory | MATCH | tsc | 4.802/4.802/4.802 | 4.264/4.253/4.265 | 0.888 | 0.000 | 0.000 |
| move | hot-a1-a1-n32 | rtl+memory | MATCH | tsc | 4.825/4.829/4.839 | 4.800/4.807/4.826 | 0.995 | 0.000 | 0.000 |
| move | hot-a1-a1-n33 | rtl+memory | MATCH | tsc | 9.483/9.447/9.504 | 8.828/8.929/9.372 | 0.934 | 0.000 | 0.000 |
| move | hot-a1-a1-n4096 | rtl+memory | MATCH | tsc | 163.040/163.647/164.745 | 126.412/126.222/126.412 | 0.771 | 0.000 | 0.000 |
| move | hot-a1-a1-n512 | rtl+memory | MATCH | tsc | 19.497/19.294/19.766 | 18.231/18.879/20.811 | 0.926 | 0.000 | 0.000 |
| move | hot-a1-a1-n63 | rtl+memory | MATCH | tsc | 6.400/6.408/6.434 | 6.400/6.400/6.400 | 1.000 | 0.000 | 0.000 |
| move | hot-a1-a1-n64 | rtl+memory | MATCH | tsc | 7.072/7.083/7.106 | 7.016/7.031/7.093 | 0.988 | 0.000 | 0.000 |
| move | hot-a1-a1-n65 | rtl+memory | MATCH | tsc | 8.936/8.960/9.018 | 6.958/6.954/6.978 | 0.779 | 0.000 | 0.000 |
| move | hot-a128-a0-n1024 | rtl+memory | MATCH | tsc | 32.002/32.009/32.054 | 27.345/27.345/27.346 | 0.854 | 0.000 | 0.000 |
| move | hot-a128-a0-n127 | rtl+memory | MATCH | tsc | 8.273/8.316/8.365 | 8.709/8.728/8.754 | 1.053 | 0.000 | 0.000 |
| move | hot-a128-a0-n128 | rtl+memory | MATCH | tsc | 8.086/8.086/8.086 | 8.709/8.709/8.709 | 1.077 | 0.000 | 0.000 |
| move | hot-a128-a0-n129 | rtl+memory | MATCH | tsc | 9.440/9.443/9.632 | 9.550/9.550/9.550 | 1.012 | 0.000 | 0.000 |
| move | hot-a128-a0-n1536 | rtl+memory | MATCH | tsc | 44.802/44.769/44.804 | 39.410/39.440/39.619 | 0.880 | 0.000 | 0.000 |
| move | hot-a128-a0-n16 | rtl+memory | MATCH | tsc | 4.775/4.775/4.775 | 4.750/4.750/4.750 | 0.995 | 0.000 | 0.000 |
| move | hot-a128-a0-n256 | rtl+memory | MATCH | tsc | 11.586/11.510/11.588 | 11.938/11.938/11.938 | 1.030 | 0.000 | 0.000 |
| move | hot-a128-a0-n31 | rtl+memory | MATCH | tsc | 4.779/4.645/4.804 | 4.383/4.401/4.429 | 0.913 | 0.000 | 0.000 |
| move | hot-a128-a0-n32 | rtl+memory | MATCH | tsc | 4.775/4.779/4.800 | 3.979/3.985/4.000 | 0.833 | 0.000 | 0.000 |
| move | hot-a128-a0-n33 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.367/6.364/6.367 | 1.000 | 0.000 | 0.000 |
| move | hot-a128-a0-n4096 | rtl+memory | MATCH | tsc | 131.425/131.549/132.292 | 103.208/103.331/103.510 | 0.785 | 0.000 | 0.000 |
| move | hot-a128-a0-n512 | rtl+memory | MATCH | tsc | 17.789/17.755/17.821 | 17.509/17.575/17.716 | 0.995 | 0.000 | 0.000 |
| move | hot-a128-a0-n63 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.367/6.367/6.367 | 1.000 | 0.000 | 0.000 |
| move | hot-a128-a0-n64 | rtl+memory | MATCH | tsc | 6.367/6.366/6.386 | 6.367/6.351/6.367 | 0.995 | 0.000 | 0.000 |
| move | hot-a128-a0-n65 | rtl+memory | MATCH | tsc | 8.514/9.023/10.747 | 6.400/6.458/6.647 | 0.753 | 0.000 | 0.000 |
| move | hot-a15-a31-n1024 | rtl+memory | MATCH | tsc | 33.873/33.809/34.114 | 29.763/29.767/29.776 | 0.879 | 0.000 | 0.000 |
| move | hot-a15-a31-n127 | rtl+memory | MATCH | tsc | 10.062/10.048/10.477 | 8.865/8.867/8.910 | 0.880 | 0.000 | 0.000 |
| move | hot-a15-a31-n128 | rtl+memory | MATCH | tsc | 9.899/9.935/10.156 | 8.870/8.892/8.962 | 0.896 | 0.000 | 0.000 |
| move | hot-a15-a31-n129 | rtl+memory | MATCH | tsc | 9.024/9.029/9.075 | 9.600/9.616/9.651 | 1.064 | 0.000 | 0.000 |
| move | hot-a15-a31-n1536 | rtl+memory | MATCH | tsc | 48.086/48.002/48.315 | 42.641/42.641/42.652 | 0.887 | 0.000 | 0.000 |
| move | hot-a15-a31-n16 | rtl+memory | MATCH | tsc | 4.800/4.793/4.800 | 4.775/4.787/4.800 | 1.000 | 0.000 | 0.000 |
| move | hot-a15-a31-n256 | rtl+memory | MATCH | tsc | 13.216/13.498/15.300 | 12.247/12.311/12.421 | 0.924 | 0.000 | 0.000 |
| move | hot-a15-a31-n31 | rtl+memory | MATCH | tsc | 4.800/4.797/4.800 | 4.775/4.779/4.800 | 0.995 | 0.000 | 0.000 |
| move | hot-a15-a31-n32 | rtl+memory | MATCH | tsc | 4.826/4.818/4.826 | 4.775/4.815/4.925 | 0.990 | 0.000 | 0.000 |
| move | hot-a15-a31-n33 | rtl+memory | MATCH | tsc | 6.367/6.372/6.400 | 6.400/6.400/6.400 | 1.005 | 0.000 | 0.000 |
| move | hot-a15-a31-n4096 | rtl+memory | MATCH | tsc | 167.186/167.734/169.125 | 143.783/143.662/144.371 | 0.853 | 0.000 | 0.000 |
| move | hot-a15-a31-n512 | rtl+memory | MATCH | tsc | 20.459/20.217/20.460 | 18.298/21.638/27.238 | 0.907 | 0.000 | 0.000 |
| move | hot-a15-a31-n63 | rtl+memory | MATCH | tsc | 6.874/6.877/6.926 | 7.036/7.029/7.054 | 1.019 | 0.000 | 0.000 |
| move | hot-a15-a31-n64 | rtl+memory | MATCH | tsc | 6.878/6.889/6.992 | 7.018/7.010/7.040 | 1.021 | 0.000 | 0.000 |
| move | hot-a15-a31-n65 | rtl+memory | MATCH | tsc | 7.934/7.912/7.966 | 6.438/6.448/6.475 | 0.813 | 0.000 | 0.000 |
| move | hot-a2048-a0-n1024 | rtl+memory | MATCH | tsc | 32.002/31.954/32.002 | 27.346/27.345/27.346 | 0.854 | 0.000 | 0.000 |
| move | hot-a2048-a0-n127 | rtl+memory | MATCH | tsc | 8.363/8.365/8.389 | 8.709/8.726/8.754 | 1.045 | 0.000 | 0.000 |
| move | hot-a2048-a0-n128 | rtl+memory | MATCH | tsc | 8.086/8.085/8.086 | 8.709/8.712/8.729 | 1.077 | 0.000 | 0.000 |
| move | hot-a2048-a0-n129 | rtl+memory | MATCH | tsc | 9.478/9.476/9.536 | 9.550/9.560/9.583 | 1.008 | 0.000 | 0.000 |
| move | hot-a2048-a0-n1536 | rtl+memory | MATCH | tsc | 44.567/44.674/44.892 | 39.409/39.409/39.410 | 0.884 | 0.000 | 0.000 |
| move | hot-a2048-a0-n16 | rtl+memory | MATCH | tsc | 4.775/4.786/4.800 | 4.750/4.750/4.750 | 0.995 | 0.000 | 0.000 |
| move | hot-a2048-a0-n256 | rtl+memory | MATCH | tsc | 11.531/11.455/11.531 | 11.938/11.938/11.938 | 1.035 | 0.000 | 0.000 |
| move | hot-a2048-a0-n31 | rtl+memory | MATCH | tsc | 4.804/4.729/4.817 | 4.427/4.400/4.429 | 0.910 | 0.000 | 0.000 |
| move | hot-a2048-a0-n32 | rtl+memory | MATCH | tsc | 4.775/4.775/4.775 | 3.979/3.979/3.979 | 0.833 | 0.000 | 0.000 |
| move | hot-a2048-a0-n33 | rtl+memory | MATCH | tsc | 6.367/6.376/6.400 | 6.367/6.368/6.376 | 1.000 | 0.000 | 0.000 |
| move | hot-a2048-a0-n4096 | rtl+memory | MATCH | tsc | 131.425/131.556/131.906 | 103.753/103.796/104.057 | 0.789 | 0.000 | 0.000 |
| move | hot-a2048-a0-n512 | rtl+memory | MATCH | tsc | 17.694/17.721/17.788 | 17.601/17.597/17.601 | 0.995 | 0.000 | 0.000 |
| move | hot-a2048-a0-n63 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.367/6.367/6.367 | 1.000 | 0.000 | 0.000 |
| move | hot-a2048-a0-n64 | rtl+memory | MATCH | tsc | 6.367/6.369/6.386 | 6.334/6.340/6.367 | 0.995 | 0.000 | 0.000 |
| move | hot-a2048-a0-n65 | rtl+memory | MATCH | tsc | 8.658/8.616/8.700 | 6.400/6.384/6.400 | 0.735 | 0.000 | 0.000 |
| move | hot-a31-a15-n1024 | rtl+memory | MATCH | tsc | 33.221/33.178/33.285 | 29.768/29.778/29.802 | 0.895 | 0.000 | 0.000 |
| move | hot-a31-a15-n127 | rtl+memory | MATCH | tsc | 10.336/10.333/10.639 | 8.824/8.853/8.933 | 0.856 | 0.000 | 0.000 |
| move | hot-a31-a15-n128 | rtl+memory | MATCH | tsc | 10.376/10.302/10.470 | 8.823/8.833/8.884 | 0.851 | 0.000 | 0.000 |
| move | hot-a31-a15-n129 | rtl+memory | MATCH | tsc | 8.977/8.983/9.047 | 9.600/9.604/9.675 | 1.069 | 0.000 | 0.000 |
| move | hot-a31-a15-n1536 | rtl+memory | MATCH | tsc | 45.755/45.779/45.912 | 42.641/42.656/42.733 | 0.933 | 0.000 | 0.000 |
| move | hot-a31-a15-n16 | rtl+memory | MATCH | tsc | 4.775/4.775/4.775 | 4.775/4.782/4.800 | 1.000 | 0.000 | 0.000 |
| move | hot-a31-a15-n256 | rtl+memory | MATCH | tsc | 12.983/13.803/15.490 | 12.282/12.352/12.488 | 0.937 | 0.000 | 0.000 |
| move | hot-a31-a15-n31 | rtl+memory | MATCH | tsc | 4.800/4.806/4.818 | 4.800/4.804/4.825 | 1.000 | 0.000 | 0.000 |
| move | hot-a31-a15-n32 | rtl+memory | MATCH | tsc | 4.800/4.807/4.826 | 4.800/4.802/4.812 | 1.000 | 0.000 | 0.000 |
| move | hot-a31-a15-n33 | rtl+memory | MATCH | tsc | 6.400/6.454/6.641 | 6.434/6.445/6.609 | 1.000 | 0.000 | 0.000 |
| move | hot-a31-a15-n4096 | rtl+memory | MATCH | tsc | 163.888/163.966/164.427 | 125.613/125.844/126.410 | 0.766 | 0.000 | 0.000 |
| move | hot-a31-a15-n512 | rtl+memory | MATCH | tsc | 20.034/19.871/20.360 | 18.558/18.469/18.558 | 0.921 | 0.000 | 0.000 |
| move | hot-a31-a15-n63 | rtl+memory | MATCH | tsc | 7.143/7.061/7.150 | 7.055/7.051/7.077 | 0.991 | 0.000 | 0.000 |
| move | hot-a31-a15-n64 | rtl+memory | MATCH | tsc | 7.033/7.021/7.104 | 7.067/7.090/7.140 | 1.006 | 0.000 | 0.000 |
| move | hot-a31-a15-n65 | rtl+memory | MATCH | tsc | 7.994/8.049/8.306 | 6.400/6.399/6.400 | 0.801 | 0.000 | 0.000 |
| move | overlap-backward-d1-n1024 | rtl+memory | MATCH | tsc | 48.174/48.120/48.264 | 48.411/48.297/48.419 | 0.999 | 0.000 | 0.000 |
| move | overlap-backward-d1-n128 | rtl+memory | MATCH | tsc | 25.150/25.136/25.194 | 21.155/21.155/21.155 | 0.841 | 0.000 | 0.000 |
| move | overlap-backward-d1-n1536 | rtl+memory | MATCH | tsc | 61.752/61.571/61.753 | 60.251/60.293/60.541 | 0.976 | 0.000 | 0.000 |
| move | overlap-backward-d1-n2048 | rtl+memory | MATCH | tsc | 74.417/73.656/74.417 | 73.232/73.445/74.022 | 0.984 | 0.000 | 0.000 |
| move | overlap-backward-d1-n256 | rtl+memory | MATCH | tsc | 29.421/29.405/29.760 | 29.254/29.219/29.421 | 0.991 | 0.000 | 0.000 |
| move | overlap-backward-d1-n33 | rtl+memory | MATCH | tsc | 22.723/22.723/22.723 | 22.722/22.731/22.781 | 1.000 | 0.000 | 0.000 |
| move | overlap-backward-d1-n4096 | rtl+memory | MATCH | tsc | 164.675/164.576/165.057 | 144.525/144.825/145.546 | 0.880 | 0.000 | 0.000 |
| move | overlap-backward-d1-n512 | rtl+memory | MATCH | tsc | 36.545/37.212/38.644 | 36.746/36.667/36.939 | 1.009 | 0.000 | 0.000 |
| move | overlap-backward-d1-n64 | rtl+memory | MATCH | tsc | 21.245/21.269/21.356 | 21.277/21.297/21.387 | 1.001 | 0.000 | 0.000 |
| move | overlap-backward-d1-n65 | rtl+memory | MATCH | tsc | 23.506/23.506/23.506 | 21.662/21.655/21.675 | 0.922 | 0.000 | 0.000 |
| move | overlap-backward-d1-n65536 | rtl+memory | MATCH | tsc | 2702.584/2702.324/2710.138 | 2645.088/2653.962/2674.893 | 0.981 | 0.000 | 0.000 |
| move | overlap-backward-d16-n1024 | rtl+memory | MATCH | tsc | 41.134/41.339/41.806 | 41.179/41.193/41.360 | 1.001 | 0.000 | 0.000 |
| move | overlap-backward-d16-n128 | rtl+memory | MATCH | tsc | 18.115/18.128/18.209 | 16.566/16.636/16.764 | 0.915 | 0.000 | 0.000 |
| move | overlap-backward-d16-n1536 | rtl+memory | MATCH | tsc | 53.046/53.114/53.309 | 53.045/53.099/53.421 | 1.000 | 0.000 | 0.000 |
| move | overlap-backward-d16-n2048 | rtl+memory | MATCH | tsc | 66.258/66.420/67.076 | 66.063/66.025/66.540 | 0.992 | 0.000 | 0.000 |
| move | overlap-backward-d16-n256 | rtl+memory | MATCH | tsc | 21.749/21.809/22.088 | 21.959/22.352/23.600 | 1.011 | 0.000 | 0.000 |
| move | overlap-backward-d16-n33 | rtl+memory | MATCH | tsc | 21.939/21.939/21.939 | 21.939/21.959/22.083 | 1.000 | 0.000 | 0.000 |
| move | overlap-backward-d16-n4096 | rtl+memory | MATCH | tsc | 163.089/163.147/163.487 | 136.174/136.073/136.175 | 0.835 | 0.000 | 0.000 |
| move | overlap-backward-d16-n512 | rtl+memory | MATCH | tsc | 28.959/29.107/30.492 | 28.907/28.776/29.164 | 0.993 | 0.000 | 0.000 |
| move | overlap-backward-d16-n64 | rtl+memory | MATCH | tsc | 6.367/6.367/6.367 | 6.367/6.367/6.367 | 1.000 | 0.000 | 0.000 |
| move | overlap-backward-d16-n65 | rtl+memory | MATCH | tsc | 23.506/23.506/23.506 | 14.887/14.887/14.887 | 0.633 | 0.000 | 0.000 |
| move | overlap-backward-d16-n65536 | rtl+memory | MATCH | tsc | 2702.300/2699.759/2708.148 | 2637.487/2642.960/2658.477 | 0.979 | 0.000 | 0.000 |
| move | overlap-backward-d63-n1024 | rtl+memory | MATCH | tsc | 34.673/34.782/34.965 | 36.156/36.248/36.405 | 1.040 | 0.000 | 0.000 |
| move | overlap-backward-d63-n128 | rtl+memory | MATCH | tsc | 24.290/24.283/24.290 | 19.588/19.588/19.588 | 0.806 | 0.000 | 0.000 |
| move | overlap-backward-d63-n1536 | rtl+memory | MATCH | tsc | 47.470/47.686/48.990 | 48.985/48.937/49.023 | 1.032 | 0.000 | 0.000 |
| move | overlap-backward-d63-n2048 | rtl+memory | MATCH | tsc | 60.015/60.088/60.402 | 61.739/61.729/61.817 | 1.030 | 0.000 | 0.000 |
| move | overlap-backward-d63-n256 | rtl+memory | MATCH | tsc | 26.303/26.061/26.570 | 25.734/25.845/26.824 | 0.980 | 0.000 | 0.000 |
| move | overlap-backward-d63-n4096 | rtl+memory | MATCH | tsc | 125.745/125.725/125.746 | 128.130/128.131/128.132 | 1.019 | 0.000 | 0.000 |
| move | overlap-backward-d63-n512 | rtl+memory | MATCH | tsc | 27.666/27.855/28.651 | 27.700/27.659/27.966 | 1.000 | 0.000 | 0.000 |
| move | overlap-backward-d63-n64 | rtl+memory | MATCH | tsc | 19.693/19.710/19.762 | 19.745/19.745/19.745 | 1.003 | 0.000 | 0.000 |
| move | overlap-backward-d63-n65 | rtl+memory | MATCH | tsc | 24.289/24.289/24.290 | 21.155/21.171/21.265 | 0.871 | 0.000 | 0.000 |
| move | overlap-backward-d63-n65536 | rtl+memory | MATCH | tsc | 2658.894/2657.668/2659.514 | 2652.082/2647.629/2654.194 | 0.999 | 0.000 | 0.000 |
| move | overlap-forward-d1-n1024 | rtl+memory | MATCH | tsc | 42.183/42.229/42.479 | 27.625/27.782/28.362 | 0.657 | 0.000 | 0.000 |
| move | overlap-forward-d1-n128 | rtl+memory | MATCH | tsc | 19.290/19.321/19.390 | 17.797/17.827/17.890 | 0.920 | 0.000 | 0.000 |
| move | overlap-forward-d1-n1536 | rtl+memory | MATCH | tsc | 53.836/54.008/54.263 | 39.563/39.576/39.739 | 0.735 | 0.000 | 0.000 |
| move | overlap-forward-d1-n2048 | rtl+memory | MATCH | tsc | 66.506/67.187/68.140 | 52.277/52.277/52.278 | 0.786 | 0.000 | 0.000 |
| move | overlap-forward-d1-n256 | rtl+memory | MATCH | tsc | 23.489/23.701/24.609 | 20.623/20.188/21.071 | 0.807 | 0.000 | 0.000 |
| move | overlap-forward-d1-n33 | rtl+memory | MATCH | tsc | 21.547/21.547/21.547 | 21.547/21.552/21.579 | 1.000 | 0.000 | 0.000 |
| move | overlap-forward-d1-n4096 | rtl+memory | MATCH | tsc | 131.425/131.636/132.508 | 103.753/103.518/103.753 | 0.789 | 0.000 | 0.000 |
| move | overlap-forward-d1-n512 | rtl+memory | MATCH | tsc | 30.203/30.108/30.481 | 22.642/22.792/23.929 | 0.762 | 0.000 | 0.000 |
| move | overlap-forward-d1-n64 | rtl+memory | MATCH | tsc | 16.455/16.461/16.477 | 16.455/16.455/16.455 | 1.000 | 0.000 | 0.000 |
| move | overlap-forward-d1-n65 | rtl+memory | MATCH | tsc | 24.681/24.681/24.681 | 16.463/16.466/16.488 | 0.667 | 0.000 | 0.000 |
| move | overlap-forward-d1-n65536 | rtl+memory | MATCH | tsc | 2626.654/2627.465/2629.539 | 2575.016/2576.452/2582.218 | 0.979 | 0.000 | 0.000 |
| move | overlap-forward-d16-n1024 | rtl+memory | MATCH | tsc | 42.161/42.254/42.594 | 27.735/27.800/28.355 | 0.658 | 0.000 | 0.000 |
| move | overlap-forward-d16-n128 | rtl+memory | MATCH | tsc | 19.385/19.354/19.402 | 17.797/17.833/17.910 | 0.923 | 0.000 | 0.000 |
| move | overlap-forward-d16-n1536 | rtl+memory | MATCH | tsc | 53.836/53.893/54.232 | 39.631/39.653/39.740 | 0.736 | 0.000 | 0.000 |
| move | overlap-forward-d16-n2048 | rtl+memory | MATCH | tsc | 67.133/67.378/68.007 | 52.277/52.277/52.278 | 0.779 | 0.000 | 0.000 |
| move | overlap-forward-d16-n256 | rtl+memory | MATCH | tsc | 23.922/23.627/24.193 | 20.794/20.258/20.835 | 0.876 | 0.000 | 0.000 |
| move | overlap-forward-d16-n33 | rtl+memory | MATCH | tsc | 22.722/22.631/22.764 | 22.295/22.425/22.722 | 0.980 | 0.000 | 0.000 |
| move | overlap-forward-d16-n4096 | rtl+memory | MATCH | tsc | 132.114/132.096/132.510 | 103.752/103.674/103.753 | 0.785 | 0.000 | 0.000 |
| move | overlap-forward-d16-n512 | rtl+memory | MATCH | tsc | 30.128/30.543/31.173 | 22.915/23.517/27.498 | 0.747 | 0.000 | 0.000 |
| move | overlap-forward-d16-n64 | rtl+memory | MATCH | tsc | 6.400/6.400/6.400 | 6.400/6.395/6.400 | 1.000 | 0.000 | 0.000 |
| move | overlap-forward-d16-n65 | rtl+memory | MATCH | tsc | 25.912/25.914/25.940 | 16.454/16.454/16.454 | 0.635 | 0.000 | 0.000 |
| move | overlap-forward-d16-n65536 | rtl+memory | MATCH | tsc | 2642.796/2639.138/2646.347 | 2586.263/2584.979/2591.079 | 0.978 | 0.000 | 0.000 |
| move | overlap-forward-d63-n1024 | rtl+memory | MATCH | tsc | 32.316/32.294/32.396 | 28.086/28.260/28.576 | 0.874 | 0.000 | 0.000 |
| move | overlap-forward-d63-n128 | rtl+memory | MATCH | tsc | 18.805/18.701/18.805 | 18.693/18.691/18.790 | 1.001 | 0.000 | 0.000 |
| move | overlap-forward-d63-n1536 | rtl+memory | MATCH | tsc | 45.039/45.081/45.145 | 39.851/39.868/39.955 | 0.884 | 0.000 | 0.000 |
| move | overlap-forward-d63-n2048 | rtl+memory | MATCH | tsc | 57.966/57.969/58.075 | 52.556/52.596/52.836 | 0.907 | 0.000 | 0.000 |
| move | overlap-forward-d63-n256 | rtl+memory | MATCH | tsc | 20.934/21.469/22.193 | 20.573/20.372/20.725 | 0.956 | 0.000 | 0.000 |
| move | overlap-forward-d63-n4096 | rtl+memory | MATCH | tsc | 132.112/132.113/132.116 | 104.308/104.307/104.309 | 0.790 | 0.000 | 0.000 |
| move | overlap-forward-d63-n512 | rtl+memory | MATCH | tsc | 24.881/25.164/26.325 | 22.932/23.665/25.191 | 0.929 | 0.000 | 0.000 |
| move | overlap-forward-d63-n64 | rtl+memory | MATCH | tsc | 17.594/17.607/17.685 | 17.594/17.594/17.594 | 1.000 | 0.000 | 0.000 |
| move | overlap-forward-d63-n65 | rtl+memory | MATCH | tsc | 24.625/24.625/24.625 | 18.449/18.449/18.449 | 0.749 | 0.000 | 0.000 |
| move | overlap-forward-d63-n65536 | rtl+memory | MATCH | tsc | 2656.861/2653.355/2658.745 | 2637.400/2636.185/2639.295 | 0.994 | 0.000 | 0.000 |
| move | same-a0-n0 | rtl+memory | MATCH | tsc | 7.052/7.055/7.072 | 7.052/7.052/7.052 | 1.000 | 0.000 | 0.000 |
| move | same-a0-n1 | rtl+memory | MATCH | tsc | 7.088/7.088/7.088 | 7.052/7.055/7.072 | 0.995 | 0.000 | 0.000 |
| move | same-a0-n1048576 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | same-a0-n127 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | same-a0-n128 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | same-a0-n129 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | same-a0-n16 | rtl+memory | MATCH | tsc | 4.775/4.777/4.787 | 4.750/4.750/4.750 | 0.995 | 0.000 | 0.000 |
| move | same-a0-n192 | rtl+memory | MATCH | tsc | 5.485/5.489/5.513 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | same-a0-n256 | rtl+memory | MATCH | tsc | 5.485/5.489/5.513 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | same-a0-n32 | rtl+memory | MATCH | tsc | 7.088/7.083/7.089 | 7.052/7.052/7.052 | 0.995 | 0.000 | 0.000 |
| move | same-a0-n33 | rtl+memory | MATCH | tsc | 21.939/21.939/21.939 | 6.301/6.305/6.334 | 0.287 | 0.000 | 0.000 |
| move | same-a0-n4096 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | same-a0-n64 | rtl+memory | MATCH | tsc | 7.201/7.184/7.201 | 6.334/6.329/6.334 | 0.880 | 0.000 | 0.000 |
| move | same-a0-n65 | rtl+memory | MATCH | tsc | 5.485/5.493/5.513 | 5.485/5.493/5.513 | 1.000 | 0.000 | 0.000 |
| move | same-a0-n80 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 5.485/5.485/5.485 | 1.000 | 0.000 | 0.000 |
| move | same-a0-n96 | rtl+memory | MATCH | tsc | 5.513/5.513/5.542 | 5.513/5.505/5.513 | 1.000 | 0.000 | 0.000 |
| move | same-a0-n97 | rtl+memory | MATCH | tsc | 5.485/5.485/5.485 | 6.268/6.268/6.268 | 1.143 | 0.000 | 0.000 |
| move | stream-a0-a0-n1024 | rtl+memory | MATCH | tsc | 286.167/294.408/306.700 | 291.412/294.245/303.692 | 1.009 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048575 | rtl+memory | MATCH | tsc | 303865.664/318649.424/363539.172 | 309645.969/314574.433/344322.453 | 1.019 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 325354.961/328581.547/335663.500 | 331402.156/343646.129/364156.969 | 1.099 | 0.000 | 0.000 |
| move | stream-a0-a0-n131072 | rtl+memory | MATCH | tsc | 35484.634/35557.986/35982.363 | 36309.946/36114.271/36792.684 | 1.009 | 0.000 | 0.000 |
| move | stream-a0-a0-n1536 | rtl+memory | MATCH | tsc | 427.120/429.064/438.195 | 428.666/428.769/432.897 | 0.986 | 0.000 | 0.000 |
| move | stream-a0-a0-n16384 | rtl+memory | MATCH | tsc | 4451.947/4562.237/4919.743 | 4549.016/4544.063/4649.146 | 1.007 | 0.000 | 0.000 |
| move | stream-a0-a0-n16777216 | rtl+memory | MATCH | tsc | 4420402.250/4634013.143/5425345.500 | 2874417.375/3012556.536/3496356.250 | 0.653 | 0.000 | 0.000 |
| move | stream-a0-a0-n2048 | rtl+memory | MATCH | tsc | 563.782/566.902/578.626 | 579.034/569.415/581.804 | 1.016 | 0.000 | 0.000 |
| move | stream-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 655579.859/691707.129/755315.906 | 668931.516/692414.455/746239.844 | 1.016 | 0.000 | 0.000 |
| move | stream-a0-a0-n256 | rtl+memory | MATCH | tsc | 75.957/75.217/76.018 | 75.419/75.886/81.298 | 0.975 | 0.000 | 0.000 |
| move | stream-a0-a0-n262144 | rtl+memory | MATCH | tsc | 74198.043/80417.203/98867.539 | 71746.078/80949.680/95570.223 | 0.968 | 0.000 | 0.000 |
| move | stream-a0-a0-n32768 | rtl+memory | MATCH | tsc | 8977.254/8925.849/9076.090 | 9016.456/9040.839/9207.819 | 0.991 | 0.000 | 0.000 |
| move | stream-a0-a0-n33554432 | rtl+memory | MATCH | tsc | 5895348.500/6023135.714/6645943.500 | 5855662.250/5803955.786/5857225.000 | 0.991 | 0.000 | 0.000 |
| move | stream-a0-a0-n4096 | rtl+memory | MATCH | tsc | 1148.425/1166.483/1312.935 | 1144.487/1139.761/1145.620 | 0.998 | 0.000 | 0.000 |
| move | stream-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 1429108.750/1435488.170/1635695.750 | 1523513.812/1407654.018/1525739.188 | 1.006 | 0.000 | 0.000 |
| move | stream-a0-a0-n512 | rtl+memory | MATCH | tsc | 150.618/147.867/152.421 | 151.119/151.894/156.323 | 1.033 | 0.000 | 0.000 |
| move | stream-a0-a0-n524288 | rtl+memory | MATCH | tsc | 151439.723/154486.646/165383.422 | 153040.918/154832.039/158044.523 | 1.005 | 0.000 | 0.000 |
| move | stream-a0-a0-n65536 | rtl+memory | MATCH | tsc | 17839.525/18198.687/19694.149 | 17930.703/18314.887/19455.740 | 1.006 | 0.000 | 0.000 |
| move | stream-a0-a0-n67108864 | rtl+memory | MATCH | tsc | 11770101.000/11711893.143/11774851.000 | 11583055.500/11657672.571/12328606.000 | 0.985 | 0.000 | 0.000 |
| move | stream-a0-a0-n786432 | rtl+memory | MATCH | tsc | 227260.676/234919.129/253704.541 | 229841.100/231837.521/236202.859 | 1.032 | 0.000 | 0.000 |
| move | stream-a0-a0-n8192 | rtl+memory | MATCH | tsc | 2258.852/2397.514/2767.858 | 2313.259/2348.085/2599.389 | 1.005 | 0.000 | 0.000 |
| move | stream-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 2289034.500/2520114.196/2924874.250 | 2382635.625/2376277.354/2742635.750 | 1.034 | 0.000 | 0.000 |
