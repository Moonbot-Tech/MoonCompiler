# MoonCompiler Pulse result

Mode: `quick`. Baseline: `moon-old`. Candidate: `moon-final`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| move | 297 | 0.714 | 244 | 30 | 23 | 0.000 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| memory | 297 | 0.714 | 244 | 30 | 23 |
| rtl | 297 | 0.714 | 244 | 30 | 23 |

## Extreme results

### 15 fastest

- `move/hot-a15-a31-n4096`: `0.034x`
- `move/hot-a0-a1-n4096`: `0.035x`
- `move/hot-a15-a31-n1536`: `0.282x`
- `move/hot-a15-a31-n64`: `0.301x`
- `move/hot-a15-a31-n63`: `0.301x`
- `move/hot-a0-a1-n65`: `0.341x`
- `move/hot-a15-a31-n128`: `0.357x`
- `move/hot-a0-a1-n128`: `0.362x`
- `move/hot-a15-a31-n127`: `0.374x`
- `move/hot-a0-a1-n127`: `0.380x`
- `move/hot-a1-a1-n31`: `0.392x`
- `move/hot-a0-a1-n31`: `0.400x`
- `move/hot-a0-a0-n524288`: `0.404x`
- `move/hot-a0-a1-n1536`: `0.408x`
- `move/hot-a1-a0-n31`: `0.411x`

### 15 slowest

- `move/stream-a0-a0-n524288`: `1.647x`
- `move/overlap-forward-d16-n128`: `1.621x`
- `move/stream-a0-a0-n2097152`: `1.620x`
- `move/stream-a0-a0-n1048575`: `1.605x`
- `move/stream-a0-a0-n8388608`: `1.598x`
- `move/stream-a0-a0-n1048576`: `1.526x`
- `move/stream-a0-a0-n4194304`: `1.505x`
- `move/overlap-backward-d16-n128`: `1.495x`
- `move/stream-a0-a0-n786432`: `1.462x`
- `move/overlap-forward-d16-n33`: `1.408x`
- `move/overlap-backward-d16-n256`: `1.329x`
- `move/same-a0-n0`: `1.279x`
- `move/same-a0-n1`: `1.275x`
- `move/hot-a0-a0-n0`: `1.242x`
- `move/overlap-forward-d16-n256`: `1.222x`
## Diagnostic Move process drift

These cases remain in the table, but the central ratio is calculated from adjacent mirrored processes; drift does not replace a semantic failure.

- `paired/move/hot-a0-a0-n1048576 ratio drift 1.453x`
- `paired/move/hot-a0-a0-n128 ratio drift 1.345x`
- `paired/move/hot-a0-a0-n129 ratio drift 1.556x`
- `paired/move/hot-a0-a0-n15 ratio drift 1.622x`
- `paired/move/hot-a0-a0-n160 ratio drift 1.253x`
- `paired/move/hot-a0-a0-n17 ratio drift 1.503x`
- `paired/move/hot-a0-a0-n2 ratio drift 1.623x`
- `paired/move/hot-a0-a0-n255 ratio drift 1.430x`
- `paired/move/hot-a0-a0-n257 ratio drift 1.304x`
- `paired/move/hot-a0-a0-n3 ratio drift 1.344x`
- `paired/move/hot-a0-a0-n31 ratio drift 1.542x`
- `paired/move/hot-a0-a0-n33 ratio drift 1.497x`
- `paired/move/hot-a0-a0-n4 ratio drift 1.635x`
- `paired/move/hot-a0-a0-n4194304 ratio drift 1.305x`
- `paired/move/hot-a0-a0-n64 ratio drift 1.516x`
- `paired/move/hot-a0-a0-n8 ratio drift 1.293x`
- `paired/move/hot-a0-a0-n80 ratio drift 1.439x`
- `paired/move/hot-a0-a0-n9 ratio drift 1.600x`
- `paired/move/hot-a0-a0-n96 ratio drift 1.445x`
- `paired/move/hot-a0-a1-n1024 ratio drift 1.637x`
- `paired/move/hot-a0-a1-n1536 ratio drift 1.663x`
- `paired/move/hot-a0-a1-n16 ratio drift 1.407x`
- `paired/move/hot-a0-a1-n256 ratio drift 1.577x`
- `paired/move/hot-a0-a1-n32 ratio drift 1.567x`
- `paired/move/hot-a0-a1-n33 ratio drift 1.408x`
- `paired/move/hot-a0-a1-n512 ratio drift 1.663x`
- `paired/move/hot-a0-a128-n129 ratio drift 1.467x`
- `paired/move/hot-a1-a0-n16 ratio drift 1.300x`
- `paired/move/hot-a1-a0-n256 ratio drift 1.553x`
- `paired/move/hot-a1-a0-n32 ratio drift 1.523x`
- `paired/move/hot-a1-a0-n33 ratio drift 1.529x`
- `paired/move/hot-a1-a1-n127 ratio drift 1.553x`
- `paired/move/hot-a1-a1-n128 ratio drift 1.598x`
- `paired/move/hot-a1-a1-n129 ratio drift 1.578x`
- `paired/move/hot-a1-a1-n16 ratio drift 1.334x`
- `paired/move/hot-a1-a1-n256 ratio drift 1.284x`
- `paired/move/hot-a1-a1-n32 ratio drift 1.632x`
- `paired/move/hot-a1-a1-n33 ratio drift 1.382x`
- `paired/move/hot-a15-a31-n1024 ratio drift 1.504x`
- `paired/move/hot-a15-a31-n129 ratio drift 1.493x`
- `paired/move/hot-a15-a31-n16 ratio drift 1.270x`
- `paired/move/hot-a15-a31-n31 ratio drift 1.503x`
- `paired/move/hot-a15-a31-n32 ratio drift 1.424x`
- `paired/move/hot-a15-a31-n33 ratio drift 1.400x`
- `paired/move/hot-a15-a31-n4096 ratio drift 1.512x`
- `paired/move/hot-a15-a31-n512 ratio drift 1.332x`
- `paired/move/hot-a15-a31-n65 ratio drift 1.570x`
- `paired/move/hot-a31-a15-n127 ratio drift 1.501x`
- `paired/move/hot-a31-a15-n128 ratio drift 1.492x`
- `paired/move/hot-a31-a15-n129 ratio drift 1.305x`
- `paired/move/hot-a31-a15-n16 ratio drift 1.270x`
- `paired/move/hot-a31-a15-n256 ratio drift 1.258x`
- `paired/move/hot-a31-a15-n33 ratio drift 1.286x`
- `paired/move/hot-a31-a15-n63 ratio drift 1.662x`
- `paired/move/hot-a31-a15-n64 ratio drift 1.617x`
- `paired/move/hot-a31-a15-n65 ratio drift 1.557x`
- `paired/move/overlap-forward-d63-n512 ratio drift 1.571x`

## All cases

| Program | Case | Layer | Oracle | Metric | moon-old stable/mean/max | moon-final stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| move | hot-a0-a0-n0 | rtl+memory | MATCH | tsc | 5.710/5.710/5.879 | 7.089/7.089/7.089 | 1.242 | 0.000 | 0.000 |
| move | hot-a0-a0-n1 | rtl+memory | MATCH | tsc | 6.271/6.271/6.942 | 7.163/7.163/7.163 | 1.155 | 0.000 | 0.000 |
| move | hot-a0-a0-n1023 | rtl+memory | MATCH | tsc | 59.347/59.347/60.473 | 29.423/29.423/29.423 | 0.496 | 0.000 | 0.000 |
| move | hot-a0-a0-n1024 | rtl+memory | MATCH | tsc | 59.502/59.502/60.473 | 27.945/27.945/28.101 | 0.470 | 0.000 | 0.000 |
| move | hot-a0-a0-n1025 | rtl+memory | MATCH | tsc | 59.346/59.346/60.473 | 30.241/30.241/30.242 | 0.510 | 0.000 | 0.000 |
| move | hot-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 156859.250/156859.250/157058.750 | 77515.034/77515.034/91727.250 | 0.494 | 0.000 | 0.000 |
| move | hot-a0-a0-n127 | rtl+memory | MATCH | tsc | 10.684/10.684/10.684 | 8.958/8.958/9.022 | 0.457 | 0.000 | 0.000 |
| move | hot-a0-a0-n128 | rtl+memory | MATCH | tsc | 12.526/12.526/14.369 | 8.894/8.894/8.894 | 0.726 | 0.000 | 0.000 |
| move | hot-a0-a0-n1280 | rtl+memory | MATCH | tsc | 72.725/72.725/73.911 | 33.510/33.510/33.511 | 0.461 | 0.000 | 0.000 |
| move | hot-a0-a0-n129 | rtl+memory | MATCH | tsc | 13.637/13.637/16.640 | 9.729/9.729/9.755 | 0.749 | 0.000 | 0.000 |
| move | hot-a0-a0-n131072 | rtl+memory | MATCH | tsc | 6888.616/6888.616/7085.028 | 7043.447/7043.447/7190.066 | 1.023 | 0.000 | 0.000 |
| move | hot-a0-a0-n15 | rtl+memory | MATCH | tsc | 7.406/7.406/9.152 | 4.860/4.860/4.868 | 0.695 | 0.000 | 0.000 |
| move | hot-a0-a0-n1535 | rtl+memory | MATCH | tsc | 85.723/85.723/87.351 | 42.388/42.388/42.502 | 0.495 | 0.000 | 0.000 |
| move | hot-a0-a0-n1536 | rtl+memory | MATCH | tsc | 85.724/85.724/87.350 | 40.152/40.152/40.469 | 0.468 | 0.000 | 0.000 |
| move | hot-a0-a0-n1537 | rtl+memory | MATCH | tsc | 85.500/85.500/87.349 | 43.203/43.203/43.320 | 0.506 | 0.000 | 0.000 |
| move | hot-a0-a0-n16 | rtl+memory | MATCH | tsc | 6.026/6.026/6.392 | 4.852/4.852/4.852 | 0.808 | 0.000 | 0.000 |
| move | hot-a0-a0-n160 | rtl+memory | MATCH | tsc | 14.162/14.162/15.791 | 9.729/9.729/9.755 | 0.696 | 0.000 | 0.000 |
| move | hot-a0-a0-n16384 | rtl+memory | MATCH | tsc | 455.906/455.906/469.112 | 461.905/461.905/462.629 | 1.014 | 0.000 | 0.000 |
| move | hot-a0-a0-n17 | rtl+memory | MATCH | tsc | 5.660/5.660/5.660 | 4.585/4.585/4.863 | 0.634 | 0.000 | 0.000 |
| move | hot-a0-a0-n192 | rtl+memory | MATCH | tsc | 15.269/15.269/16.719 | 10.512/10.512/10.512 | 0.695 | 0.000 | 0.000 |
| move | hot-a0-a0-n2 | rtl+memory | MATCH | tsc | 7.408/7.408/9.186 | 7.182/7.182/7.201 | 1.028 | 0.000 | 0.000 |
| move | hot-a0-a0-n2048 | rtl+memory | MATCH | tsc | 79.337/79.337/81.470 | 52.983/52.983/53.124 | 0.668 | 0.000 | 0.000 |
| move | hot-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 312592.750/312592.750/312597.500 | 169276.700/169276.700/187872.000 | 0.542 | 0.000 | 0.000 |
| move | hot-a0-a0-n24 | rtl+memory | MATCH | tsc | 6.883/6.883/8.137 | 4.469/4.469/4.851 | 0.661 | 0.000 | 0.000 |
| move | hot-a0-a0-n255 | rtl+memory | MATCH | tsc | 20.738/20.738/24.405 | 13.007/13.007/13.007 | 0.647 | 0.000 | 0.000 |
| move | hot-a0-a0-n256 | rtl+memory | MATCH | tsc | 18.744/18.744/20.417 | 13.130/13.130/13.322 | 0.705 | 0.000 | 0.000 |
| move | hot-a0-a0-n257 | rtl+memory | MATCH | tsc | 19.664/19.664/22.256 | 13.007/13.007/13.007 | 0.673 | 0.000 | 0.000 |
| move | hot-a0-a0-n262144 | rtl+memory | MATCH | tsc | 15463.342/15463.342/15661.542 | 15288.788/15288.788/15338.816 | 0.989 | 0.000 | 0.000 |
| move | hot-a0-a0-n3 | rtl+memory | MATCH | tsc | 6.618/6.618/7.605 | 7.182/7.182/7.200 | 1.110 | 0.000 | 0.000 |
| move | hot-a0-a0-n3072 | rtl+memory | MATCH | tsc | 105.246/105.246/108.346 | 78.655/78.655/78.866 | 0.748 | 0.000 | 0.000 |
| move | hot-a0-a0-n31 | rtl+memory | MATCH | tsc | 5.660/5.660/5.660 | 4.668/4.668/4.888 | 0.648 | 0.000 | 0.000 |
| move | hot-a0-a0-n32 | rtl+memory | MATCH | tsc | 6.141/6.141/6.621 | 4.458/4.458/4.851 | 0.725 | 0.000 | 0.000 |
| move | hot-a0-a0-n320 | rtl+memory | MATCH | tsc | 21.445/21.445/22.566 | 12.194/12.194/12.194 | 0.570 | 0.000 | 0.000 |
| move | hot-a0-a0-n32768 | rtl+memory | MATCH | tsc | 1671.404/1671.404/1716.620 | 1648.684/1648.684/1648.704 | 0.987 | 0.000 | 0.000 |
| move | hot-a0-a0-n33 | rtl+memory | MATCH | tsc | 9.126/9.126/10.944 | 6.469/6.469/6.469 | 0.738 | 0.000 | 0.000 |
| move | hot-a0-a0-n384 | rtl+memory | MATCH | tsc | 24.395/24.395/24.794 | 16.430/16.430/16.513 | 0.674 | 0.000 | 0.000 |
| move | hot-a0-a0-n4 | rtl+memory | MATCH | tsc | 6.413/6.413/7.974 | 6.384/6.384/6.400 | 1.057 | 0.000 | 0.000 |
| move | hot-a0-a0-n4096 | rtl+memory | MATCH | tsc | 131.689/131.689/135.228 | 106.296/106.296/107.711 | 0.807 | 0.000 | 0.000 |
| move | hot-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 627798.000/627798.000/631237.000 | 419615.000/419615.000/477451.000 | 0.668 | 0.000 | 0.000 |
| move | hot-a0-a0-n48 | rtl+memory | MATCH | tsc | 7.721/7.721/8.126 | 6.480/6.480/6.526 | 0.841 | 0.000 | 0.000 |
| move | hot-a0-a0-n5 | rtl+memory | MATCH | tsc | 4.860/4.860/4.860 | 6.384/6.384/6.401 | 0.697 | 0.000 | 0.000 |
| move | hot-a0-a0-n511 | rtl+memory | MATCH | tsc | 31.660/31.660/33.241 | 18.748/18.748/18.798 | 0.594 | 0.000 | 0.000 |
| move | hot-a0-a0-n512 | rtl+memory | MATCH | tsc | 30.577/30.577/31.076 | 18.599/18.599/18.697 | 0.608 | 0.000 | 0.000 |
| move | hot-a0-a0-n513 | rtl+memory | MATCH | tsc | 30.847/30.847/31.615 | 18.599/18.599/18.698 | 0.603 | 0.000 | 0.000 |
| move | hot-a0-a0-n524288 | rtl+memory | MATCH | tsc | 79773.611/79773.611/80072.333 | 32242.587/32242.587/32464.391 | 0.404 | 0.000 | 0.000 |
| move | hot-a0-a0-n63 | rtl+memory | MATCH | tsc | 7.366/7.366/7.366 | 6.486/6.486/6.503 | 0.414 | 0.000 | 0.000 |
| move | hot-a0-a0-n64 | rtl+memory | MATCH | tsc | 9.282/9.282/11.209 | 6.452/6.452/6.469 | 0.726 | 0.000 | 0.000 |
| move | hot-a0-a0-n640 | rtl+memory | MATCH | tsc | 37.189/37.189/37.796 | 21.194/21.194/21.250 | 0.570 | 0.000 | 0.000 |
| move | hot-a0-a0-n65 | rtl+memory | MATCH | tsc | 7.423/7.423/7.423 | 6.532/6.532/6.547 | 0.496 | 0.000 | 0.000 |
| move | hot-a0-a0-n65536 | rtl+memory | MATCH | tsc | 3458.536/3458.536/3552.376 | 3490.600/3490.600/3591.446 | 1.009 | 0.000 | 0.000 |
| move | hot-a0-a0-n7 | rtl+memory | MATCH | tsc | 4.859/4.859/4.859 | 6.400/6.400/6.400 | 0.697 | 0.000 | 0.000 |
| move | hot-a0-a0-n768 | rtl+memory | MATCH | tsc | 43.799/43.799/44.513 | 23.172/23.172/23.702 | 0.529 | 0.000 | 0.000 |
| move | hot-a0-a0-n8 | rtl+memory | MATCH | tsc | 5.631/5.631/6.411 | 6.436/6.436/6.505 | 1.164 | 0.000 | 0.000 |
| move | hot-a0-a0-n80 | rtl+memory | MATCH | tsc | 8.972/8.972/10.588 | 6.503/6.503/6.503 | 0.749 | 0.000 | 0.000 |
| move | hot-a0-a0-n8192 | rtl+memory | MATCH | tsc | 235.216/235.216/242.762 | 209.851/209.851/210.739 | 0.893 | 0.000 | 0.000 |
| move | hot-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 1262379.000/1262379.000/1273798.000 | 890425.500/890425.500/909948.000 | 0.706 | 0.000 | 0.000 |
| move | hot-a0-a0-n896 | rtl+memory | MATCH | tsc | 52.753/52.753/53.753 | 25.607/25.607/25.876 | 0.486 | 0.000 | 0.000 |
| move | hot-a0-a0-n9 | rtl+memory | MATCH | tsc | 7.421/7.421/9.152 | 4.840/4.840/4.853 | 0.689 | 0.000 | 0.000 |
| move | hot-a0-a0-n96 | rtl+memory | MATCH | tsc | 11.050/11.050/13.060 | 7.316/7.316/7.316 | 0.685 | 0.000 | 0.000 |
| move | hot-a0-a1-n1024 | rtl+memory | MATCH | tsc | 77.421/77.421/96.308 | 30.330/30.330/30.408 | 0.416 | 0.000 | 0.000 |
| move | hot-a0-a1-n127 | rtl+memory | MATCH | tsc | 10.626/10.626/10.626 | 8.918/8.918/8.942 | 0.380 | 0.000 | 0.000 |
| move | hot-a0-a1-n128 | rtl+memory | MATCH | tsc | 10.640/10.640/10.640 | 8.942/8.942/8.942 | 0.362 | 0.000 | 0.000 |
| move | hot-a0-a1-n129 | rtl+memory | MATCH | tsc | 10.841/10.841/10.841 | 11.388/11.388/11.541 | 0.484 | 0.000 | 0.000 |
| move | hot-a0-a1-n1536 | rtl+memory | MATCH | tsc | 84.556/84.556/84.556 | 43.335/43.335/43.566 | 0.408 | 0.000 | 0.000 |
| move | hot-a0-a1-n16 | rtl+memory | MATCH | tsc | 7.023/7.023/8.445 | 5.026/5.026/5.199 | 0.741 | 0.000 | 0.000 |
| move | hot-a0-a1-n256 | rtl+memory | MATCH | tsc | 22.194/22.194/27.220 | 13.042/13.042/13.077 | 0.619 | 0.000 | 0.000 |
| move | hot-a0-a1-n31 | rtl+memory | MATCH | tsc | 5.630/5.630/5.630 | 4.577/4.577/4.833 | 0.400 | 0.000 | 0.000 |
| move | hot-a0-a1-n32 | rtl+memory | MATCH | tsc | 7.288/7.288/8.915 | 4.865/4.865/4.877 | 0.702 | 0.000 | 0.000 |
| move | hot-a0-a1-n33 | rtl+memory | MATCH | tsc | 10.595/10.595/12.532 | 9.023/9.023/9.149 | 0.879 | 0.000 | 0.000 |
| move | hot-a0-a1-n4096 | rtl+memory | MATCH | tsc | 3926.542/3926.542/4178.320 | 138.732/138.732/139.103 | 0.035 | 0.000 | 0.000 |
| move | hot-a0-a1-n512 | rtl+memory | MATCH | tsc | 40.064/40.064/50.038 | 19.619/19.619/19.619 | 0.522 | 0.000 | 0.000 |
| move | hot-a0-a1-n63 | rtl+memory | MATCH | tsc | 7.580/7.580/7.580 | 6.577/6.577/6.650 | 0.467 | 0.000 | 0.000 |
| move | hot-a0-a1-n64 | rtl+memory | MATCH | tsc | 7.372/7.372/7.372 | 7.001/7.001/7.042 | 0.503 | 0.000 | 0.000 |
| move | hot-a0-a1-n65 | rtl+memory | MATCH | tsc | 8.260/8.260/8.260 | 7.150/7.150/7.171 | 0.341 | 0.000 | 0.000 |
| move | hot-a0-a128-n1024 | rtl+memory | MATCH | tsc | 58.533/58.533/58.535 | 27.790/27.790/27.790 | 0.475 | 0.000 | 0.000 |
| move | hot-a0-a128-n127 | rtl+memory | MATCH | tsc | 10.597/10.597/10.625 | 8.824/8.824/8.847 | 0.833 | 0.000 | 0.000 |
| move | hot-a0-a128-n128 | rtl+memory | MATCH | tsc | 10.568/10.568/10.568 | 8.824/8.824/8.847 | 0.835 | 0.000 | 0.000 |
| move | hot-a0-a128-n129 | rtl+memory | MATCH | tsc | 13.110/13.110/15.593 | 9.652/9.652/9.652 | 0.764 | 0.000 | 0.000 |
| move | hot-a0-a128-n1536 | rtl+memory | MATCH | tsc | 84.778/84.778/85.006 | 40.049/40.049/40.049 | 0.472 | 0.000 | 0.000 |
| move | hot-a0-a128-n16 | rtl+memory | MATCH | tsc | 5.630/5.630/5.660 | 4.826/4.826/4.826 | 0.857 | 0.000 | 0.000 |
| move | hot-a0-a128-n256 | rtl+memory | MATCH | tsc | 17.118/17.118/17.164 | 12.129/12.129/12.129 | 0.709 | 0.000 | 0.000 |
| move | hot-a0-a128-n31 | rtl+memory | MATCH | tsc | 5.645/5.645/5.660 | 4.891/4.891/4.895 | 0.866 | 0.000 | 0.000 |
| move | hot-a0-a128-n32 | rtl+memory | MATCH | tsc | 5.645/5.645/5.660 | 4.826/4.826/4.826 | 0.855 | 0.000 | 0.000 |
| move | hot-a0-a128-n33 | rtl+memory | MATCH | tsc | 7.297/7.297/7.316 | 6.452/6.452/6.469 | 0.884 | 0.000 | 0.000 |
| move | hot-a0-a128-n4096 | rtl+memory | MATCH | tsc | 130.938/130.938/133.056 | 105.158/105.158/105.441 | 0.803 | 0.000 | 0.000 |
| move | hot-a0-a128-n512 | rtl+memory | MATCH | tsc | 30.160/30.160/30.241 | 17.885/17.885/17.885 | 0.593 | 0.000 | 0.000 |
| move | hot-a0-a128-n63 | rtl+memory | MATCH | tsc | 7.434/7.434/7.511 | 6.481/6.481/6.494 | 0.872 | 0.000 | 0.000 |
| move | hot-a0-a128-n64 | rtl+memory | MATCH | tsc | 7.356/7.356/7.356 | 6.434/6.434/6.434 | 0.875 | 0.000 | 0.000 |
| move | hot-a0-a128-n65 | rtl+memory | MATCH | tsc | 7.390/7.390/7.460 | 6.469/6.469/6.469 | 0.875 | 0.000 | 0.000 |
| move | hot-a0-a2048-n1024 | rtl+memory | MATCH | tsc | 58.532/58.532/58.532 | 27.789/27.789/27.790 | 0.475 | 0.000 | 0.000 |
| move | hot-a0-a2048-n127 | rtl+memory | MATCH | tsc | 10.597/10.597/10.625 | 8.824/8.824/8.848 | 0.833 | 0.000 | 0.000 |
| move | hot-a0-a2048-n128 | rtl+memory | MATCH | tsc | 10.569/10.569/10.569 | 8.801/8.801/8.801 | 0.833 | 0.000 | 0.000 |
| move | hot-a0-a2048-n129 | rtl+memory | MATCH | tsc | 10.597/10.597/10.625 | 9.652/9.652/9.652 | 0.911 | 0.000 | 0.000 |
| move | hot-a0-a2048-n1536 | rtl+memory | MATCH | tsc | 85.006/85.006/85.464 | 39.942/39.942/40.049 | 0.470 | 0.000 | 0.000 |
| move | hot-a0-a2048-n16 | rtl+memory | MATCH | tsc | 5.645/5.645/5.660 | 4.813/4.813/4.826 | 0.853 | 0.000 | 0.000 |
| move | hot-a0-a2048-n256 | rtl+memory | MATCH | tsc | 17.072/17.072/17.072 | 12.129/12.129/12.129 | 0.710 | 0.000 | 0.000 |
| move | hot-a0-a2048-n31 | rtl+memory | MATCH | tsc | 5.744/5.744/5.797 | 4.864/4.864/4.869 | 0.847 | 0.000 | 0.000 |
| move | hot-a0-a2048-n32 | rtl+memory | MATCH | tsc | 5.645/5.645/5.660 | 4.813/4.813/4.826 | 0.853 | 0.000 | 0.000 |
| move | hot-a0-a2048-n33 | rtl+memory | MATCH | tsc | 7.316/7.316/7.316 | 6.558/6.558/6.648 | 0.896 | 0.000 | 0.000 |
| move | hot-a0-a2048-n4096 | rtl+memory | MATCH | tsc | 128.482/128.482/128.819 | 104.869/104.869/104.870 | 0.816 | 0.000 | 0.000 |
| move | hot-a0-a2048-n512 | rtl+memory | MATCH | tsc | 30.079/30.079/30.079 | 17.789/17.789/17.789 | 0.591 | 0.000 | 0.000 |
| move | hot-a0-a2048-n63 | rtl+memory | MATCH | tsc | 7.336/7.336/7.356 | 6.486/6.486/6.503 | 0.884 | 0.000 | 0.000 |
| move | hot-a0-a2048-n64 | rtl+memory | MATCH | tsc | 7.469/7.469/7.621 | 6.417/6.417/6.434 | 0.860 | 0.000 | 0.000 |
| move | hot-a0-a2048-n65 | rtl+memory | MATCH | tsc | 7.357/7.357/7.397 | 6.469/6.469/6.469 | 0.879 | 0.000 | 0.000 |
| move | hot-a1-a0-n1024 | rtl+memory | MATCH | tsc | 58.534/58.534/58.846 | 27.865/27.865/27.940 | 0.476 | 0.000 | 0.000 |
| move | hot-a1-a0-n127 | rtl+memory | MATCH | tsc | 10.629/10.629/10.629 | 8.895/8.895/8.895 | 0.414 | 0.000 | 0.000 |
| move | hot-a1-a0-n128 | rtl+memory | MATCH | tsc | 10.878/10.878/10.878 | 8.918/8.918/8.942 | 0.456 | 0.000 | 0.000 |
| move | hot-a1-a0-n129 | rtl+memory | MATCH | tsc | 10.656/10.656/10.656 | 9.755/9.755/9.755 | 0.487 | 0.000 | 0.000 |
| move | hot-a1-a0-n1536 | rtl+memory | MATCH | tsc | 84.547/84.547/84.549 | 40.572/40.572/40.869 | 0.480 | 0.000 | 0.000 |
| move | hot-a1-a0-n16 | rtl+memory | MATCH | tsc | 6.493/6.493/7.356 | 4.839/4.839/4.851 | 0.758 | 0.000 | 0.000 |
| move | hot-a1-a0-n256 | rtl+memory | MATCH | tsc | 21.654/21.654/26.237 | 13.076/13.076/13.144 | 0.633 | 0.000 | 0.000 |
| move | hot-a1-a0-n31 | rtl+memory | MATCH | tsc | 5.630/5.630/5.630 | 4.580/4.580/4.861 | 0.411 | 0.000 | 0.000 |
| move | hot-a1-a0-n32 | rtl+memory | MATCH | tsc | 6.445/6.445/7.260 | 4.456/4.456/4.826 | 0.710 | 0.000 | 0.000 |
| move | hot-a1-a0-n33 | rtl+memory | MATCH | tsc | 9.270/9.270/11.234 | 6.486/6.486/6.503 | 0.732 | 0.000 | 0.000 |
| move | hot-a1-a0-n4096 | rtl+memory | MATCH | tsc | 173.962/173.962/174.415 | 105.444/105.444/106.008 | 0.606 | 0.000 | 0.000 |
| move | hot-a1-a0-n512 | rtl+memory | MATCH | tsc | 30.858/30.858/31.071 | 18.698/18.698/18.698 | 0.606 | 0.000 | 0.000 |
| move | hot-a1-a0-n63 | rtl+memory | MATCH | tsc | 7.366/7.366/7.366 | 6.486/6.486/6.503 | 0.421 | 0.000 | 0.000 |
| move | hot-a1-a0-n64 | rtl+memory | MATCH | tsc | 7.316/7.316/7.316 | 6.560/6.560/6.582 | 0.475 | 0.000 | 0.000 |
| move | hot-a1-a0-n65 | rtl+memory | MATCH | tsc | 7.383/7.383/7.383 | 6.531/6.531/6.548 | 0.485 | 0.000 | 0.000 |
| move | hot-a1-a1-n1024 | rtl+memory | MATCH | tsc | 58.376/58.376/58.532 | 30.161/30.161/30.242 | 0.517 | 0.000 | 0.000 |
| move | hot-a1-a1-n127 | rtl+memory | MATCH | tsc | 13.607/13.607/16.588 | 8.918/8.918/8.942 | 0.688 | 0.000 | 0.000 |
| move | hot-a1-a1-n128 | rtl+memory | MATCH | tsc | 13.972/13.972/17.260 | 8.917/8.917/8.964 | 0.675 | 0.000 | 0.000 |
| move | hot-a1-a1-n129 | rtl+memory | MATCH | tsc | 14.085/14.085/17.358 | 11.273/11.273/11.371 | 0.844 | 0.000 | 0.000 |
| move | hot-a1-a1-n1536 | rtl+memory | MATCH | tsc | 84.547/84.547/84.547 | 43.202/43.202/43.318 | 0.511 | 0.000 | 0.000 |
| move | hot-a1-a1-n16 | rtl+memory | MATCH | tsc | 6.626/6.626/7.622 | 4.863/4.863/4.899 | 0.750 | 0.000 | 0.000 |
| move | hot-a1-a1-n256 | rtl+memory | MATCH | tsc | 19.350/19.350/21.627 | 13.368/13.368/13.459 | 0.701 | 0.000 | 0.000 |
| move | hot-a1-a1-n31 | rtl+memory | MATCH | tsc | 5.630/5.630/5.630 | 4.592/4.592/4.858 | 0.392 | 0.000 | 0.000 |
| move | hot-a1-a1-n32 | rtl+memory | MATCH | tsc | 6.428/6.428/7.950 | 4.922/4.922/4.940 | 0.812 | 0.000 | 0.000 |
| move | hot-a1-a1-n33 | rtl+memory | MATCH | tsc | 10.473/10.473/12.221 | 8.982/8.982/9.042 | 0.881 | 0.000 | 0.000 |
| move | hot-a1-a1-n4096 | rtl+memory | MATCH | tsc | 138.135/138.135/138.500 | 127.438/127.438/127.777 | 0.923 | 0.000 | 0.000 |
| move | hot-a1-a1-n512 | rtl+memory | MATCH | tsc | 30.268/30.268/30.618 | 19.663/19.663/19.709 | 0.650 | 0.000 | 0.000 |
| move | hot-a1-a1-n63 | rtl+memory | MATCH | tsc | 7.540/7.540/7.540 | 6.543/6.543/6.582 | 0.503 | 0.000 | 0.000 |
| move | hot-a1-a1-n64 | rtl+memory | MATCH | tsc | 8.306/8.306/8.306 | 7.212/7.212/7.248 | 0.505 | 0.000 | 0.000 |
| move | hot-a1-a1-n65 | rtl+memory | MATCH | tsc | 8.231/8.231/8.231 | 7.233/7.233/7.256 | 0.503 | 0.000 | 0.000 |
| move | hot-a128-a0-n1024 | rtl+memory | MATCH | tsc | 58.532/58.532/58.533 | 27.789/27.789/27.790 | 0.475 | 0.000 | 0.000 |
| move | hot-a128-a0-n127 | rtl+memory | MATCH | tsc | 10.654/10.654/10.682 | 8.847/8.847/8.847 | 0.830 | 0.000 | 0.000 |
| move | hot-a128-a0-n128 | rtl+memory | MATCH | tsc | 10.625/10.625/10.625 | 8.824/8.824/8.847 | 0.830 | 0.000 | 0.000 |
| move | hot-a128-a0-n129 | rtl+memory | MATCH | tsc | 11.961/11.961/13.164 | 10.893/10.893/12.083 | 0.910 | 0.000 | 0.000 |
| move | hot-a128-a0-n1536 | rtl+memory | MATCH | tsc | 84.549/84.549/84.552 | 40.050/40.050/40.051 | 0.474 | 0.000 | 0.000 |
| move | hot-a128-a0-n16 | rtl+memory | MATCH | tsc | 5.630/5.630/5.660 | 4.813/4.813/4.826 | 0.855 | 0.000 | 0.000 |
| move | hot-a128-a0-n256 | rtl+memory | MATCH | tsc | 17.118/17.118/17.164 | 12.097/12.097/12.129 | 0.707 | 0.000 | 0.000 |
| move | hot-a128-a0-n31 | rtl+memory | MATCH | tsc | 5.322/5.322/5.713 | 4.873/4.873/4.894 | 0.920 | 0.000 | 0.000 |
| move | hot-a128-a0-n32 | rtl+memory | MATCH | tsc | 5.645/5.645/5.660 | 4.813/4.813/4.826 | 0.853 | 0.000 | 0.000 |
| move | hot-a128-a0-n33 | rtl+memory | MATCH | tsc | 7.410/7.410/7.543 | 6.452/6.452/6.469 | 0.871 | 0.000 | 0.000 |
| move | hot-a128-a0-n4096 | rtl+memory | MATCH | tsc | 128.149/128.149/128.152 | 104.881/104.881/104.881 | 0.818 | 0.000 | 0.000 |
| move | hot-a128-a0-n512 | rtl+memory | MATCH | tsc | 30.160/30.160/30.240 | 17.837/17.837/17.885 | 0.591 | 0.000 | 0.000 |
| move | hot-a128-a0-n63 | rtl+memory | MATCH | tsc | 7.356/7.356/7.356 | 6.452/6.452/6.469 | 0.877 | 0.000 | 0.000 |
| move | hot-a128-a0-n64 | rtl+memory | MATCH | tsc | 7.336/7.336/7.356 | 6.452/6.452/6.469 | 0.879 | 0.000 | 0.000 |
| move | hot-a128-a0-n65 | rtl+memory | MATCH | tsc | 7.337/7.337/7.357 | 6.469/6.469/6.469 | 0.882 | 0.000 | 0.000 |
| move | hot-a15-a31-n1024 | rtl+memory | MATCH | tsc | 73.521/73.521/88.509 | 30.330/30.330/30.412 | 0.430 | 0.000 | 0.000 |
| move | hot-a15-a31-n127 | rtl+memory | MATCH | tsc | 10.991/10.991/10.991 | 9.204/9.204/9.481 | 0.374 | 0.000 | 0.000 |
| move | hot-a15-a31-n128 | rtl+memory | MATCH | tsc | 10.809/10.809/10.809 | 8.954/8.954/8.971 | 0.357 | 0.000 | 0.000 |
| move | hot-a15-a31-n129 | rtl+memory | MATCH | tsc | 13.289/13.289/15.953 | 9.729/9.729/9.755 | 0.762 | 0.000 | 0.000 |
| move | hot-a15-a31-n1536 | rtl+memory | MATCH | tsc | 84.552/84.552/84.552 | 43.328/43.328/43.332 | 0.282 | 0.000 | 0.000 |
| move | hot-a15-a31-n16 | rtl+memory | MATCH | tsc | 6.430/6.430/7.229 | 4.852/4.852/4.877 | 0.766 | 0.000 | 0.000 |
| move | hot-a15-a31-n256 | rtl+memory | MATCH | tsc | 17.074/17.074/17.074 | 13.418/13.418/13.538 | 0.454 | 0.000 | 0.000 |
| move | hot-a15-a31-n31 | rtl+memory | MATCH | tsc | 7.083/7.083/8.506 | 4.851/4.851/4.852 | 0.714 | 0.000 | 0.000 |
| move | hot-a15-a31-n32 | rtl+memory | MATCH | tsc | 5.932/5.932/6.985 | 4.864/4.864/4.877 | 0.846 | 0.000 | 0.000 |
| move | hot-a15-a31-n33 | rtl+memory | MATCH | tsc | 8.755/8.755/10.119 | 6.576/6.576/6.649 | 0.771 | 0.000 | 0.000 |
| move | hot-a15-a31-n4096 | rtl+memory | MATCH | tsc | 4395.148/4395.148/5303.490 | 144.960/144.960/145.390 | 0.034 | 0.000 | 0.000 |
| move | hot-a15-a31-n512 | rtl+memory | MATCH | tsc | 36.896/36.896/43.712 | 19.638/19.638/19.638 | 0.761 | 0.000 | 0.000 |
| move | hot-a15-a31-n63 | rtl+memory | MATCH | tsc | 8.827/8.827/8.827 | 7.185/7.185/7.247 | 0.301 | 0.000 | 0.000 |
| move | hot-a15-a31-n64 | rtl+memory | MATCH | tsc | 8.924/8.924/8.924 | 7.221/7.221/7.286 | 0.301 | 0.000 | 0.000 |
| move | hot-a15-a31-n65 | rtl+memory | MATCH | tsc | 9.987/9.987/12.226 | 6.546/6.546/6.563 | 0.690 | 0.000 | 0.000 |
| move | hot-a2048-a0-n1024 | rtl+memory | MATCH | tsc | 58.378/58.378/58.532 | 27.715/27.715/27.790 | 0.475 | 0.000 | 0.000 |
| move | hot-a2048-a0-n127 | rtl+memory | MATCH | tsc | 10.625/10.625/10.682 | 8.847/8.847/8.847 | 0.833 | 0.000 | 0.000 |
| move | hot-a2048-a0-n128 | rtl+memory | MATCH | tsc | 10.596/10.596/10.625 | 8.824/8.824/8.847 | 0.833 | 0.000 | 0.000 |
| move | hot-a2048-a0-n129 | rtl+memory | MATCH | tsc | 10.673/10.673/10.701 | 9.703/9.703/9.703 | 0.909 | 0.000 | 0.000 |
| move | hot-a2048-a0-n1536 | rtl+memory | MATCH | tsc | 84.547/84.547/84.549 | 39.941/39.941/40.047 | 0.472 | 0.000 | 0.000 |
| move | hot-a2048-a0-n16 | rtl+memory | MATCH | tsc | 5.645/5.645/5.660 | 4.826/4.826/4.852 | 0.855 | 0.000 | 0.000 |
| move | hot-a2048-a0-n256 | rtl+memory | MATCH | tsc | 17.072/17.072/17.072 | 12.181/12.181/12.232 | 0.714 | 0.000 | 0.000 |
| move | hot-a2048-a0-n31 | rtl+memory | MATCH | tsc | 5.645/5.645/5.660 | 4.876/4.876/4.883 | 0.864 | 0.000 | 0.000 |
| move | hot-a2048-a0-n32 | rtl+memory | MATCH | tsc | 5.630/5.630/5.630 | 4.813/4.813/4.826 | 0.855 | 0.000 | 0.000 |
| move | hot-a2048-a0-n33 | rtl+memory | MATCH | tsc | 7.297/7.297/7.316 | 6.469/6.469/6.469 | 0.887 | 0.000 | 0.000 |
| move | hot-a2048-a0-n4096 | rtl+memory | MATCH | tsc | 128.142/128.142/128.146 | 106.762/106.762/108.648 | 0.833 | 0.000 | 0.000 |
| move | hot-a2048-a0-n512 | rtl+memory | MATCH | tsc | 30.160/30.160/30.240 | 17.837/17.837/17.885 | 0.591 | 0.000 | 0.000 |
| move | hot-a2048-a0-n63 | rtl+memory | MATCH | tsc | 7.336/7.336/7.356 | 6.452/6.452/6.469 | 0.879 | 0.000 | 0.000 |
| move | hot-a2048-a0-n64 | rtl+memory | MATCH | tsc | 7.336/7.336/7.356 | 6.434/6.434/6.434 | 0.877 | 0.000 | 0.000 |
| move | hot-a2048-a0-n65 | rtl+memory | MATCH | tsc | 7.369/7.369/7.381 | 6.473/6.473/6.477 | 0.878 | 0.000 | 0.000 |
| move | hot-a31-a15-n1024 | rtl+memory | MATCH | tsc | 59.359/59.359/60.187 | 30.419/30.419/30.420 | 0.513 | 0.000 | 0.000 |
| move | hot-a31-a15-n127 | rtl+memory | MATCH | tsc | 13.394/13.394/16.079 | 8.963/8.963/8.963 | 0.697 | 0.000 | 0.000 |
| move | hot-a31-a15-n128 | rtl+memory | MATCH | tsc | 13.408/13.408/16.098 | 8.939/8.939/8.967 | 0.694 | 0.000 | 0.000 |
| move | hot-a31-a15-n129 | rtl+memory | MATCH | tsc | 12.323/12.323/14.020 | 9.756/9.756/9.808 | 0.806 | 0.000 | 0.000 |
| move | hot-a31-a15-n1536 | rtl+memory | MATCH | tsc | 84.321/84.321/84.544 | 43.275/43.275/43.331 | 0.513 | 0.000 | 0.000 |
| move | hot-a31-a15-n16 | rtl+memory | MATCH | tsc | 6.410/6.410/7.190 | 4.865/4.865/4.878 | 0.770 | 0.000 | 0.000 |
| move | hot-a31-a15-n256 | rtl+memory | MATCH | tsc | 19.264/19.264/21.456 | 13.372/13.372/13.378 | 0.703 | 0.000 | 0.000 |
| move | hot-a31-a15-n31 | rtl+memory | MATCH | tsc | 6.393/6.393/7.126 | 4.865/4.865/4.904 | 0.770 | 0.000 | 0.000 |
| move | hot-a31-a15-n32 | rtl+memory | MATCH | tsc | 6.396/6.396/7.163 | 4.917/4.917/4.983 | 0.779 | 0.000 | 0.000 |
| move | hot-a31-a15-n33 | rtl+memory | MATCH | tsc | 8.319/8.319/9.342 | 6.518/6.518/6.532 | 0.796 | 0.000 | 0.000 |
| move | hot-a31-a15-n4096 | rtl+memory | MATCH | tsc | 182.387/182.387/185.338 | 126.972/126.972/126.976 | 0.696 | 0.000 | 0.000 |
| move | hot-a31-a15-n512 | rtl+memory | MATCH | tsc | 30.080/30.080/30.241 | 20.372/20.372/20.372 | 0.681 | 0.000 | 0.000 |
| move | hot-a31-a15-n63 | rtl+memory | MATCH | tsc | 7.971/7.971/7.971 | 7.192/7.192/7.234 | 0.718 | 0.000 | 0.000 |
| move | hot-a31-a15-n64 | rtl+memory | MATCH | tsc | 10.497/10.497/12.981 | 7.157/7.157/7.163 | 0.722 | 0.000 | 0.000 |
| move | hot-a31-a15-n65 | rtl+memory | MATCH | tsc | 9.406/9.406/11.455 | 6.503/6.503/6.503 | 0.726 | 0.000 | 0.000 |
| move | overlap-backward-d1-n1024 | rtl+memory | MATCH | tsc | 62.709/62.709/63.083 | 48.837/48.837/48.894 | 0.779 | 0.000 | 0.000 |
| move | overlap-backward-d1-n128 | rtl+memory | MATCH | tsc | 28.473/28.473/28.551 | 21.321/21.321/21.376 | 0.749 | 0.000 | 0.000 |
| move | overlap-backward-d1-n1536 | rtl+memory | MATCH | tsc | 94.910/94.910/94.910 | 61.049/61.049/61.210 | 0.643 | 0.000 | 0.000 |
| move | overlap-backward-d1-n2048 | rtl+memory | MATCH | tsc | 130.491/130.491/131.196 | 73.812/73.812/74.011 | 0.566 | 0.000 | 0.000 |
| move | overlap-backward-d1-n256 | rtl+memory | MATCH | tsc | 30.936/30.936/31.103 | 29.493/29.493/29.781 | 0.953 | 0.000 | 0.000 |
| move | overlap-backward-d1-n33 | rtl+memory | MATCH | tsc | 22.901/22.901/22.961 | 22.783/22.783/22.841 | 0.995 | 0.000 | 0.000 |
| move | overlap-backward-d1-n4096 | rtl+memory | MATCH | tsc | 245.629/245.629/246.920 | 145.623/145.623/145.736 | 0.593 | 0.000 | 0.000 |
| move | overlap-backward-d1-n512 | rtl+memory | MATCH | tsc | 37.798/37.798/37.997 | 37.343/37.343/37.593 | 0.988 | 0.000 | 0.000 |
| move | overlap-backward-d1-n64 | rtl+memory | MATCH | tsc | 24.543/24.543/24.575 | 21.319/21.319/21.378 | 0.869 | 0.000 | 0.000 |
| move | overlap-backward-d1-n65 | rtl+memory | MATCH | tsc | 26.849/26.849/26.919 | 21.879/21.879/22.150 | 0.815 | 0.000 | 0.000 |
| move | overlap-backward-d1-n65536 | rtl+memory | MATCH | tsc | 3757.454/3757.454/3768.333 | 2699.213/2699.213/2714.458 | 0.718 | 0.000 | 0.000 |
| move | overlap-backward-d16-n1024 | rtl+memory | MATCH | tsc | 52.559/52.559/52.559 | 41.425/41.425/41.437 | 0.788 | 0.000 | 0.000 |
| move | overlap-backward-d16-n128 | rtl+memory | MATCH | tsc | 11.226/11.226/11.257 | 16.777/16.777/16.902 | 1.495 | 0.000 | 0.000 |
| move | overlap-backward-d16-n1536 | rtl+memory | MATCH | tsc | 78.018/78.018/78.018 | 54.149/54.149/54.688 | 0.694 | 0.000 | 0.000 |
| move | overlap-backward-d16-n2048 | rtl+memory | MATCH | tsc | 104.034/104.034/104.310 | 66.590/66.590/66.765 | 0.640 | 0.000 | 0.000 |
| move | overlap-backward-d16-n256 | rtl+memory | MATCH | tsc | 16.673/16.673/16.752 | 22.152/22.152/22.196 | 1.329 | 0.000 | 0.000 |
| move | overlap-backward-d16-n33 | rtl+memory | MATCH | tsc | 21.267/21.267/21.377 | 22.054/22.054/22.054 | 1.037 | 0.000 | 0.000 |
| move | overlap-backward-d16-n4096 | rtl+memory | MATCH | tsc | 207.263/207.263/207.812 | 136.903/136.903/136.903 | 0.661 | 0.000 | 0.000 |
| move | overlap-backward-d16-n512 | rtl+memory | MATCH | tsc | 28.134/28.134/28.257 | 28.827/28.827/28.908 | 1.025 | 0.000 | 0.000 |
| move | overlap-backward-d16-n64 | rtl+memory | MATCH | tsc | 8.195/8.195/8.217 | 6.434/6.434/6.434 | 0.785 | 0.000 | 0.000 |
| move | overlap-backward-d16-n65 | rtl+memory | MATCH | tsc | 18.835/18.835/18.901 | 15.043/15.043/15.043 | 0.799 | 0.000 | 0.000 |
| move | overlap-backward-d16-n65536 | rtl+memory | MATCH | tsc | 3344.624/3344.624/3362.581 | 2683.208/2683.208/2692.133 | 0.802 | 0.000 | 0.000 |
| move | overlap-backward-d63-n1024 | rtl+memory | MATCH | tsc | 53.013/53.013/53.072 | 36.702/36.702/36.915 | 0.692 | 0.000 | 0.000 |
| move | overlap-backward-d63-n128 | rtl+memory | MATCH | tsc | 24.913/24.913/24.968 | 19.690/19.690/19.690 | 0.790 | 0.000 | 0.000 |
| move | overlap-backward-d63-n1536 | rtl+memory | MATCH | tsc | 78.762/78.762/78.960 | 49.508/49.508/49.666 | 0.629 | 0.000 | 0.000 |
| move | overlap-backward-d63-n2048 | rtl+memory | MATCH | tsc | 104.311/104.311/104.865 | 62.146/62.146/62.301 | 0.596 | 0.000 | 0.000 |
| move | overlap-backward-d63-n256 | rtl+memory | MATCH | tsc | 27.077/27.077/27.231 | 26.205/26.205/26.540 | 0.968 | 0.000 | 0.000 |
| move | overlap-backward-d63-n4096 | rtl+memory | MATCH | tsc | 209.557/209.557/210.099 | 129.503/129.503/130.191 | 0.618 | 0.000 | 0.000 |
| move | overlap-backward-d63-n512 | rtl+memory | MATCH | tsc | 33.193/33.193/33.210 | 28.330/28.330/29.093 | 0.854 | 0.000 | 0.000 |
| move | overlap-backward-d63-n64 | rtl+memory | MATCH | tsc | 22.842/22.842/22.960 | 19.927/19.927/20.030 | 0.872 | 0.000 | 0.000 |
| move | overlap-backward-d63-n65 | rtl+memory | MATCH | tsc | 24.480/24.480/24.543 | 21.266/21.266/21.266 | 0.869 | 0.000 | 0.000 |
| move | overlap-backward-d63-n65536 | rtl+memory | MATCH | tsc | 3738.227/3738.227/3754.044 | 2684.012/2684.012/2685.533 | 0.718 | 0.000 | 0.000 |
| move | overlap-forward-d1-n1024 | rtl+memory | MATCH | tsc | 58.622/58.622/58.714 | 28.111/28.111/28.248 | 0.480 | 0.000 | 0.000 |
| move | overlap-forward-d1-n128 | rtl+memory | MATCH | tsc | 22.765/22.765/22.889 | 17.994/17.994/18.096 | 0.790 | 0.000 | 0.000 |
| move | overlap-forward-d1-n1536 | rtl+memory | MATCH | tsc | 90.308/90.308/96.521 | 39.858/39.858/39.867 | 0.443 | 0.000 | 0.000 |
| move | overlap-forward-d1-n2048 | rtl+memory | MATCH | tsc | 98.311/98.311/98.452 | 52.701/52.701/52.841 | 0.536 | 0.000 | 0.000 |
| move | overlap-forward-d1-n256 | rtl+memory | MATCH | tsc | 26.491/26.491/26.618 | 21.499/21.499/21.549 | 0.812 | 0.000 | 0.000 |
| move | overlap-forward-d1-n33 | rtl+memory | MATCH | tsc | 22.521/22.521/22.580 | 21.660/21.660/21.660 | 0.962 | 0.000 | 0.000 |
| move | overlap-forward-d1-n4096 | rtl+memory | MATCH | tsc | 174.932/174.932/175.799 | 105.055/105.055/105.799 | 0.601 | 0.000 | 0.000 |
| move | overlap-forward-d1-n512 | rtl+memory | MATCH | tsc | 31.451/31.451/32.178 | 22.153/22.153/22.314 | 0.705 | 0.000 | 0.000 |
| move | overlap-forward-d1-n64 | rtl+memory | MATCH | tsc | 19.516/19.516/19.658 | 16.542/16.542/16.543 | 0.848 | 0.000 | 0.000 |
| move | overlap-forward-d1-n65 | rtl+memory | MATCH | tsc | 21.035/21.035/21.603 | 16.635/16.635/16.721 | 0.792 | 0.000 | 0.000 |
| move | overlap-forward-d1-n65536 | rtl+memory | MATCH | tsc | 2830.397/2830.397/2833.978 | 2618.011/2618.011/2639.291 | 0.925 | 0.000 | 0.000 |
| move | overlap-forward-d16-n1024 | rtl+memory | MATCH | tsc | 58.624/58.624/58.717 | 28.024/28.024/28.409 | 0.478 | 0.000 | 0.000 |
| move | overlap-forward-d16-n128 | rtl+memory | MATCH | tsc | 11.080/11.080/11.450 | 17.937/17.937/17.984 | 1.621 | 0.000 | 0.000 |
| move | overlap-forward-d16-n1536 | rtl+memory | MATCH | tsc | 90.252/90.252/96.408 | 39.970/39.970/40.089 | 0.445 | 0.000 | 0.000 |
| move | overlap-forward-d16-n2048 | rtl+memory | MATCH | tsc | 97.235/97.235/97.481 | 53.220/53.220/53.599 | 0.547 | 0.000 | 0.000 |
| move | overlap-forward-d16-n256 | rtl+memory | MATCH | tsc | 17.719/17.719/18.274 | 21.639/21.639/22.166 | 1.222 | 0.000 | 0.000 |
| move | overlap-forward-d16-n33 | rtl+memory | MATCH | tsc | 15.835/15.835/15.917 | 22.300/22.300/22.371 | 1.408 | 0.000 | 0.000 |
| move | overlap-forward-d16-n4096 | rtl+memory | MATCH | tsc | 172.546/172.546/172.596 | 104.598/104.598/104.875 | 0.606 | 0.000 | 0.000 |
| move | overlap-forward-d16-n512 | rtl+memory | MATCH | tsc | 30.402/30.402/30.564 | 22.311/22.311/22.641 | 0.734 | 0.000 | 0.000 |
| move | overlap-forward-d16-n64 | rtl+memory | MATCH | tsc | 7.742/7.742/8.129 | 6.435/6.435/6.435 | 0.833 | 0.000 | 0.000 |
| move | overlap-forward-d16-n65 | rtl+memory | MATCH | tsc | 17.073/17.073/17.091 | 16.540/16.540/16.540 | 0.969 | 0.000 | 0.000 |
| move | overlap-forward-d16-n65536 | rtl+memory | MATCH | tsc | 2813.578/2813.578/2821.606 | 2607.651/2607.651/2611.714 | 0.927 | 0.000 | 0.000 |
| move | overlap-forward-d63-n1024 | rtl+memory | MATCH | tsc | 58.780/58.780/59.028 | 28.390/28.390/28.400 | 0.483 | 0.000 | 0.000 |
| move | overlap-forward-d63-n128 | rtl+memory | MATCH | tsc | 19.948/19.948/20.021 | 18.900/18.900/18.912 | 0.948 | 0.000 | 0.000 |
| move | overlap-forward-d63-n1536 | rtl+memory | MATCH | tsc | 84.501/84.501/84.904 | 40.282/40.282/40.292 | 0.477 | 0.000 | 0.000 |
| move | overlap-forward-d63-n2048 | rtl+memory | MATCH | tsc | 96.447/96.447/96.592 | 52.984/52.984/53.126 | 0.549 | 0.000 | 0.000 |
| move | overlap-forward-d63-n256 | rtl+memory | MATCH | tsc | 21.881/21.881/21.913 | 21.400/21.400/21.996 | 0.978 | 0.000 | 0.000 |
| move | overlap-forward-d63-n4096 | rtl+memory | MATCH | tsc | 172.256/172.256/172.707 | 105.158/105.158/105.441 | 0.610 | 0.000 | 0.000 |
| move | overlap-forward-d63-n512 | rtl+memory | MATCH | tsc | 30.484/30.484/30.727 | 30.744/30.744/37.800 | 1.007 | 0.000 | 0.000 |
| move | overlap-forward-d63-n64 | rtl+memory | MATCH | tsc | 17.588/17.588/17.758 | 17.640/17.640/17.685 | 1.003 | 0.000 | 0.000 |
| move | overlap-forward-d63-n65 | rtl+memory | MATCH | tsc | 18.379/18.379/18.453 | 18.545/18.545/18.545 | 1.009 | 0.000 | 0.000 |
| move | overlap-forward-d63-n65536 | rtl+memory | MATCH | tsc | 2868.487/2868.487/2893.973 | 2670.482/2670.482/2672.467 | 0.931 | 0.000 | 0.000 |
| move | same-a0-n0 | rtl+memory | MATCH | tsc | 5.586/5.586/5.600 | 7.144/7.144/7.163 | 1.279 | 0.000 | 0.000 |
| move | same-a0-n1 | rtl+memory | MATCH | tsc | 5.641/5.641/5.681 | 7.193/7.193/7.223 | 1.275 | 0.000 | 0.000 |
| move | same-a0-n1048576 | rtl+memory | MATCH | tsc | 7.182/7.182/7.201 | 6.334/6.334/6.334 | 0.882 | 0.000 | 0.000 |
| move | same-a0-n127 | rtl+memory | MATCH | tsc | 7.201/7.201/7.201 | 6.351/6.351/6.367 | 0.882 | 0.000 | 0.000 |
| move | same-a0-n128 | rtl+memory | MATCH | tsc | 7.201/7.201/7.201 | 6.318/6.318/6.334 | 0.877 | 0.000 | 0.000 |
| move | same-a0-n129 | rtl+memory | MATCH | tsc | 7.348/7.348/7.495 | 6.334/6.334/6.334 | 0.862 | 0.000 | 0.000 |
| move | same-a0-n16 | rtl+memory | MATCH | tsc | 5.660/5.660/5.660 | 4.826/4.826/4.826 | 0.853 | 0.000 | 0.000 |
| move | same-a0-n192 | rtl+memory | MATCH | tsc | 7.182/7.182/7.201 | 6.360/6.360/6.386 | 0.886 | 0.000 | 0.000 |
| move | same-a0-n256 | rtl+memory | MATCH | tsc | 7.201/7.201/7.201 | 6.334/6.334/6.334 | 0.880 | 0.000 | 0.000 |
| move | same-a0-n32 | rtl+memory | MATCH | tsc | 7.239/7.239/7.239 | 7.163/7.163/7.163 | 0.990 | 0.000 | 0.000 |
| move | same-a0-n33 | rtl+memory | MATCH | tsc | 7.220/7.220/7.239 | 6.367/6.367/6.367 | 0.882 | 0.000 | 0.000 |
| move | same-a0-n4096 | rtl+memory | MATCH | tsc | 7.201/7.201/7.201 | 6.350/6.350/6.367 | 0.882 | 0.000 | 0.000 |
| move | same-a0-n64 | rtl+memory | MATCH | tsc | 7.220/7.220/7.239 | 6.367/6.367/6.367 | 0.882 | 0.000 | 0.000 |
| move | same-a0-n65 | rtl+memory | MATCH | tsc | 7.201/7.201/7.201 | 5.571/5.571/5.571 | 0.774 | 0.000 | 0.000 |
| move | same-a0-n80 | rtl+memory | MATCH | tsc | 7.220/7.220/7.239 | 5.571/5.571/5.571 | 0.772 | 0.000 | 0.000 |
| move | same-a0-n96 | rtl+memory | MATCH | tsc | 7.220/7.220/7.239 | 5.568/5.568/5.594 | 0.771 | 0.000 | 0.000 |
| move | same-a0-n97 | rtl+memory | MATCH | tsc | 7.220/7.220/7.239 | 6.334/6.334/6.334 | 0.877 | 0.000 | 0.000 |
| move | stream-a0-a0-n1024 | rtl+memory | MATCH | tsc | 276.646/276.646/285.731 | 279.857/279.857/303.529 | 1.010 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048575 | rtl+memory | MATCH | tsc | 179828.469/179828.469/182758.328 | 289031.711/289031.711/317220.438 | 1.605 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 187110.664/187110.664/199703.953 | 285077.039/285077.039/296625.328 | 1.526 | 0.000 | 0.000 |
| move | stream-a0-a0-n131072 | rtl+memory | MATCH | tsc | 35651.886/35651.886/35860.236 | 37437.422/37437.422/37503.514 | 1.050 | 0.000 | 0.000 |
| move | stream-a0-a0-n1536 | rtl+memory | MATCH | tsc | 399.998/399.998/407.600 | 422.269/422.269/451.399 | 1.055 | 0.000 | 0.000 |
| move | stream-a0-a0-n16384 | rtl+memory | MATCH | tsc | 4700.243/4700.243/4748.771 | 4569.143/4569.143/4965.109 | 0.973 | 0.000 | 0.000 |
| move | stream-a0-a0-n16777216 | rtl+memory | MATCH | tsc | 2885532.375/2885532.375/2966313.250 | 2957307.250/2957307.250/2984149.500 | 1.026 | 0.000 | 0.000 |
| move | stream-a0-a0-n2048 | rtl+memory | MATCH | tsc | 537.840/537.840/549.252 | 576.683/576.683/627.303 | 1.071 | 0.000 | 0.000 |
| move | stream-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 357974.844/357974.844/358427.875 | 580031.109/580031.109/594021.938 | 1.620 | 0.000 | 0.000 |
| move | stream-a0-a0-n256 | rtl+memory | MATCH | tsc | 78.537/78.537/84.197 | 75.386/75.386/77.611 | 0.963 | 0.000 | 0.000 |
| move | stream-a0-a0-n262144 | rtl+memory | MATCH | tsc | 68593.006/68593.006/70304.973 | 76899.605/76899.605/85984.426 | 1.118 | 0.000 | 0.000 |
| move | stream-a0-a0-n32768 | rtl+memory | MATCH | tsc | 8847.696/8847.696/8898.735 | 8848.253/8848.253/9297.735 | 1.000 | 0.000 | 0.000 |
| move | stream-a0-a0-n33554432 | rtl+memory | MATCH | tsc | 6131105.250/6131105.250/6148552.000 | 5844119.750/5844119.750/6024976.000 | 0.953 | 0.000 | 0.000 |
| move | stream-a0-a0-n4096 | rtl+memory | MATCH | tsc | 1132.839/1132.839/1223.977 | 1145.144/1145.144/1263.653 | 1.009 | 0.000 | 0.000 |
| move | stream-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 770952.312/770952.312/796401.625 | 1160651.812/1160651.812/1219734.688 | 1.505 | 0.000 | 0.000 |
| move | stream-a0-a0-n512 | rtl+memory | MATCH | tsc | 141.005/141.005/144.302 | 140.732/140.732/151.254 | 0.997 | 0.000 | 0.000 |
| move | stream-a0-a0-n524288 | rtl+memory | MATCH | tsc | 90298.465/90298.465/90739.547 | 148645.980/148645.980/163190.258 | 1.647 | 0.000 | 0.000 |
| move | stream-a0-a0-n65536 | rtl+memory | MATCH | tsc | 17625.988/17625.988/17689.390 | 18331.206/18331.206/19994.383 | 1.040 | 0.000 | 0.000 |
| move | stream-a0-a0-n67108864 | rtl+memory | MATCH | tsc | 11510665.500/11510665.500/11647627.000 | 11361563.000/11361563.000/11444289.000 | 0.987 | 0.000 | 0.000 |
| move | stream-a0-a0-n786432 | rtl+memory | MATCH | tsc | 141463.271/141463.271/146014.329 | 206774.988/206774.988/214034.553 | 1.462 | 0.000 | 0.000 |
| move | stream-a0-a0-n8192 | rtl+memory | MATCH | tsc | 2334.366/2334.366/2483.243 | 2397.277/2397.277/2444.003 | 1.032 | 0.000 | 0.000 |
| move | stream-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 1474375.062/1474375.062/1516872.125 | 2354279.312/2354279.312/2361880.500 | 1.598 | 0.000 | 0.000 |
