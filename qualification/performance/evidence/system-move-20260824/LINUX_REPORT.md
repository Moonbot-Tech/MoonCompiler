# MoonCompiler Pulse result

Mode: `medium`. Baseline: `moon-default`. Candidate: `moon`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| move | 297 | 0.932 | 101 | 137 | 59 | 0.000 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| memory | 297 | 0.932 | 101 | 137 | 59 |
| rtl | 297 | 0.932 | 101 | 137 | 59 |

## Extreme results

### 15 fastest

- `move/hot-a0-a0-n640`: `0.429x`
- `move/same-a0-n33`: `0.429x`
- `move/hot-a0-a2048-n33`: `0.430x`
- `move/same-a0-n128`: `0.432x`
- `move/hot-a0-a1-n31`: `0.432x`
- `move/hot-a0-a128-n65`: `0.438x`
- `move/same-a0-n1048576`: `0.442x`
- `move/hot-a15-a31-n65`: `0.445x`
- `move/hot-a0-a128-n256`: `0.449x`
- `move/hot-a15-a31-n1024`: `0.455x`
- `move/hot-a0-a128-n32`: `0.456x`
- `move/hot-a15-a31-n512`: `0.457x`
- `move/hot-a2048-a0-n64`: `0.463x`
- `move/hot-a0-a128-n64`: `0.466x`
- `move/same-a0-n129`: `0.470x`

### 15 slowest

- `move/same-a0-n80`: `2.503x`
- `move/hot-a0-a2048-n32`: `2.227x`
- `move/hot-a0-a2048-n1536`: `2.061x`
- `move/hot-a0-a1-n1024`: `2.047x`
- `move/hot-a1-a1-n256`: `1.982x`
- `move/hot-a0-a1-n256`: `1.908x`
- `move/hot-a2048-a0-n4096`: `1.867x`
- `move/hot-a128-a0-n16`: `1.829x`
- `move/hot-a31-a15-n256`: `1.824x`
- `move/hot-a1-a0-n1536`: `1.793x`
- `move/overlap-backward-d63-n65`: `1.725x`
- `move/hot-a15-a31-n256`: `1.644x`
- `move/hot-a31-a15-n128`: `1.641x`
- `move/hot-a0-a2048-n16`: `1.174x`
- `move/overlap-backward-d1-n65`: `1.162x`
## Diagnostic Move process drift

These cases remain in the table, but the central ratio is calculated from adjacent mirrored processes; drift does not replace a semantic failure.

- `paired/move/hot-a0-a0-n0 ratio drift 2.725x`
- `paired/move/hot-a0-a0-n1 ratio drift 2.493x`
- `paired/move/hot-a0-a0-n1023 ratio drift 2.421x`
- `paired/move/hot-a0-a0-n1024 ratio drift 1.478x`
- `paired/move/hot-a0-a0-n1025 ratio drift 2.405x`
- `paired/move/hot-a0-a0-n1048576 ratio drift 2.139x`
- `paired/move/hot-a0-a0-n1280 ratio drift 2.217x`
- `paired/move/hot-a0-a0-n129 ratio drift 2.639x`
- `paired/move/hot-a0-a0-n131072 ratio drift 1.424x`
- `paired/move/hot-a0-a0-n15 ratio drift 2.072x`
- `paired/move/hot-a0-a0-n1535 ratio drift 2.378x`
- `paired/move/hot-a0-a0-n1536 ratio drift 2.452x`
- `paired/move/hot-a0-a0-n1537 ratio drift 2.321x`
- `paired/move/hot-a0-a0-n16 ratio drift 1.262x`
- `paired/move/hot-a0-a0-n160 ratio drift 2.245x`
- `paired/move/hot-a0-a0-n16384 ratio drift 1.262x`
- `paired/move/hot-a0-a0-n17 ratio drift 2.262x`
- `paired/move/hot-a0-a0-n2 ratio drift 1.719x`
- `paired/move/hot-a0-a0-n2048 ratio drift 1.339x`
- `paired/move/hot-a0-a0-n2097152 ratio drift 1.363x`
- `paired/move/hot-a0-a0-n24 ratio drift 2.317x`
- `paired/move/hot-a0-a0-n255 ratio drift 1.405x`
- `paired/move/hot-a0-a0-n256 ratio drift 1.982x`
- `paired/move/hot-a0-a0-n262144 ratio drift 1.337x`
- `paired/move/hot-a0-a0-n3 ratio drift 2.307x`
- `paired/move/hot-a0-a0-n3072 ratio drift 2.053x`
- `paired/move/hot-a0-a0-n31 ratio drift 2.429x`
- `paired/move/hot-a0-a0-n32 ratio drift 2.629x`
- `paired/move/hot-a0-a0-n32768 ratio drift 1.342x`
- `paired/move/hot-a0-a0-n33 ratio drift 1.499x`
- `paired/move/hot-a0-a0-n4 ratio drift 2.543x`
- `paired/move/hot-a0-a0-n4096 ratio drift 1.929x`
- `paired/move/hot-a0-a0-n4194304 ratio drift 1.270x`
- `paired/move/hot-a0-a0-n48 ratio drift 2.439x`
- `paired/move/hot-a0-a0-n5 ratio drift 2.716x`
- `paired/move/hot-a0-a0-n511 ratio drift 2.469x`
- `paired/move/hot-a0-a0-n524288 ratio drift 1.950x`
- `paired/move/hot-a0-a0-n63 ratio drift 2.551x`
- `paired/move/hot-a0-a0-n64 ratio drift 2.537x`
- `paired/move/hot-a0-a0-n640 ratio drift 2.505x`
- `paired/move/hot-a0-a0-n65 ratio drift 2.607x`
- `paired/move/hot-a0-a0-n65536 ratio drift 1.581x`
- `paired/move/hot-a0-a0-n7 ratio drift 2.750x`
- `paired/move/hot-a0-a0-n768 ratio drift 2.452x`
- `paired/move/hot-a0-a0-n8 ratio drift 2.634x`
- `paired/move/hot-a0-a0-n8192 ratio drift 2.295x`
- `paired/move/hot-a0-a0-n8388608 ratio drift 1.271x`
- `paired/move/hot-a0-a0-n896 ratio drift 2.386x`
- `paired/move/hot-a0-a0-n96 ratio drift 2.133x`
- `paired/move/hot-a0-a1-n1024 ratio drift 4.777x`
- `paired/move/hot-a0-a1-n127 ratio drift 1.809x`
- `paired/move/hot-a0-a1-n128 ratio drift 1.662x`
- `paired/move/hot-a0-a1-n129 ratio drift 2.385x`
- `paired/move/hot-a0-a1-n1536 ratio drift 2.048x`
- `paired/move/hot-a0-a1-n16 ratio drift 2.232x`
- `paired/move/hot-a0-a1-n256 ratio drift 3.957x`
- `paired/move/hot-a0-a1-n31 ratio drift 2.356x`
- `paired/move/hot-a0-a1-n33 ratio drift 1.259x`
- `paired/move/hot-a0-a1-n512 ratio drift 2.248x`
- `paired/move/hot-a0-a1-n63 ratio drift 2.442x`
- `paired/move/hot-a0-a1-n64 ratio drift 1.829x`
- `paired/move/hot-a0-a1-n65 ratio drift 1.688x`
- `paired/move/hot-a0-a128-n1024 ratio drift 2.042x`
- `paired/move/hot-a0-a128-n127 ratio drift 1.719x`
- `paired/move/hot-a0-a128-n128 ratio drift 1.267x`
- `paired/move/hot-a0-a128-n129 ratio drift 2.184x`
- `paired/move/hot-a0-a128-n1536 ratio drift 1.656x`
- `paired/move/hot-a0-a128-n16 ratio drift 2.152x`
- `paired/move/hot-a0-a128-n256 ratio drift 2.181x`
- `paired/move/hot-a0-a128-n31 ratio drift 2.155x`
- `paired/move/hot-a0-a128-n32 ratio drift 2.178x`
- `paired/move/hot-a0-a128-n33 ratio drift 2.644x`
- `paired/move/hot-a0-a128-n4096 ratio drift 2.120x`
- `paired/move/hot-a0-a128-n512 ratio drift 2.392x`
- `paired/move/hot-a0-a128-n63 ratio drift 2.391x`
- `paired/move/hot-a0-a128-n64 ratio drift 2.021x`
- `paired/move/hot-a0-a128-n65 ratio drift 2.528x`
- `paired/move/hot-a0-a2048-n1024 ratio drift 2.739x`
- `paired/move/hot-a0-a2048-n127 ratio drift 1.968x`
- `paired/move/hot-a0-a2048-n128 ratio drift 1.795x`
- `paired/move/hot-a0-a2048-n129 ratio drift 2.896x`
- `paired/move/hot-a0-a2048-n1536 ratio drift 4.660x`
- `paired/move/hot-a0-a2048-n16 ratio drift 2.197x`
- `paired/move/hot-a0-a2048-n256 ratio drift 2.084x`
- `paired/move/hot-a0-a2048-n31 ratio drift 2.374x`
- `paired/move/hot-a0-a2048-n32 ratio drift 4.512x`
- `paired/move/hot-a0-a2048-n33 ratio drift 2.519x`
- `paired/move/hot-a0-a2048-n4096 ratio drift 2.266x`
- `paired/move/hot-a0-a2048-n63 ratio drift 2.274x`
- `paired/move/hot-a0-a2048-n64 ratio drift 2.346x`
- `paired/move/hot-a0-a2048-n65 ratio drift 1.540x`
- `paired/move/hot-a1-a0-n1024 ratio drift 2.403x`
- `paired/move/hot-a1-a0-n128 ratio drift 1.796x`
- `paired/move/hot-a1-a0-n129 ratio drift 2.490x`
- `paired/move/hot-a1-a0-n1536 ratio drift 2.221x`
- `paired/move/hot-a1-a0-n16 ratio drift 1.980x`
- `paired/move/hot-a1-a0-n31 ratio drift 1.486x`
- `paired/move/hot-a1-a0-n33 ratio drift 1.877x`
- `paired/move/hot-a1-a0-n4096 ratio drift 1.671x`
- `paired/move/hot-a1-a0-n512 ratio drift 2.504x`
- `paired/move/hot-a1-a0-n63 ratio drift 2.240x`
- `paired/move/hot-a1-a0-n64 ratio drift 2.457x`
- `paired/move/hot-a1-a0-n65 ratio drift 1.330x`
- `paired/move/hot-a1-a1-n127 ratio drift 1.752x`
- `paired/move/hot-a1-a1-n128 ratio drift 1.849x`
- `paired/move/hot-a1-a1-n129 ratio drift 2.097x`
- `paired/move/hot-a1-a1-n1536 ratio drift 2.521x`
- `paired/move/hot-a1-a1-n256 ratio drift 4.039x`
- `paired/move/hot-a1-a1-n31 ratio drift 2.055x`
- `paired/move/hot-a1-a1-n32 ratio drift 2.831x`
- `paired/move/hot-a1-a1-n33 ratio drift 1.915x`
- `paired/move/hot-a1-a1-n4096 ratio drift 1.791x`
- `paired/move/hot-a1-a1-n512 ratio drift 2.350x`
- `paired/move/hot-a1-a1-n63 ratio drift 2.236x`
- `paired/move/hot-a1-a1-n64 ratio drift 1.322x`
- `paired/move/hot-a1-a1-n65 ratio drift 2.256x`
- `paired/move/hot-a128-a0-n1024 ratio drift 1.327x`
- `paired/move/hot-a128-a0-n127 ratio drift 1.981x`
- `paired/move/hot-a128-a0-n128 ratio drift 2.022x`
- `paired/move/hot-a128-a0-n129 ratio drift 2.366x`
- `paired/move/hot-a128-a0-n1536 ratio drift 2.326x`
- `paired/move/hot-a128-a0-n16 ratio drift 3.922x`
- `paired/move/hot-a128-a0-n31 ratio drift 2.438x`
- `paired/move/hot-a128-a0-n32 ratio drift 2.689x`
- `paired/move/hot-a128-a0-n33 ratio drift 2.060x`
- `paired/move/hot-a128-a0-n4096 ratio drift 2.149x`
- `paired/move/hot-a128-a0-n512 ratio drift 2.700x`
- `paired/move/hot-a128-a0-n63 ratio drift 2.657x`
- `paired/move/hot-a128-a0-n64 ratio drift 2.550x`
- `paired/move/hot-a128-a0-n65 ratio drift 2.294x`
- `paired/move/hot-a15-a31-n1024 ratio drift 2.312x`
- `paired/move/hot-a15-a31-n127 ratio drift 1.740x`
- `paired/move/hot-a15-a31-n128 ratio drift 1.840x`
- `paired/move/hot-a15-a31-n129 ratio drift 2.150x`
- `paired/move/hot-a15-a31-n1536 ratio drift 1.902x`
- `paired/move/hot-a15-a31-n16 ratio drift 2.040x`
- `paired/move/hot-a15-a31-n256 ratio drift 2.857x`
- `paired/move/hot-a15-a31-n31 ratio drift 2.708x`
- `paired/move/hot-a15-a31-n32 ratio drift 1.260x`
- `paired/move/hot-a15-a31-n4096 ratio drift 1.782x`
- `paired/move/hot-a15-a31-n512 ratio drift 2.359x`
- `paired/move/hot-a15-a31-n63 ratio drift 2.149x`
- `paired/move/hot-a15-a31-n64 ratio drift 2.146x`
- `paired/move/hot-a15-a31-n65 ratio drift 2.308x`
- `paired/move/hot-a2048-a0-n1024 ratio drift 2.202x`
- `paired/move/hot-a2048-a0-n127 ratio drift 1.949x`
- `paired/move/hot-a2048-a0-n128 ratio drift 2.107x`
- `paired/move/hot-a2048-a0-n129 ratio drift 2.596x`
- `paired/move/hot-a2048-a0-n1536 ratio drift 2.432x`
- `paired/move/hot-a2048-a0-n16 ratio drift 1.917x`
- `paired/move/hot-a2048-a0-n256 ratio drift 2.286x`
- `paired/move/hot-a2048-a0-n32 ratio drift 2.462x`
- `paired/move/hot-a2048-a0-n33 ratio drift 2.531x`
- `paired/move/hot-a2048-a0-n4096 ratio drift 2.259x`
- `paired/move/hot-a2048-a0-n512 ratio drift 1.362x`
- `paired/move/hot-a2048-a0-n63 ratio drift 2.516x`
- `paired/move/hot-a2048-a0-n64 ratio drift 2.691x`
- `paired/move/hot-a2048-a0-n65 ratio drift 2.189x`
- `paired/move/hot-a31-a15-n1024 ratio drift 2.615x`
- `paired/move/hot-a31-a15-n127 ratio drift 1.893x`
- `paired/move/hot-a31-a15-n128 ratio drift 1.887x`
- `paired/move/hot-a31-a15-n129 ratio drift 1.256x`
- `paired/move/hot-a31-a15-n1536 ratio drift 2.368x`
- `paired/move/hot-a31-a15-n16 ratio drift 2.140x`
- `paired/move/hot-a31-a15-n256 ratio drift 1.901x`
- `paired/move/hot-a31-a15-n31 ratio drift 1.266x`
- `paired/move/hot-a31-a15-n4096 ratio drift 1.792x`
- `paired/move/hot-a31-a15-n512 ratio drift 1.308x`
- `paired/move/hot-a31-a15-n64 ratio drift 2.399x`
- `paired/move/hot-a31-a15-n65 ratio drift 1.706x`
- `paired/move/overlap-backward-d1-n1024 ratio drift 2.388x`
- `paired/move/overlap-backward-d1-n1536 ratio drift 2.161x`
- `paired/move/overlap-backward-d1-n2048 ratio drift 2.330x`
- `paired/move/overlap-backward-d1-n256 ratio drift 3.067x`
- `paired/move/overlap-backward-d1-n33 ratio drift 1.582x`
- `paired/move/overlap-backward-d1-n4096 ratio drift 1.918x`
- `paired/move/overlap-backward-d1-n512 ratio drift 2.053x`
- `paired/move/overlap-backward-d1-n64 ratio drift 1.410x`
- `paired/move/overlap-backward-d1-n65 ratio drift 1.523x`
- `paired/move/overlap-backward-d1-n65536 ratio drift 1.742x`
- `paired/move/overlap-backward-d16-n1024 ratio drift 2.316x`
- `paired/move/overlap-backward-d16-n1536 ratio drift 2.351x`
- `paired/move/overlap-backward-d16-n2048 ratio drift 2.698x`
- `paired/move/overlap-backward-d16-n33 ratio drift 1.473x`
- `paired/move/overlap-backward-d16-n4096 ratio drift 2.478x`
- `paired/move/overlap-backward-d16-n512 ratio drift 2.416x`
- `paired/move/overlap-backward-d16-n65536 ratio drift 1.340x`
- `paired/move/overlap-backward-d63-n1024 ratio drift 2.308x`
- `paired/move/overlap-backward-d63-n128 ratio drift 1.429x`
- `paired/move/overlap-backward-d63-n1536 ratio drift 2.363x`
- `paired/move/overlap-backward-d63-n2048 ratio drift 2.548x`
- `paired/move/overlap-backward-d63-n256 ratio drift 2.140x`
- `paired/move/overlap-backward-d63-n4096 ratio drift 2.173x`
- `paired/move/overlap-backward-d63-n512 ratio drift 1.271x`
- `paired/move/overlap-backward-d63-n64 ratio drift 1.403x`
- `paired/move/overlap-backward-d63-n65 ratio drift 2.968x`
- `paired/move/overlap-backward-d63-n65536 ratio drift 1.629x`
- `paired/move/overlap-forward-d1-n1024 ratio drift 2.090x`
- `paired/move/overlap-forward-d1-n128 ratio drift 1.560x`
- `paired/move/overlap-forward-d1-n1536 ratio drift 2.104x`
- `paired/move/overlap-forward-d1-n2048 ratio drift 2.231x`
- `paired/move/overlap-forward-d1-n256 ratio drift 1.885x`
- `paired/move/overlap-forward-d1-n33 ratio drift 1.517x`
- `paired/move/overlap-forward-d1-n4096 ratio drift 1.853x`
- `paired/move/overlap-forward-d1-n64 ratio drift 1.482x`
- `paired/move/overlap-forward-d16-n1024 ratio drift 2.198x`
- `paired/move/overlap-forward-d16-n128 ratio drift 1.394x`
- `paired/move/overlap-forward-d16-n1536 ratio drift 2.900x`
- `paired/move/overlap-forward-d16-n2048 ratio drift 2.073x`
- `paired/move/overlap-forward-d16-n256 ratio drift 2.088x`
- `paired/move/overlap-forward-d16-n33 ratio drift 1.570x`
- `paired/move/overlap-forward-d16-n512 ratio drift 2.009x`
- `paired/move/overlap-forward-d16-n64 ratio drift 2.241x`
- `paired/move/overlap-forward-d63-n1024 ratio drift 2.125x`
- `paired/move/overlap-forward-d63-n128 ratio drift 1.613x`
- `paired/move/overlap-forward-d63-n1536 ratio drift 2.122x`
- `paired/move/overlap-forward-d63-n2048 ratio drift 2.317x`
- `paired/move/overlap-forward-d63-n4096 ratio drift 1.620x`
- `paired/move/overlap-forward-d63-n512 ratio drift 2.610x`
- `paired/move/overlap-forward-d63-n64 ratio drift 1.315x`
- `paired/move/overlap-forward-d63-n65536 ratio drift 1.322x`
- `paired/move/same-a0-n0 ratio drift 2.744x`
- `paired/move/same-a0-n1 ratio drift 2.901x`
- `paired/move/same-a0-n127 ratio drift 2.432x`
- `paired/move/same-a0-n128 ratio drift 1.313x`
- `paired/move/same-a0-n129 ratio drift 2.217x`
- `paired/move/same-a0-n16 ratio drift 2.312x`
- `paired/move/same-a0-n192 ratio drift 2.618x`
- `paired/move/same-a0-n256 ratio drift 2.402x`
- `paired/move/same-a0-n32 ratio drift 2.248x`
- `paired/move/same-a0-n33 ratio drift 2.760x`
- `paired/move/same-a0-n4096 ratio drift 2.407x`
- `paired/move/same-a0-n64 ratio drift 2.363x`
- `paired/move/same-a0-n65 ratio drift 2.458x`
- `paired/move/same-a0-n80 ratio drift 2.715x`
- `paired/move/same-a0-n96 ratio drift 2.403x`
- `paired/move/same-a0-n97 ratio drift 2.552x`
- `paired/move/stream-a0-a0-n2048 ratio drift 1.276x`
- `paired/move/stream-a0-a0-n8192 ratio drift 1.253x`

## All cases

| Program | Case | Layer | Oracle | Metric | moon-default stable/mean/max | moon stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| move | hot-a0-a0-n0 | rtl+memory | MATCH | tsc | 8.483/8.940/9.626 | 8.483/8.872/9.452 | 1.096 | 0.000 | 0.000 |
| move | hot-a0-a0-n1 | rtl+memory | MATCH | tsc | 8.706/9.007/9.933 | 8.882/9.285/10.476 | 1.037 | 0.000 | 0.000 |
| move | hot-a0-a0-n1023 | rtl+memory | MATCH | tsc | 34.830/35.510/42.451 | 35.692/35.397/38.025 | 0.886 | 0.000 | 0.000 |
| move | hot-a0-a0-n1024 | rtl+memory | MATCH | tsc | 37.949/36.707/39.341 | 37.149/36.610/38.199 | 1.034 | 0.000 | 0.000 |
| move | hot-a0-a0-n1025 | rtl+memory | MATCH | tsc | 35.784/37.843/40.062 | 40.321/40.120/42.575 | 1.091 | 0.000 | 0.000 |
| move | hot-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 204250.625/193045.888/228443.071 | 191113.694/198779.243/236830.000 | 1.093 | 0.000 | 0.000 |
| move | hot-a0-a0-n127 | rtl+memory | MATCH | tsc | 11.422/12.310/13.762 | 11.629/12.211/13.269 | 1.004 | 0.000 | 0.000 |
| move | hot-a0-a0-n128 | rtl+memory | MATCH | tsc | 11.956/12.174/13.080 | 11.608/12.159/12.889 | 1.015 | 0.000 | 0.000 |
| move | hot-a0-a0-n1280 | rtl+memory | MATCH | tsc | 40.419/42.830/46.497 | 45.213/43.582/47.204 | 0.979 | 0.000 | 0.000 |
| move | hot-a0-a0-n129 | rtl+memory | MATCH | tsc | 14.217/13.674/14.813 | 12.388/12.774/14.152 | 0.949 | 0.000 | 0.000 |
| move | hot-a0-a0-n131072 | rtl+memory | MATCH | tsc | 7596.616/7645.668/8645.006 | 7851.348/7656.755/7885.956 | 0.916 | 0.000 | 0.000 |
| move | hot-a0-a0-n15 | rtl+memory | MATCH | tsc | 8.941/9.286/10.375 | 9.502/9.193/9.731 | 1.078 | 0.000 | 0.000 |
| move | hot-a0-a0-n1535 | rtl+memory | MATCH | tsc | 51.899/49.860/52.037 | 46.954/45.347/48.422 | 0.883 | 0.000 | 0.000 |
| move | hot-a0-a0-n1536 | rtl+memory | MATCH | tsc | 50.030/48.551/53.569 | 46.884/47.884/53.669 | 0.944 | 0.000 | 0.000 |
| move | hot-a0-a0-n1537 | rtl+memory | MATCH | tsc | 54.381/50.592/54.992 | 45.494/49.005/54.831 | 0.489 | 0.000 | 0.000 |
| move | hot-a0-a0-n16 | rtl+memory | MATCH | tsc | 8.745/8.788/10.025 | 9.065/9.238/10.025 | 1.049 | 0.000 | 0.000 |
| move | hot-a0-a0-n160 | rtl+memory | MATCH | tsc | 12.747/12.916/13.439 | 12.662/13.006/14.156 | 0.945 | 0.000 | 0.000 |
| move | hot-a0-a0-n16384 | rtl+memory | MATCH | tsc | 654.175/663.746/720.194 | 597.633/643.532/722.022 | 1.037 | 0.000 | 0.000 |
| move | hot-a0-a0-n17 | rtl+memory | MATCH | tsc | 7.915/8.293/8.850 | 9.113/8.607/9.113 | 0.992 | 0.000 | 0.000 |
| move | hot-a0-a0-n192 | rtl+memory | MATCH | tsc | 13.819/13.767/15.037 | 14.532/14.597/15.980 | 0.971 | 0.000 | 0.000 |
| move | hot-a0-a0-n2 | rtl+memory | MATCH | tsc | 8.511/9.135/9.963 | 8.482/8.577/8.802 | 0.890 | 0.000 | 0.000 |
| move | hot-a0-a0-n2048 | rtl+memory | MATCH | tsc | 58.184/56.226/65.208 | 53.996/55.264/61.441 | 1.023 | 0.000 | 0.000 |
| move | hot-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 466485.500/473387.768/570374.000 | 539070.917/483557.190/566239.000 | 0.882 | 0.000 | 0.000 |
| move | hot-a0-a0-n24 | rtl+memory | MATCH | tsc | 8.593/8.332/8.983 | 8.845/8.527/8.930 | 1.029 | 0.000 | 0.000 |
| move | hot-a0-a0-n255 | rtl+memory | MATCH | tsc | 16.638/17.967/19.955 | 19.596/18.322/19.598 | 1.096 | 0.000 | 0.000 |
| move | hot-a0-a0-n256 | rtl+memory | MATCH | tsc | 18.033/17.671/18.655 | 17.091/17.453/19.027 | 0.942 | 0.000 | 0.000 |
| move | hot-a0-a0-n257 | rtl+memory | MATCH | tsc | 19.787/20.070/21.040 | 20.935/21.370/23.380 | 0.979 | 0.000 | 0.000 |
| move | hot-a0-a0-n262144 | rtl+memory | MATCH | tsc | 14352.703/15793.691/17779.951 | 16745.099/16747.473/20656.314 | 0.940 | 0.000 | 0.000 |
| move | hot-a0-a0-n3 | rtl+memory | MATCH | tsc | 8.762/9.146/9.762 | 9.005/9.173/9.779 | 1.002 | 0.000 | 0.000 |
| move | hot-a0-a0-n3072 | rtl+memory | MATCH | tsc | 79.921/81.844/91.904 | 78.947/81.403/91.850 | 1.007 | 0.000 | 0.000 |
| move | hot-a0-a0-n31 | rtl+memory | MATCH | tsc | 8.646/8.250/8.701 | 8.372/8.152/8.592 | 0.972 | 0.000 | 0.000 |
| move | hot-a0-a0-n32 | rtl+memory | MATCH | tsc | 8.067/8.693/9.895 | 8.614/8.246/8.636 | 0.958 | 0.000 | 0.000 |
| move | hot-a0-a0-n320 | rtl+memory | MATCH | tsc | 22.335/21.763/22.345 | 21.063/21.331/22.477 | 0.968 | 0.000 | 0.000 |
| move | hot-a0-a0-n32768 | rtl+memory | MATCH | tsc | 1946.558/2073.692/2533.381 | 1828.599/1912.250/2158.178 | 0.963 | 0.000 | 0.000 |
| move | hot-a0-a0-n33 | rtl+memory | MATCH | tsc | 10.586/10.869/11.873 | 10.633/11.098/12.558 | 0.986 | 0.000 | 0.000 |
| move | hot-a0-a0-n384 | rtl+memory | MATCH | tsc | 24.324/22.906/24.777 | 22.758/22.761/23.694 | 0.947 | 0.000 | 0.000 |
| move | hot-a0-a0-n4 | rtl+memory | MATCH | tsc | 7.941/8.265/9.110 | 7.833/7.990/9.040 | 0.832 | 0.000 | 0.000 |
| move | hot-a0-a0-n4096 | rtl+memory | MATCH | tsc | 111.363/105.947/111.746 | 99.981/104.746/115.999 | 0.906 | 0.000 | 0.000 |
| move | hot-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 917666.500/951568.929/1012891.000 | 917127.500/930085.643/1021346.000 | 0.956 | 0.000 | 0.000 |
| move | hot-a0-a0-n48 | rtl+memory | MATCH | tsc | 9.189/9.172/9.453 | 9.452/9.504/9.730 | 1.029 | 0.000 | 0.000 |
| move | hot-a0-a0-n5 | rtl+memory | MATCH | tsc | 8.497/8.268/8.889 | 7.742/8.327/9.163 | 1.045 | 0.000 | 0.000 |
| move | hot-a0-a0-n511 | rtl+memory | MATCH | tsc | 25.498/25.113/26.469 | 23.777/24.961/26.651 | 1.071 | 0.000 | 0.000 |
| move | hot-a0-a0-n512 | rtl+memory | MATCH | tsc | 23.134/24.426/27.265 | 23.789/24.121/25.779 | 0.939 | 0.000 | 0.000 |
| move | hot-a0-a0-n513 | rtl+memory | MATCH | tsc | 28.476/29.114/30.337 | 26.229/26.669/28.408 | 0.925 | 0.000 | 0.000 |
| move | hot-a0-a0-n524288 | rtl+memory | MATCH | tsc | 64573.860/62016.707/73672.458 | 54975.866/53406.100/63663.639 | 0.982 | 0.000 | 0.000 |
| move | hot-a0-a0-n63 | rtl+memory | MATCH | tsc | 10.166/9.564/10.256 | 8.721/9.354/10.070 | 0.957 | 0.000 | 0.000 |
| move | hot-a0-a0-n64 | rtl+memory | MATCH | tsc | 8.940/9.101/10.025 | 8.501/9.036/9.794 | 0.962 | 0.000 | 0.000 |
| move | hot-a0-a0-n640 | rtl+memory | MATCH | tsc | 29.063/29.061/31.914 | 26.021/32.796/47.125 | 0.429 | 0.000 | 0.000 |
| move | hot-a0-a0-n65 | rtl+memory | MATCH | tsc | 12.344/12.083/12.750 | 11.596/11.611/12.957 | 0.950 | 0.000 | 0.000 |
| move | hot-a0-a0-n65536 | rtl+memory | MATCH | tsc | 5165.642/4375.849/5170.234 | 3561.748/3792.726/4172.083 | 1.093 | 0.000 | 0.000 |
| move | hot-a0-a0-n7 | rtl+memory | MATCH | tsc | 18.527/14.203/19.662 | 8.041/8.436/9.114 | 1.013 | 0.000 | 0.000 |
| move | hot-a0-a0-n768 | rtl+memory | MATCH | tsc | 30.503/30.158/31.851 | 32.727/31.247/33.096 | 0.919 | 0.000 | 0.000 |
| move | hot-a0-a0-n8 | rtl+memory | MATCH | tsc | 8.023/8.510/9.241 | 9.215/8.667/9.231 | 1.143 | 0.000 | 0.000 |
| move | hot-a0-a0-n80 | rtl+memory | MATCH | tsc | 10.026/9.916/10.748 | 9.254/9.741/10.751 | 0.923 | 0.000 | 0.000 |
| move | hot-a0-a0-n8192 | rtl+memory | MATCH | tsc | 213.908/217.760/236.014 | 198.492/208.329/227.555 | 0.960 | 0.000 | 0.000 |
| move | hot-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 2072827.250/2025646.857/2126495.000 | 1937323.250/2000806.000/2237801.500 | 1.028 | 0.000 | 0.000 |
| move | hot-a0-a0-n896 | rtl+memory | MATCH | tsc | 30.940/31.950/34.790 | 33.401/32.779/36.247 | 1.122 | 0.000 | 0.000 |
| move | hot-a0-a0-n9 | rtl+memory | MATCH | tsc | 8.705/8.789/9.450 | 8.723/8.900/9.671 | 0.936 | 0.000 | 0.000 |
| move | hot-a0-a0-n96 | rtl+memory | MATCH | tsc | 11.115/11.859/13.295 | 11.384/11.437/12.030 | 1.094 | 0.000 | 0.000 |
| move | hot-a0-a1-n1024 | rtl+memory | MATCH | tsc | 39.250/39.597/41.835 | 85.499/63.476/85.544 | 2.047 | 0.000 | 0.000 |
| move | hot-a0-a1-n127 | rtl+memory | MATCH | tsc | 12.387/12.932/13.670 | 22.058/17.544/22.090 | 1.015 | 0.000 | 0.000 |
| move | hot-a0-a1-n128 | rtl+memory | MATCH | tsc | 12.630/12.883/13.369 | 13.269/13.401/13.884 | 1.039 | 0.000 | 0.000 |
| move | hot-a0-a1-n129 | rtl+memory | MATCH | tsc | 14.285/13.703/14.304 | 13.784/13.987/14.227 | 1.023 | 0.000 | 0.000 |
| move | hot-a0-a1-n1536 | rtl+memory | MATCH | tsc | 54.160/57.378/61.931 | 57.114/58.285/62.697 | 1.061 | 0.000 | 0.000 |
| move | hot-a0-a1-n16 | rtl+memory | MATCH | tsc | 8.997/9.368/9.759 | 8.732/8.849/9.451 | 1.028 | 0.000 | 0.000 |
| move | hot-a0-a1-n256 | rtl+memory | MATCH | tsc | 18.876/19.006/20.206 | 37.629/31.329/38.863 | 1.908 | 0.000 | 0.000 |
| move | hot-a0-a1-n31 | rtl+memory | MATCH | tsc | 8.594/8.266/8.845 | 7.713/8.060/8.627 | 0.432 | 0.000 | 0.000 |
| move | hot-a0-a1-n32 | rtl+memory | MATCH | tsc | 8.595/8.712/9.223 | 7.915/8.449/9.113 | 0.993 | 0.000 | 0.000 |
| move | hot-a0-a1-n33 | rtl+memory | MATCH | tsc | 20.471/16.957/22.227 | 10.914/11.182/12.022 | 0.577 | 0.000 | 0.000 |
| move | hot-a0-a1-n4096 | rtl+memory | MATCH | tsc | 218.258/197.717/238.056 | 170.113/171.178/210.507 | 0.723 | 0.000 | 0.000 |
| move | hot-a0-a1-n512 | rtl+memory | MATCH | tsc | 64.464/51.561/64.568 | 26.905/28.506/31.017 | 1.004 | 0.000 | 0.000 |
| move | hot-a0-a1-n63 | rtl+memory | MATCH | tsc | 9.937/9.376/10.050 | 8.918/8.678/9.784 | 0.818 | 0.000 | 0.000 |
| move | hot-a0-a1-n64 | rtl+memory | MATCH | tsc | 10.094/10.308/11.330 | 9.856/9.937/10.125 | 0.905 | 0.000 | 0.000 |
| move | hot-a0-a1-n65 | rtl+memory | MATCH | tsc | 13.238/13.782/15.226 | 14.436/15.183/17.881 | 0.986 | 0.000 | 0.000 |
| move | hot-a0-a128-n1024 | rtl+memory | MATCH | tsc | 38.623/40.724/44.780 | 42.158/40.362/43.466 | 0.968 | 0.000 | 0.000 |
| move | hot-a0-a128-n127 | rtl+memory | MATCH | tsc | 11.874/12.751/14.343 | 21.862/17.922/22.772 | 0.580 | 0.000 | 0.000 |
| move | hot-a0-a128-n128 | rtl+memory | MATCH | tsc | 12.708/12.333/13.129 | 12.585/13.172/14.356 | 1.084 | 0.000 | 0.000 |
| move | hot-a0-a128-n129 | rtl+memory | MATCH | tsc | 14.234/13.653/14.791 | 13.434/13.320/13.744 | 0.938 | 0.000 | 0.000 |
| move | hot-a0-a128-n1536 | rtl+memory | MATCH | tsc | 95.927/80.558/105.266 | 62.550/58.511/63.820 | 0.974 | 0.000 | 0.000 |
| move | hot-a0-a128-n16 | rtl+memory | MATCH | tsc | 8.936/8.970/9.240 | 9.806/9.545/9.857 | 1.043 | 0.000 | 0.000 |
| move | hot-a0-a128-n256 | rtl+memory | MATCH | tsc | 18.884/18.793/20.389 | 19.056/18.172/19.594 | 0.449 | 0.000 | 0.000 |
| move | hot-a0-a128-n31 | rtl+memory | MATCH | tsc | 8.846/8.723/9.170 | 8.750/8.543/9.311 | 0.906 | 0.000 | 0.000 |
| move | hot-a0-a128-n32 | rtl+memory | MATCH | tsc | 19.787/14.982/19.795 | 9.177/9.159/9.399 | 0.456 | 0.000 | 0.000 |
| move | hot-a0-a128-n33 | rtl+memory | MATCH | tsc | 9.513/9.367/9.737 | 9.799/9.506/10.026 | 1.030 | 0.000 | 0.000 |
| move | hot-a0-a128-n4096 | rtl+memory | MATCH | tsc | 144.270/152.136/162.886 | 152.608/159.162/168.656 | 1.123 | 0.000 | 0.000 |
| move | hot-a0-a128-n512 | rtl+memory | MATCH | tsc | 27.363/26.873/28.672 | 29.133/26.571/29.153 | 1.009 | 0.000 | 0.000 |
| move | hot-a0-a128-n63 | rtl+memory | MATCH | tsc | 8.978/9.138/10.024 | 9.101/10.012/11.894 | 0.933 | 0.000 | 0.000 |
| move | hot-a0-a128-n64 | rtl+memory | MATCH | tsc | 10.025/9.577/10.025 | 21.587/16.212/21.596 | 0.466 | 0.000 | 0.000 |
| move | hot-a0-a128-n65 | rtl+memory | MATCH | tsc | 10.339/10.658/11.016 | 10.502/10.274/11.045 | 0.438 | 0.000 | 0.000 |
| move | hot-a0-a2048-n1024 | rtl+memory | MATCH | tsc | 34.298/34.649/38.259 | 37.820/36.800/39.485 | 0.981 | 0.000 | 0.000 |
| move | hot-a0-a2048-n127 | rtl+memory | MATCH | tsc | 22.434/17.617/22.764 | 13.047/13.258/13.669 | 1.031 | 0.000 | 0.000 |
| move | hot-a0-a2048-n128 | rtl+memory | MATCH | tsc | 12.193/12.467/13.669 | 13.269/12.809/13.366 | 1.088 | 0.000 | 0.000 |
| move | hot-a0-a2048-n129 | rtl+memory | MATCH | tsc | 13.559/20.800/30.379 | 30.340/22.562/30.348 | 1.010 | 0.000 | 0.000 |
| move | hot-a0-a2048-n1536 | rtl+memory | MATCH | tsc | 51.186/51.027/53.632 | 100.028/75.383/100.135 | 2.061 | 0.000 | 0.000 |
| move | hot-a0-a2048-n16 | rtl+memory | MATCH | tsc | 10.102/9.471/10.129 | 10.004/10.046/10.430 | 1.174 | 0.000 | 0.000 |
| move | hot-a0-a2048-n256 | rtl+memory | MATCH | tsc | 37.929/28.495/38.354 | 18.286/17.962/19.016 | 0.504 | 0.000 | 0.000 |
| move | hot-a0-a2048-n31 | rtl+memory | MATCH | tsc | 8.598/8.575/9.115 | 8.281/10.163/15.435 | 1.003 | 0.000 | 0.000 |
| move | hot-a0-a2048-n32 | rtl+memory | MATCH | tsc | 8.845/8.709/9.115 | 7.931/10.094/15.319 | 2.227 | 0.000 | 0.000 |
| move | hot-a0-a2048-n33 | rtl+memory | MATCH | tsc | 9.252/9.120/9.453 | 9.211/9.218/9.454 | 0.430 | 0.000 | 0.000 |
| move | hot-a0-a2048-n4096 | rtl+memory | MATCH | tsc | 114.429/110.883/121.289 | 107.826/110.248/117.653 | 1.049 | 0.000 | 0.000 |
| move | hot-a0-a2048-n512 | rtl+memory | MATCH | tsc | 25.065/25.046/26.077 | 24.360/24.885/25.870 | 0.982 | 0.000 | 0.000 |
| move | hot-a0-a2048-n63 | rtl+memory | MATCH | tsc | 8.888/9.490/10.452 | 9.899/9.492/10.472 | 0.940 | 0.000 | 0.000 |
| move | hot-a0-a2048-n64 | rtl+memory | MATCH | tsc | 9.976/9.832/10.505 | 9.395/9.214/9.853 | 1.022 | 0.000 | 0.000 |
| move | hot-a0-a2048-n65 | rtl+memory | MATCH | tsc | 10.078/10.160/10.936 | 10.371/10.043/10.663 | 1.033 | 0.000 | 0.000 |
| move | hot-a1-a0-n1024 | rtl+memory | MATCH | tsc | 33.089/33.692/34.849 | 36.900/35.457/37.094 | 1.056 | 0.000 | 0.000 |
| move | hot-a1-a0-n127 | rtl+memory | MATCH | tsc | 22.014/19.165/22.038 | 11.745/12.636/13.835 | 0.537 | 0.000 | 0.000 |
| move | hot-a1-a0-n128 | rtl+memory | MATCH | tsc | 21.873/17.734/22.029 | 22.016/19.049/22.023 | 0.988 | 0.000 | 0.000 |
| move | hot-a1-a0-n129 | rtl+memory | MATCH | tsc | 13.398/13.615/14.657 | 14.204/14.033/14.683 | 1.103 | 0.000 | 0.000 |
| move | hot-a1-a0-n1536 | rtl+memory | MATCH | tsc | 52.183/50.992/52.826 | 97.607/83.306/97.699 | 1.793 | 0.000 | 0.000 |
| move | hot-a1-a0-n16 | rtl+memory | MATCH | tsc | 8.728/11.106/15.240 | 9.191/9.013/9.192 | 0.504 | 0.000 | 0.000 |
| move | hot-a1-a0-n256 | rtl+memory | MATCH | tsc | 37.651/31.966/37.781 | 19.850/19.344/19.860 | 0.524 | 0.000 | 0.000 |
| move | hot-a1-a0-n31 | rtl+memory | MATCH | tsc | 8.648/8.822/10.735 | 7.991/8.050/9.228 | 0.884 | 0.000 | 0.000 |
| move | hot-a1-a0-n32 | rtl+memory | MATCH | tsc | 8.632/8.374/8.847 | 8.385/8.359/8.849 | 1.009 | 0.000 | 0.000 |
| move | hot-a1-a0-n33 | rtl+memory | MATCH | tsc | 10.584/11.237/12.150 | 11.761/11.727/12.892 | 1.085 | 0.000 | 0.000 |
| move | hot-a1-a0-n4096 | rtl+memory | MATCH | tsc | 136.482/169.255/219.214 | 195.853/181.382/233.470 | 0.648 | 0.000 | 0.000 |
| move | hot-a1-a0-n512 | rtl+memory | MATCH | tsc | 25.119/26.645/30.248 | 26.536/25.938/27.345 | 0.968 | 0.000 | 0.000 |
| move | hot-a1-a0-n63 | rtl+memory | MATCH | tsc | 9.108/9.602/10.273 | 20.594/15.171/20.890 | 0.939 | 0.000 | 0.000 |
| move | hot-a1-a0-n64 | rtl+memory | MATCH | tsc | 10.125/10.099/11.318 | 10.112/10.438/10.813 | 1.020 | 0.000 | 0.000 |
| move | hot-a1-a0-n65 | rtl+memory | MATCH | tsc | 13.953/14.002/14.388 | 13.529/13.708/14.825 | 0.942 | 0.000 | 0.000 |
| move | hot-a1-a1-n1024 | rtl+memory | MATCH | tsc | 42.303/41.085/42.488 | 36.272/45.169/67.604 | 0.862 | 0.000 | 0.000 |
| move | hot-a1-a1-n127 | rtl+memory | MATCH | tsc | 12.530/12.647/13.627 | 11.753/12.441/13.370 | 0.900 | 0.000 | 0.000 |
| move | hot-a1-a1-n128 | rtl+memory | MATCH | tsc | 21.963/17.968/21.973 | 13.674/13.109/13.678 | 1.002 | 0.000 | 0.000 |
| move | hot-a1-a1-n129 | rtl+memory | MATCH | tsc | 12.746/13.785/15.038 | 13.751/13.942/15.625 | 0.942 | 0.000 | 0.000 |
| move | hot-a1-a1-n1536 | rtl+memory | MATCH | tsc | 47.318/50.188/53.300 | 50.424/52.700/57.329 | 1.052 | 0.000 | 0.000 |
| move | hot-a1-a1-n16 | rtl+memory | MATCH | tsc | 8.963/9.042/9.560 | 8.314/8.837/9.729 | 0.934 | 0.000 | 0.000 |
| move | hot-a1-a1-n256 | rtl+memory | MATCH | tsc | 18.616/18.711/20.209 | 37.527/29.316/37.713 | 1.982 | 0.000 | 0.000 |
| move | hot-a1-a1-n31 | rtl+memory | MATCH | tsc | 7.711/8.252/9.138 | 8.512/8.300/8.845 | 1.009 | 0.000 | 0.000 |
| move | hot-a1-a1-n32 | rtl+memory | MATCH | tsc | 7.729/8.258/9.276 | 7.914/8.007/8.845 | 1.002 | 0.000 | 0.000 |
| move | hot-a1-a1-n33 | rtl+memory | MATCH | tsc | 10.521/10.943/11.401 | 20.882/16.052/20.937 | 1.073 | 0.000 | 0.000 |
| move | hot-a1-a1-n4096 | rtl+memory | MATCH | tsc | 134.648/138.990/147.752 | 152.427/140.725/152.479 | 0.976 | 0.000 | 0.000 |
| move | hot-a1-a1-n512 | rtl+memory | MATCH | tsc | 30.091/28.721/30.099 | 28.428/29.055/32.271 | 0.935 | 0.000 | 0.000 |
| move | hot-a1-a1-n63 | rtl+memory | MATCH | tsc | 20.613/15.978/21.600 | 9.326/13.960/19.863 | 0.963 | 0.000 | 0.000 |
| move | hot-a1-a1-n64 | rtl+memory | MATCH | tsc | 9.968/14.530/20.220 | 10.674/10.822/11.367 | 0.547 | 0.000 | 0.000 |
| move | hot-a1-a1-n65 | rtl+memory | MATCH | tsc | 13.152/13.258/13.991 | 12.318/13.399/15.492 | 0.947 | 0.000 | 0.000 |
| move | hot-a128-a0-n1024 | rtl+memory | MATCH | tsc | 34.670/35.609/41.356 | 37.838/35.901/37.980 | 1.093 | 0.000 | 0.000 |
| move | hot-a128-a0-n127 | rtl+memory | MATCH | tsc | 22.128/18.881/22.302 | 12.242/12.761/13.672 | 0.579 | 0.000 | 0.000 |
| move | hot-a128-a0-n128 | rtl+memory | MATCH | tsc | 12.423/12.194/12.892 | 12.044/12.630/13.670 | 0.992 | 0.000 | 0.000 |
| move | hot-a128-a0-n129 | rtl+memory | MATCH | tsc | 13.432/13.347/14.153 | 14.630/13.781/14.679 | 1.120 | 0.000 | 0.000 |
| move | hot-a128-a0-n1536 | rtl+memory | MATCH | tsc | 46.578/48.317/52.125 | 51.288/50.098/51.756 | 1.031 | 0.000 | 0.000 |
| move | hot-a128-a0-n16 | rtl+memory | MATCH | tsc | 10.122/10.152/12.305 | 18.655/15.465/18.663 | 1.829 | 0.000 | 0.000 |
| move | hot-a128-a0-n256 | rtl+memory | MATCH | tsc | 17.964/17.926/19.016 | 17.510/18.504/19.890 | 1.068 | 0.000 | 0.000 |
| move | hot-a128-a0-n31 | rtl+memory | MATCH | tsc | 8.047/8.690/9.615 | 8.354/8.464/9.120 | 0.918 | 0.000 | 0.000 |
| move | hot-a128-a0-n32 | rtl+memory | MATCH | tsc | 8.393/8.532/9.113 | 8.271/8.405/9.113 | 0.939 | 0.000 | 0.000 |
| move | hot-a128-a0-n33 | rtl+memory | MATCH | tsc | 9.963/12.837/17.872 | 9.497/9.717/10.412 | 0.977 | 0.000 | 0.000 |
| move | hot-a128-a0-n4096 | rtl+memory | MATCH | tsc | 109.478/115.554/125.640 | 111.232/108.579/117.844 | 0.883 | 0.000 | 0.000 |
| move | hot-a128-a0-n512 | rtl+memory | MATCH | tsc | 25.295/25.282/27.512 | 26.889/26.065/27.038 | 1.077 | 0.000 | 0.000 |
| move | hot-a128-a0-n63 | rtl+memory | MATCH | tsc | 8.823/9.558/10.647 | 9.556/9.375/10.098 | 0.950 | 0.000 | 0.000 |
| move | hot-a128-a0-n64 | rtl+memory | MATCH | tsc | 9.029/9.267/10.075 | 8.736/9.414/10.441 | 1.103 | 0.000 | 0.000 |
| move | hot-a128-a0-n65 | rtl+memory | MATCH | tsc | 10.357/10.788/11.432 | 9.917/10.000/11.413 | 0.875 | 0.000 | 0.000 |
| move | hot-a15-a31-n1024 | rtl+memory | MATCH | tsc | 39.269/41.554/44.051 | 39.612/40.047/43.626 | 0.455 | 0.000 | 0.000 |
| move | hot-a15-a31-n127 | rtl+memory | MATCH | tsc | 21.749/17.840/22.795 | 11.913/12.138/12.531 | 0.555 | 0.000 | 0.000 |
| move | hot-a15-a31-n128 | rtl+memory | MATCH | tsc | 22.024/19.370/22.642 | 12.895/12.779/13.349 | 1.000 | 0.000 | 0.000 |
| move | hot-a15-a31-n129 | rtl+memory | MATCH | tsc | 15.676/16.317/17.556 | 15.502/15.743/16.623 | 0.500 | 0.000 | 0.000 |
| move | hot-a15-a31-n1536 | rtl+memory | MATCH | tsc | 63.275/81.278/107.569 | 56.480/57.916/63.100 | 0.943 | 0.000 | 0.000 |
| move | hot-a15-a31-n16 | rtl+memory | MATCH | tsc | 9.189/9.018/10.026 | 8.496/9.224/10.376 | 1.017 | 0.000 | 0.000 |
| move | hot-a15-a31-n256 | rtl+memory | MATCH | tsc | 22.199/21.861/22.315 | 37.621/33.697/37.629 | 1.644 | 0.000 | 0.000 |
| move | hot-a15-a31-n31 | rtl+memory | MATCH | tsc | 7.914/8.068/8.592 | 7.723/8.077/8.846 | 1.000 | 0.000 | 0.000 |
| move | hot-a15-a31-n32 | rtl+memory | MATCH | tsc | 7.727/8.384/9.115 | 7.711/7.922/8.354 | 1.011 | 0.000 | 0.000 |
| move | hot-a15-a31-n33 | rtl+memory | MATCH | tsc | 8.958/8.525/8.962 | 8.131/8.381/9.936 | 1.007 | 0.000 | 0.000 |
| move | hot-a15-a31-n4096 | rtl+memory | MATCH | tsc | 237.604/193.053/237.674 | 150.059/157.530/170.230 | 1.118 | 0.000 | 0.000 |
| move | hot-a15-a31-n512 | rtl+memory | MATCH | tsc | 64.338/46.692/64.537 | 28.717/27.846/30.079 | 0.457 | 0.000 | 0.000 |
| move | hot-a15-a31-n63 | rtl+memory | MATCH | tsc | 11.266/11.136/11.692 | 11.335/11.212/11.655 | 1.064 | 0.000 | 0.000 |
| move | hot-a15-a31-n64 | rtl+memory | MATCH | tsc | 9.783/10.449/12.205 | 10.025/9.929/10.027 | 0.482 | 0.000 | 0.000 |
| move | hot-a15-a31-n65 | rtl+memory | MATCH | tsc | 23.344/18.459/23.383 | 10.708/10.505/10.985 | 0.445 | 0.000 | 0.000 |
| move | hot-a2048-a0-n1024 | rtl+memory | MATCH | tsc | 35.778/36.254/37.828 | 39.172/37.775/39.422 | 1.076 | 0.000 | 0.000 |
| move | hot-a2048-a0-n127 | rtl+memory | MATCH | tsc | 13.223/13.266/14.185 | 12.995/12.904/13.796 | 1.035 | 0.000 | 0.000 |
| move | hot-a2048-a0-n128 | rtl+memory | MATCH | tsc | 22.068/17.768/22.071 | 12.031/12.831/13.930 | 1.130 | 0.000 | 0.000 |
| move | hot-a2048-a0-n129 | rtl+memory | MATCH | tsc | 14.154/13.787/14.155 | 13.465/13.851/14.581 | 0.975 | 0.000 | 0.000 |
| move | hot-a2048-a0-n1536 | rtl+memory | MATCH | tsc | 91.989/72.602/97.667 | 101.243/78.723/103.650 | 1.064 | 0.000 | 0.000 |
| move | hot-a2048-a0-n16 | rtl+memory | MATCH | tsc | 9.739/9.242/9.771 | 10.025/9.502/10.027 | 1.030 | 0.000 | 0.000 |
| move | hot-a2048-a0-n256 | rtl+memory | MATCH | tsc | 17.572/18.041/19.595 | 19.073/18.720/20.000 | 1.088 | 0.000 | 0.000 |
| move | hot-a2048-a0-n31 | rtl+memory | MATCH | tsc | 7.931/8.245/8.848 | 19.700/14.763/19.765 | 1.010 | 0.000 | 0.000 |
| move | hot-a2048-a0-n32 | rtl+memory | MATCH | tsc | 9.110/8.948/9.400 | 19.154/14.882/20.405 | 0.986 | 0.000 | 0.000 |
| move | hot-a2048-a0-n33 | rtl+memory | MATCH | tsc | 9.225/10.607/14.990 | 8.482/9.189/10.338 | 0.867 | 0.000 | 0.000 |
| move | hot-a2048-a0-n4096 | rtl+memory | MATCH | tsc | 103.800/105.504/111.489 | 218.053/209.528/218.452 | 1.867 | 0.000 | 0.000 |
| move | hot-a2048-a0-n512 | rtl+memory | MATCH | tsc | 27.456/25.811/27.569 | 27.543/25.844/27.745 | 1.000 | 0.000 | 0.000 |
| move | hot-a2048-a0-n63 | rtl+memory | MATCH | tsc | 9.956/11.323/16.189 | 9.221/9.211/10.024 | 1.006 | 0.000 | 0.000 |
| move | hot-a2048-a0-n64 | rtl+memory | MATCH | tsc | 9.729/9.106/9.730 | 8.706/9.373/10.319 | 0.463 | 0.000 | 0.000 |
| move | hot-a2048-a0-n65 | rtl+memory | MATCH | tsc | 10.386/10.364/10.936 | 10.936/10.560/11.280 | 1.003 | 0.000 | 0.000 |
| move | hot-a31-a15-n1024 | rtl+memory | MATCH | tsc | 37.768/38.268/40.334 | 37.094/39.711/43.338 | 0.998 | 0.000 | 0.000 |
| move | hot-a31-a15-n127 | rtl+memory | MATCH | tsc | 13.547/13.042/14.369 | 11.607/12.374/13.394 | 0.987 | 0.000 | 0.000 |
| move | hot-a31-a15-n128 | rtl+memory | MATCH | tsc | 13.670/13.539/13.675 | 21.887/21.671/24.281 | 1.641 | 0.000 | 0.000 |
| move | hot-a31-a15-n129 | rtl+memory | MATCH | tsc | 14.873/14.582/16.032 | 14.741/19.084/26.886 | 1.099 | 0.000 | 0.000 |
| move | hot-a31-a15-n1536 | rtl+memory | MATCH | tsc | 54.410/53.460/55.961 | 52.871/50.728/52.901 | 0.955 | 0.000 | 0.000 |
| move | hot-a31-a15-n16 | rtl+memory | MATCH | tsc | 17.437/13.880/18.624 | 9.452/9.066/9.452 | 1.028 | 0.000 | 0.000 |
| move | hot-a31-a15-n256 | rtl+memory | MATCH | tsc | 20.353/19.828/22.059 | 38.020/30.937/38.275 | 1.824 | 0.000 | 0.000 |
| move | hot-a31-a15-n31 | rtl+memory | MATCH | tsc | 7.913/8.351/9.398 | 7.947/8.299/8.926 | 0.978 | 0.000 | 0.000 |
| move | hot-a31-a15-n32 | rtl+memory | MATCH | tsc | 7.938/8.094/8.592 | 7.787/8.169/8.811 | 0.994 | 0.000 | 0.000 |
| move | hot-a31-a15-n33 | rtl+memory | MATCH | tsc | 8.788/8.477/9.318 | 9.550/8.933/9.576 | 0.992 | 0.000 | 0.000 |
| move | hot-a31-a15-n4096 | rtl+memory | MATCH | tsc | 134.215/135.610/143.758 | 230.816/191.004/241.637 | 0.996 | 0.000 | 0.000 |
| move | hot-a31-a15-n512 | rtl+memory | MATCH | tsc | 27.293/27.933/30.072 | 29.496/27.931/29.788 | 1.019 | 0.000 | 0.000 |
| move | hot-a31-a15-n63 | rtl+memory | MATCH | tsc | 21.546/16.253/21.604 | 11.388/11.105/11.461 | 0.530 | 0.000 | 0.000 |
| move | hot-a31-a15-n64 | rtl+memory | MATCH | tsc | 9.873/9.275/9.876 | 9.714/9.331/9.754 | 0.922 | 0.000 | 0.000 |
| move | hot-a31-a15-n65 | rtl+memory | MATCH | tsc | 11.088/11.374/11.798 | 23.284/19.422/23.294 | 1.081 | 0.000 | 0.000 |
| move | overlap-backward-d1-n1024 | rtl+memory | MATCH | tsc | 46.462/46.461/50.732 | 52.153/49.081/52.192 | 1.008 | 0.000 | 0.000 |
| move | overlap-backward-d1-n128 | rtl+memory | MATCH | tsc | 19.774/17.743/21.129 | 19.824/17.414/19.830 | 1.004 | 0.000 | 0.000 |
| move | overlap-backward-d1-n1536 | rtl+memory | MATCH | tsc | 56.383/56.589/59.758 | 57.690/56.559/58.245 | 0.963 | 0.000 | 0.000 |
| move | overlap-backward-d1-n2048 | rtl+memory | MATCH | tsc | 75.934/72.189/76.121 | 73.224/70.178/73.292 | 0.470 | 0.000 | 0.000 |
| move | overlap-backward-d1-n256 | rtl+memory | MATCH | tsc | 20.549/21.448/22.907 | 48.264/39.240/48.369 | 0.968 | 0.000 | 0.000 |
| move | overlap-backward-d1-n33 | rtl+memory | MATCH | tsc | 20.009/17.689/20.558 | 19.909/17.422/19.994 | 1.016 | 0.000 | 0.000 |
| move | overlap-backward-d1-n4096 | rtl+memory | MATCH | tsc | 142.126/151.143/164.358 | 143.706/143.468/157.740 | 0.918 | 0.000 | 0.000 |
| move | overlap-backward-d1-n512 | rtl+memory | MATCH | tsc | 62.919/48.259/63.120 | 32.466/31.574/32.653 | 1.013 | 0.000 | 0.000 |
| move | overlap-backward-d1-n64 | rtl+memory | MATCH | tsc | 15.114/14.990/15.309 | 14.871/15.713/19.419 | 0.979 | 0.000 | 0.000 |
| move | overlap-backward-d1-n65 | rtl+memory | MATCH | tsc | 18.020/18.388/20.057 | 20.942/20.247/21.631 | 1.162 | 0.000 | 0.000 |
| move | overlap-backward-d1-n65536 | rtl+memory | MATCH | tsc | 2839.298/2905.799/2988.304 | 2963.072/3022.292/3242.647 | 1.024 | 0.000 | 0.000 |
| move | overlap-backward-d16-n1024 | rtl+memory | MATCH | tsc | 43.688/43.955/48.788 | 48.801/48.620/50.389 | 1.090 | 0.000 | 0.000 |
| move | overlap-backward-d16-n128 | rtl+memory | MATCH | tsc | 14.633/17.233/20.436 | 20.196/18.220/20.498 | 0.998 | 0.000 | 0.000 |
| move | overlap-backward-d16-n1536 | rtl+memory | MATCH | tsc | 56.786/55.137/57.498 | 56.444/53.326/56.555 | 0.877 | 0.000 | 0.000 |
| move | overlap-backward-d16-n2048 | rtl+memory | MATCH | tsc | 72.268/69.130/72.299 | 63.555/70.049/77.960 | 1.080 | 0.000 | 0.000 |
| move | overlap-backward-d16-n256 | rtl+memory | MATCH | tsc | 22.774/22.042/22.873 | 21.620/21.343/22.194 | 0.947 | 0.000 | 0.000 |
| move | overlap-backward-d16-n33 | rtl+memory | MATCH | tsc | 14.041/15.654/17.804 | 14.644/14.393/15.033 | 0.857 | 0.000 | 0.000 |
| move | overlap-backward-d16-n4096 | rtl+memory | MATCH | tsc | 148.549/144.969/152.475 | 288.170/223.650/296.874 | 0.915 | 0.000 | 0.000 |
| move | overlap-backward-d16-n512 | rtl+memory | MATCH | tsc | 27.604/28.138/30.522 | 31.377/29.662/31.411 | 0.980 | 0.000 | 0.000 |
| move | overlap-backward-d16-n64 | rtl+memory | MATCH | tsc | 19.936/14.764/19.961 | 9.783/9.574/10.175 | 0.485 | 0.000 | 0.000 |
| move | overlap-backward-d16-n65 | rtl+memory | MATCH | tsc | 12.195/12.510/13.666 | 12.892/12.752/13.672 | 0.931 | 0.000 | 0.000 |
| move | overlap-backward-d16-n65536 | rtl+memory | MATCH | tsc | 2965.193/3191.289/3977.944 | 4053.341/3539.356/4220.653 | 0.711 | 0.000 | 0.000 |
| move | overlap-backward-d63-n1024 | rtl+memory | MATCH | tsc | 42.026/43.178/48.272 | 44.334/42.261/44.527 | 0.910 | 0.000 | 0.000 |
| move | overlap-backward-d63-n128 | rtl+memory | MATCH | tsc | 20.324/17.881/20.443 | 14.617/14.342/15.504 | 0.952 | 0.000 | 0.000 |
| move | overlap-backward-d63-n1536 | rtl+memory | MATCH | tsc | 54.793/52.796/54.837 | 59.450/57.728/59.617 | 1.090 | 0.000 | 0.000 |
| move | overlap-backward-d63-n2048 | rtl+memory | MATCH | tsc | 64.378/65.830/70.556 | 74.106/71.113/74.113 | 1.143 | 0.000 | 0.000 |
| move | overlap-backward-d63-n256 | rtl+memory | MATCH | tsc | 22.888/21.799/22.912 | 22.083/21.664/23.205 | 0.958 | 0.000 | 0.000 |
| move | overlap-backward-d63-n4096 | rtl+memory | MATCH | tsc | 151.251/145.847/153.480 | 297.479/230.345/297.487 | 0.967 | 0.000 | 0.000 |
| move | overlap-backward-d63-n512 | rtl+memory | MATCH | tsc | 63.129/49.736/63.189 | 30.220/29.758/31.763 | 0.505 | 0.000 | 0.000 |
| move | overlap-backward-d63-n64 | rtl+memory | MATCH | tsc | 11.871/11.631/12.482 | 11.482/11.463/12.091 | 1.034 | 0.000 | 0.000 |
| move | overlap-backward-d63-n65 | rtl+memory | MATCH | tsc | 12.534/12.831/14.961 | 21.535/18.685/21.587 | 1.725 | 0.000 | 0.000 |
| move | overlap-backward-d63-n65536 | rtl+memory | MATCH | tsc | 2890.728/2877.258/2969.871 | 2880.198/3034.536/3215.811 | 1.014 | 0.000 | 0.000 |
| move | overlap-forward-d1-n1024 | rtl+memory | MATCH | tsc | 37.533/36.751/37.665 | 76.253/60.027/76.638 | 0.521 | 0.000 | 0.000 |
| move | overlap-forward-d1-n128 | rtl+memory | MATCH | tsc | 18.115/17.997/20.366 | 20.054/18.442/20.713 | 0.833 | 0.000 | 0.000 |
| move | overlap-forward-d1-n1536 | rtl+memory | MATCH | tsc | 50.451/49.918/53.742 | 98.903/76.966/105.543 | 0.976 | 0.000 | 0.000 |
| move | overlap-forward-d1-n2048 | rtl+memory | MATCH | tsc | 121.457/95.066/121.542 | 74.393/69.956/75.435 | 1.059 | 0.000 | 0.000 |
| move | overlap-forward-d1-n256 | rtl+memory | MATCH | tsc | 19.757/19.487/20.550 | 20.265/20.095/20.905 | 1.008 | 0.000 | 0.000 |
| move | overlap-forward-d1-n33 | rtl+memory | MATCH | tsc | 13.337/14.169/15.175 | 14.851/16.104/19.196 | 0.973 | 0.000 | 0.000 |
| move | overlap-forward-d1-n4096 | rtl+memory | MATCH | tsc | 120.736/137.231/165.740 | 137.751/132.056/142.186 | 0.640 | 0.000 | 0.000 |
| move | overlap-forward-d1-n512 | rtl+memory | MATCH | tsc | 25.054/25.230/26.538 | 25.849/25.063/25.922 | 1.036 | 0.000 | 0.000 |
| move | overlap-forward-d1-n64 | rtl+memory | MATCH | tsc | 14.438/17.136/19.978 | 14.386/16.144/19.273 | 0.777 | 0.000 | 0.000 |
| move | overlap-forward-d1-n65 | rtl+memory | MATCH | tsc | 18.438/19.090/21.592 | 16.467/19.078/21.623 | 0.941 | 0.000 | 0.000 |
| move | overlap-forward-d1-n65536 | rtl+memory | MATCH | tsc | 2962.740/2984.516/3138.735 | 2865.372/2992.364/3191.661 | 0.976 | 0.000 | 0.000 |
| move | overlap-forward-d16-n1024 | rtl+memory | MATCH | tsc | 36.343/37.298/42.646 | 41.012/39.659/41.016 | 1.132 | 0.000 | 0.000 |
| move | overlap-forward-d16-n128 | rtl+memory | MATCH | tsc | 17.571/18.860/20.442 | 17.193/17.750/19.912 | 0.988 | 0.000 | 0.000 |
| move | overlap-forward-d16-n1536 | rtl+memory | MATCH | tsc | 53.072/52.444/56.155 | 98.338/82.245/99.979 | 0.505 | 0.000 | 0.000 |
| move | overlap-forward-d16-n2048 | rtl+memory | MATCH | tsc | 63.454/67.282/71.846 | 67.780/68.239/72.660 | 1.109 | 0.000 | 0.000 |
| move | overlap-forward-d16-n256 | rtl+memory | MATCH | tsc | 18.273/20.182/23.736 | 21.157/20.375/21.360 | 1.077 | 0.000 | 0.000 |
| move | overlap-forward-d16-n33 | rtl+memory | MATCH | tsc | 19.306/17.416/20.034 | 16.781/17.038/19.919 | 1.043 | 0.000 | 0.000 |
| move | overlap-forward-d16-n4096 | rtl+memory | MATCH | tsc | 204.771/194.786/217.246 | 122.718/125.988/130.000 | 0.614 | 0.000 | 0.000 |
| move | overlap-forward-d16-n512 | rtl+memory | MATCH | tsc | 25.043/26.119/27.854 | 26.986/25.906/27.340 | 0.502 | 0.000 | 0.000 |
| move | overlap-forward-d16-n64 | rtl+memory | MATCH | tsc | 8.845/8.666/9.114 | 8.898/8.824/8.901 | 0.989 | 0.000 | 0.000 |
| move | overlap-forward-d16-n65 | rtl+memory | MATCH | tsc | 20.921/18.532/21.475 | 16.080/16.192/19.108 | 0.770 | 0.000 | 0.000 |
| move | overlap-forward-d16-n65536 | rtl+memory | MATCH | tsc | 3958.642/3710.735/4324.877 | 2981.538/2950.442/3228.404 | 0.706 | 0.000 | 0.000 |
| move | overlap-forward-d63-n1024 | rtl+memory | MATCH | tsc | 36.666/36.949/37.843 | 37.684/37.915/39.079 | 1.002 | 0.000 | 0.000 |
| move | overlap-forward-d63-n128 | rtl+memory | MATCH | tsc | 20.438/19.133/20.657 | 20.283/18.163/20.349 | 0.788 | 0.000 | 0.000 |
| move | overlap-forward-d63-n1536 | rtl+memory | MATCH | tsc | 52.199/51.251/53.586 | 52.254/52.710/57.417 | 1.091 | 0.000 | 0.000 |
| move | overlap-forward-d63-n2048 | rtl+memory | MATCH | tsc | 115.761/94.939/121.892 | 63.283/65.997/70.841 | 0.562 | 0.000 | 0.000 |
| move | overlap-forward-d63-n256 | rtl+memory | MATCH | tsc | 21.571/20.778/21.587 | 21.497/21.135/22.080 | 1.093 | 0.000 | 0.000 |
| move | overlap-forward-d63-n4096 | rtl+memory | MATCH | tsc | 216.612/177.051/222.929 | 137.758/132.443/138.248 | 1.005 | 0.000 | 0.000 |
| move | overlap-forward-d63-n512 | rtl+memory | MATCH | tsc | 25.854/25.920/27.697 | 24.802/24.661/25.776 | 0.930 | 0.000 | 0.000 |
| move | overlap-forward-d63-n64 | rtl+memory | MATCH | tsc | 20.065/18.146/20.084 | 19.624/17.919/20.156 | 0.975 | 0.000 | 0.000 |
| move | overlap-forward-d63-n65 | rtl+memory | MATCH | tsc | 19.405/18.714/21.423 | 21.348/20.304/22.118 | 0.998 | 0.000 | 0.000 |
| move | overlap-forward-d63-n65536 | rtl+memory | MATCH | tsc | 4086.470/3465.904/4093.345 | 4092.407/3655.637/4219.914 | 0.884 | 0.000 | 0.000 |
| move | same-a0-n0 | rtl+memory | MATCH | tsc | 22.929/18.288/22.966 | 23.029/16.931/23.035 | 0.974 | 0.000 | 0.000 |
| move | same-a0-n1 | rtl+memory | MATCH | tsc | 9.455/9.269/9.458 | 22.272/16.463/23.068 | 1.022 | 0.000 | 0.000 |
| move | same-a0-n1048576 | rtl+memory | MATCH | tsc | 16.880/13.065/17.510 | 8.266/7.755/8.330 | 0.442 | 0.000 | 0.000 |
| move | same-a0-n127 | rtl+memory | MATCH | tsc | 7.569/7.724/7.960 | 7.542/7.663/7.960 | 0.999 | 0.000 | 0.000 |
| move | same-a0-n128 | rtl+memory | MATCH | tsc | 17.466/12.560/17.513 | 7.600/7.769/8.332 | 0.432 | 0.000 | 0.000 |
| move | same-a0-n129 | rtl+memory | MATCH | tsc | 16.334/13.009/17.438 | 7.985/7.891/8.324 | 0.470 | 0.000 | 0.000 |
| move | same-a0-n16 | rtl+memory | MATCH | tsc | 8.592/8.441/8.593 | 19.371/14.734/19.406 | 0.970 | 0.000 | 0.000 |
| move | same-a0-n192 | rtl+memory | MATCH | tsc | 7.242/7.801/8.651 | 8.081/7.901/8.319 | 1.103 | 0.000 | 0.000 |
| move | same-a0-n256 | rtl+memory | MATCH | tsc | 17.511/13.294/17.525 | 17.444/13.115/17.504 | 1.002 | 0.000 | 0.000 |
| move | same-a0-n32 | rtl+memory | MATCH | tsc | 7.316/7.713/8.306 | 8.210/7.850/8.391 | 0.888 | 0.000 | 0.000 |
| move | same-a0-n33 | rtl+memory | MATCH | tsc | 7.914/8.274/9.114 | 8.964/8.782/9.184 | 0.429 | 0.000 | 0.000 |
| move | same-a0-n4096 | rtl+memory | MATCH | tsc | 8.312/7.908/8.354 | 7.810/7.967/8.181 | 1.072 | 0.000 | 0.000 |
| move | same-a0-n64 | rtl+memory | MATCH | tsc | 8.374/8.665/9.320 | 8.848/9.000/9.193 | 1.040 | 0.000 | 0.000 |
| move | same-a0-n65 | rtl+memory | MATCH | tsc | 8.563/8.711/9.400 | 8.633/8.442/9.116 | 0.932 | 0.000 | 0.000 |
| move | same-a0-n80 | rtl+memory | MATCH | tsc | 8.183/8.325/8.877 | 21.065/18.449/21.082 | 2.503 | 0.000 | 0.000 |
| move | same-a0-n96 | rtl+memory | MATCH | tsc | 8.751/8.480/9.113 | 9.115/8.665/9.221 | 0.970 | 0.000 | 0.000 |
| move | same-a0-n97 | rtl+memory | MATCH | tsc | 7.961/7.847/9.113 | 7.387/7.710/8.190 | 0.935 | 0.000 | 0.000 |
| move | stream-a0-a0-n1024 | rtl+memory | MATCH | tsc | 450.817/456.291/479.067 | 470.993/457.626/471.766 | 0.998 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048575 | rtl+memory | MATCH | tsc | 471805.898/470646.439/481633.594 | 459755.051/462318.471/481145.164 | 0.974 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 487344.555/480409.684/493543.820 | 452108.031/459699.462/481984.281 | 0.941 | 0.000 | 0.000 |
| move | stream-a0-a0-n131072 | rtl+memory | MATCH | tsc | 59772.875/59094.026/62502.019 | 59188.264/58436.828/59211.075 | 0.996 | 0.000 | 0.000 |
| move | stream-a0-a0-n1536 | rtl+memory | MATCH | tsc | 675.979/671.805/702.555 | 722.595/704.901/723.075 | 1.047 | 0.000 | 0.000 |
| move | stream-a0-a0-n16384 | rtl+memory | MATCH | tsc | 7774.533/7410.073/7775.858 | 7462.260/7561.171/7816.023 | 0.981 | 0.000 | 0.000 |
| move | stream-a0-a0-n16777216 | rtl+memory | MATCH | tsc | 4871945.938/5056560.107/5619278.875 | 4765019.000/5023749.125/5733579.000 | 0.978 | 0.000 | 0.000 |
| move | stream-a0-a0-n2048 | rtl+memory | MATCH | tsc | 948.098/926.614/963.407 | 967.929/923.360/986.101 | 0.934 | 0.000 | 0.000 |
| move | stream-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 953273.906/954308.971/996717.203 | 907187.898/918993.507/953983.984 | 1.001 | 0.000 | 0.000 |
| move | stream-a0-a0-n256 | rtl+memory | MATCH | tsc | 111.844/111.774/118.651 | 116.268/115.841/120.391 | 1.011 | 0.000 | 0.000 |
| move | stream-a0-a0-n262144 | rtl+memory | MATCH | tsc | 117497.911/118410.931/121587.840 | 119678.295/120563.012/123358.070 | 1.031 | 0.000 | 0.000 |
| move | stream-a0-a0-n32768 | rtl+memory | MATCH | tsc | 14782.011/15183.702/16123.121 | 14973.224/15117.132/15766.357 | 1.013 | 0.000 | 0.000 |
| move | stream-a0-a0-n33554432 | rtl+memory | MATCH | tsc | 9815758.875/10074422.071/10512858.250 | 10128926.500/10053994.679/10451712.750 | 0.989 | 0.000 | 0.000 |
| move | stream-a0-a0-n4096 | rtl+memory | MATCH | tsc | 1822.140/1858.084/1983.426 | 1870.196/1882.427/1992.532 | 0.999 | 0.000 | 0.000 |
| move | stream-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 1880340.516/1887070.393/1950253.312 | 1838389.062/1850591.290/1913058.719 | 0.985 | 0.000 | 0.000 |
| move | stream-a0-a0-n512 | rtl+memory | MATCH | tsc | 224.803/230.314/239.312 | 222.323/225.029/237.429 | 0.991 | 0.000 | 0.000 |
| move | stream-a0-a0-n524288 | rtl+memory | MATCH | tsc | 233798.658/236620.363/250267.812 | 229842.129/230658.176/241647.664 | 0.964 | 0.000 | 0.000 |
| move | stream-a0-a0-n65536 | rtl+memory | MATCH | tsc | 29616.139/29295.915/30350.913 | 29635.190/29128.120/30059.320 | 1.001 | 0.000 | 0.000 |
| move | stream-a0-a0-n67108864 | rtl+memory | MATCH | tsc | 23666229.250/22757422.857/23696914.500 | 22888530.500/22877271.214/23790270.000 | 1.006 | 0.000 | 0.000 |
| move | stream-a0-a0-n786432 | rtl+memory | MATCH | tsc | 349569.303/352893.890/366223.212 | 340362.706/354345.845/375859.976 | 0.998 | 0.000 | 0.000 |
| move | stream-a0-a0-n8192 | rtl+memory | MATCH | tsc | 3544.296/3579.602/3748.262 | 3761.805/3694.348/4043.973 | 0.999 | 0.000 | 0.000 |
| move | stream-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 3510935.094/3703561.991/3939072.812 | 3827530.906/3711003.991/3835349.750 | 0.982 | 0.000 | 0.000 |
