# Pulse evidence: integration-final-20260823

This is a versioned summary of the complete Win64 O3 medium run of exact current
`main`. Raw logs, binaries, and the complete manifest intentionally remain in
ignored `results/pulse/integration-final-20260823`; Git contains the complete
aggregate report and machine-readable values for every case.

- source HEAD: `81daffaa8bd943c02a011f57b2af6e94085d398f`;
- worktree at manifest capture: clean;
- system: Windows 11 x86-64, AMD Family 25 Model 33, 16 logical CPU;
- mode: `medium`;
- matrix: 390 cases, Delphi 12.2 / Moon+bundled MM / Moon+default FPC MM;
- executions: 7 separate processes per system/case, system order interleaved
  and repeated; 7 samples within a process;
- semantic oracle: `390/390 MATCH`;
- result excluding nine unstable cases: Moon/Delphi geomean `0.7318`,
  `195` faster, `118` at parity, `68` slower;
- allocator group excluding unstable `alloc-free-1m`: bundled MM / default
  FPC MM geomean `0.6179`, meaning the bundled MM is `1.62` times faster on
  average.

Nine cases have at least one process pair with drift above 1.25x and are marked
with `†` in HTML:

- `abi/record16-value`: Moon 1.880x;
- `codegen/scan-llc`: Moon-default 1.278x;
- `codegen/scan-strided`: Moon-default 1.739x;
- `managed/interface-copy-call`: Moon-default 3.092x;
- `mm/alloc-free-1m`: Delphi 1.334x, Moon 1.391x, Moon-default 1.449x;
- `rtl-collections/objectlist-owned-clear`: Moon 1.284x;
- `rtl-collections/stack-string-roundtrip`: Delphi 1.259x;
- `workloads/stream-scale`: Delphi 1.268x;
- `workloads/stream-triad`: Moon 1.295x, Moon-default 1.277x.

This is not a semantic failure: executable hashes match within each system, all
oracles match, and the spread is created by individual processes. Cases are
retained in raw evidence and in the shared table but excluded from the results
above and focused performance conclusions.

Across the 379 shared stable cases of the previous and current snapshots,
Moon/Delphi geomean changed from `0.7233` to `0.7323` (the current snapshot is
`1.24%` slower). This is a cross-snapshot comparison, not pre/post A/B of one
change, so it records product state but does not itself prove a regression in a
particular fix.

Key hashes:

- compiler: `2448238e15a306be14b6a24433afa8cb5c0641e1204d055d97baa289f9d2d53c`;
- compiler config: `91f931689135277c317a9fb325b42b9bdbb5995e165b51bae7d8de39e52a8543`;
- bundled MM: `b0af17e29e98cca60a8c5ca8a7670552b78b43cafa6171289a4a6c6107ff40af`;
- Delphi `dcc64`: `68cf81c0b1044e585eb584d96947a01e669605d8ac1ed048a2de44fd867fdb88`;
- raw manifest: `1D4F2B7AD5B214F6F65303AACD3B43876ACD9A0D4C0E93F86B82394FE07F14A0`;
- `summary.json`: `6FED59C7E92069679A24E25F06E85881EE56BBA6E30B03820D0CF1EE0A19F216`;
- `REPORT.md`: `61FF43400157C77EE3577B689B9116909989731E09449486A3C343B72F144C03`.

Full aggregate report: [REPORT.md](REPORT.md). Data for the shared historical
table: [summary.json](summary.json).
