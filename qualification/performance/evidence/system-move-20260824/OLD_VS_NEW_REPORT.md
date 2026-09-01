# MoonCompiler Pulse result

Mode: `medium`. Baseline: `moon-old`. Candidate: `moon-final`.

Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;
TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.

## Summary by program

`< 0.95` — Moon is faster, `0.95..1.05` — parity, `> 1.05` — Moon is slower.

| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| move | 17 | 0.923 | 5 | 5 | 7 | 0.000 |

## Summary by physical layer

| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| memory | 17 | 0.923 | 5 | 5 | 7 |
| rtl | 17 | 0.923 | 5 | 5 | 7 |

## Extreme results

### 15 fastest

- `move/hot-a0-a0-n4194304`: `0.408x`
- `move/hot-a0-a0-n8388608`: `0.417x`
- `move/hot-a0-a0-n524288`: `0.422x`
- `move/hot-a0-a0-n2097152`: `0.425x`
- `move/hot-a0-a0-n1048576`: `0.425x`
- `move/stream-a0-a0-n262144`: `0.961x`
- `move/stream-a0-a0-n67108864`: `0.989x`
- `move/stream-a0-a0-n16777216`: `0.996x`
- `move/hot-a0-a0-n262144`: `1.002x`
- `move/stream-a0-a0-n33554432`: `1.021x`
- `move/stream-a0-a0-n786432`: `1.486x`
- `move/stream-a0-a0-n524288`: `1.497x`
- `move/stream-a0-a0-n1048576`: `1.522x`
- `move/stream-a0-a0-n4194304`: `1.553x`
- `move/stream-a0-a0-n2097152`: `1.555x`

### 15 slowest

- `move/stream-a0-a0-n8388608`: `1.594x`
- `move/stream-a0-a0-n1048575`: `1.571x`
- `move/stream-a0-a0-n2097152`: `1.555x`
- `move/stream-a0-a0-n4194304`: `1.553x`
- `move/stream-a0-a0-n1048576`: `1.522x`
- `move/stream-a0-a0-n524288`: `1.497x`
- `move/stream-a0-a0-n786432`: `1.486x`
- `move/stream-a0-a0-n33554432`: `1.021x`
- `move/hot-a0-a0-n262144`: `1.002x`
- `move/stream-a0-a0-n16777216`: `0.996x`
- `move/stream-a0-a0-n67108864`: `0.989x`
- `move/stream-a0-a0-n262144`: `0.961x`
- `move/hot-a0-a0-n1048576`: `0.425x`
- `move/hot-a0-a0-n2097152`: `0.425x`
- `move/hot-a0-a0-n524288`: `0.422x`
## Diagnostic Move process drift

These cases remain in the table, but the central ratio is calculated from adjacent mirrored processes; drift does not replace a semantic failure.

- `paired/move/stream-a0-a0-n8388608 ratio drift 1.329x`

## All cases

| Program | Case | Layer | Oracle | Metric | moon-old stable/mean/max | moon-final stable/mean/max | Candidate/baseline | Control/op | MM effect |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| move | hot-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 156530.821/158078.255/161999.429 | 66979.894/66856.188/67156.364 | 0.425 | 0.000 | 0.000 |
| move | hot-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 312699.286/314197.184/318171.286 | 133642.088/131213.571/133831.529 | 0.425 | 0.000 | 0.000 |
| move | hot-a0-a0-n262144 | rtl+memory | MATCH | tsc | 15571.671/15490.590/15681.075 | 15575.132/15921.797/16918.812 | 1.002 | 0.000 | 0.000 |
| move | hot-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 625347.000/629046.571/636886.333 | 256493.045/258465.870/269424.750 | 0.408 | 0.000 | 0.000 |
| move | hot-a0-a0-n524288 | rtl+memory | MATCH | tsc | 79951.321/80126.587/80519.964 | 33703.022/33901.445/34166.821 | 0.422 | 0.000 | 0.000 |
| move | hot-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 1256688.500/1264583.000/1277237.000 | 511140.375/524931.321/546245.250 | 0.417 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048575 | rtl+memory | MATCH | tsc | 214986.188/215095.268/222416.078 | 337914.852/340895.158/350505.172 | 1.571 | 0.000 | 0.000 |
| move | stream-a0-a0-n1048576 | rtl+memory | MATCH | tsc | 218231.328/218337.779/228967.516 | 331166.586/330665.779/341837.016 | 1.522 | 0.000 | 0.000 |
| move | stream-a0-a0-n16777216 | rtl+memory | MATCH | tsc | 3301893.625/3274066.429/3348284.500 | 3330179.875/3246473.000/3334371.750 | 0.996 | 0.000 | 0.000 |
| move | stream-a0-a0-n2097152 | rtl+memory | MATCH | tsc | 428828.812/432969.879/452928.531 | 651668.234/665505.366/688522.594 | 1.555 | 0.000 | 0.000 |
| move | stream-a0-a0-n262144 | rtl+memory | MATCH | tsc | 77875.582/76001.166/77903.488 | 74358.764/76077.304/84056.074 | 0.961 | 0.000 | 0.000 |
| move | stream-a0-a0-n33554432 | rtl+memory | MATCH | tsc | 6639060.750/6774174.500/7337952.000 | 6757939.000/6558049.500/6767258.500 | 1.021 | 0.000 | 0.000 |
| move | stream-a0-a0-n4194304 | rtl+memory | MATCH | tsc | 857143.438/854015.562/893336.062 | 1338012.062/1338246.170/1383726.062 | 1.553 | 0.000 | 0.000 |
| move | stream-a0-a0-n524288 | rtl+memory | MATCH | tsc | 103040.266/104726.049/112175.258 | 152299.027/161050.828/178133.906 | 1.497 | 0.000 | 0.000 |
| move | stream-a0-a0-n67108864 | rtl+memory | MATCH | tsc | 12891842.000/13415522.714/14278709.000 | 12657429.500/12673488.571/13132192.000 | 0.989 | 0.000 | 0.000 |
| move | stream-a0-a0-n786432 | rtl+memory | MATCH | tsc | 161693.018/162388.370/166978.929 | 240114.959/251631.466/283956.788 | 1.486 | 0.000 | 0.000 |
| move | stream-a0-a0-n8388608 | rtl+memory | MATCH | tsc | 1710984.438/1729405.729/1989732.250 | 2624644.562/2616521.214/2741158.500 | 1.594 | 0.000 | 0.000 |
