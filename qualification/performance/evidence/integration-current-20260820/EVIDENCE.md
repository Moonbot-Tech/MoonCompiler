# Pulse evidence: integration-current-20260820

This is a versioned summary of the complete Win64 O3 medium run of the safe
integration line. Raw logs and binaries intentionally remain in ignored
`results/pulse/integration-current-20260820`; Git contains the complete
aggregate report and machine-readable values for every case.

- source HEAD: `c0139f0ea4cf7f0265a7df9ef349fff8c77dc612`;
- worktree at manifest capture: clean;
- system: Windows 11 x86-64, AMD Family 25 Model 33, 16 logical CPU;
- mode: `medium`;
- matrix: 390 cases, Delphi 12.2 / Moon+bundled MM / Moon+default FPC MM;
- executions: 7 separate processes per system/case, system order interleaved
  and repeated; 7 samples within a process;
- semantic oracle: `390/390 MATCH`;
- result excluding three unstable cases: Moon/Delphi geomean `0.7230`,
  `203` faster, `120` at parity, `64` slower.

Three cases have process drift above 1.25x and are marked with `†` in HTML:

- `loops/histogram-random`: `moon-default` 1.301x;
- `managed/closure-create-invoke`: Delphi 1.266x;
- `mm/alloc-free-1m`: Delphi 1.298x, Moon 1.347x.

This is not a semantic failure: executable hashes and oracles match for every
process, while the deviation is created by individual fast processes relative
to the main cluster. These three cases are retained in raw evidence but
excluded from focused performance conclusions and the final geomean above.

Key hashes:

- compiler: `7cd7b16c657b13873c86ed68b37fd0c3f62d2d69042f95b9fd098a2b475de9d3`;
- compiler config: `2aa3a135a3187aacb8ae576676e7fe2c1321a20c16165448877720aad9020d28`;
- bundled MM: `55f37fb89b369af454a482698c05e8fb74bc9f18f2e96e4a64b6b8ac43dd0535`;
- Delphi `dcc64`: `68cf81c0b1044e585eb584d96947a01e669605d8ac1ed048a2de44fd867fdb88`;
- raw manifest: `B451C6CD8E137691E9A10BAC7246019C170F4F24CEB4E1E415B83ADC95756BCF`;
- `summary.json`: `9684C509DBCD5286290E2A1010F6BB0DFC0AB8F33D387D05930525DA55D64D38`;
- `REPORT.md`: `82B008909FF98D7240116510B3512910484E0E6E355E782570D1DEC1D4E02D87`.

Full aggregate report: [REPORT.md](REPORT.md). Data for the shared historical
table: [summary.json](summary.json).
