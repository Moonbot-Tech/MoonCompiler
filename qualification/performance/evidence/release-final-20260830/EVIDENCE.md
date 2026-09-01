# Pulse evidence: release-final-20260830

This is a versioned summary of the complete Win64 O3 medium run of exact `main`
after integrating the compiler/RTL/MM and optimizer block. Raw logs, binaries,
and the manifest remain in ignored `results/pulse/release-final-20260830`; Git
contains the complete aggregate report and machine-readable values for every case.

- source HEAD: `64067c9949c24f688c29c048ec3051ddce0b5847`;
- worktree at manifest capture: clean;
- system: Windows 11 x86-64, AMD Family 25 Model 33, 16 logical CPU;
- mode: `medium`;
- matrix: 757 cases, Delphi 12.2 / Moon+bundled MM / Moon+default FPC MM;
- executions: 7 separate processes per system/case, mirrored interleaved order;
  15,897 processes in total;
- complete snapshot duration: 43.1 minutes;
- semantic oracle: `757/757 MATCH`;
- result excluding 13 unstable cases: Moon/Delphi geomean `0.8310`, 360 faster,
  289 at parity, 95 slower;
- Heartbeat: `20/20 MATCH`, geomean `0.8185`, 18 faster, 2 at parity,
  no losses;
- allocator group: bundled MM / default FPC MM geomean `0.6069`, meaning the
  bundled MM is `1.65` times faster on average.

The overall geomean cannot be directly compared with the older 390-case
snapshot: the current matrix contains 297-case `System.Move`, Heartbeat,
kernels, and new RTL/Devil consumers. Across 369 shared stable cases, the old
snapshot was `0.7722` and the current one `0.7439`; the common portion of the
matrix became approximately 3.7 percent faster.

The first column of `PULSE_HISTORY.html` records the earlier baseline before
the RTL/compiler/MM optimization series began. Between it and the final snapshot
remain 243 shared stable case IDs: Moon/Delphi geomean changed from `0.9978` to
`0.7625`, while the geomean of “final / baseline” ratios was `0.7642`. This is
23.6 percent less normalized time, or approximately 30.9 percent more completed
work per unit of time. It is the product-level before/after for the whole
series; methodology changes for individual stages are recorded in HTML notes
and do not replace focused A/B of a particular fix.

Eight cases exceeded permissible 1.25x process drift in at least one system:

- `calibration/asm-memory-write-64m`;
- `codegen/concrete-reverse-rec`;
- `json/builder-growth-64k`;
- `loops/histogram-random`;
- `mm/alloc-free-1m`;
- `mm/fragmented-mixed`;
- `workloads/stream-add`;
- `workloads/stream-scale`.

Another five TSC cases did not form a stable cluster from half the adjacent
mirrored process pairs. The report retains the diagnostic ratio of
process-balanced modes for them, but they are also excluded from conclusions:

- `move/hot-a0-a0-n8388608`;
- `threads/cross-thread-free-4`;
- `threads/parallel-alloc-free-4`;
- `threads/parallel-alloc-free-96-4`;
- `threads/parallel-alloc-free-96-8`.

These are not semantic failures: all oracles match. The Pulse reporter can now
avoid discarding an entire finished snapshot because of this kind of
`Move`/thread drift and marks the fallback explicitly. The complete 297-case
Move matrix remains a separate exhaustive qualification; it need not be repeated
inside every general Pulse run.

Key hashes:

- compiler backend: `D29E15594AA0F65BAAC42D6E4BDEC336614CD5B50C86C503165B275F2FF3E52D`;
- compiler config: `810029B56ACC96C9E29ADF4B199D08D0097336FED209B53CCF7B89FEAAC2DF55`;
- bundled MM: `86DEAA048613F57B2100310A4AEA3C45B5C1F47E605A9A7B1DA1505E72A14B90`;
- Delphi `dcc64`: `68CF81C0B1044E585EB584D96947A01E669605D8AC1ED048A2DE44FD867FDB88`;
- raw manifest: `DEC17A7F7EADB3C05C8484D662EB7656468133F3E73A7A05E31265833D784536`;
- `summary.json`: `E0DA21193A67F9D70BDA65CA4A42A0875DFC1BBEA1FC099024DD7B0E893BBD8E`;
- `REPORT.md`: `703B24E78B4C74431BC99C9D758F5ABD82E21B9A80EEAD942CDE46772B9885D7`.

Full aggregate report: [REPORT.md](REPORT.md). Data for the shared historical
table: [summary.json](summary.json).
