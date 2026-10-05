# Selected second-release measurements

This is the measurement record for the examples in the
[release notes](../../RELEASE_NOTES.md). It contains selected confirmed useful
operations, not the full Pulse corpus or a release-wide average.

The 4 October 2026 comparison used the integrated implementation
`54b63f39b54e066c56e30f76625d26856370293e` and first-release baseline
`ccaa5fbaf5ec5bfeef09a3f3f049ffe603d9509c`. The Windows host was BRO-3 (Ryzen);
the Linux host was AMD4 (Ryzen 7 7700). Delphi 12.2 comparisons are Windows-only.
Old and new Moon builds use their complete product Release profiles. The old
published August table is not used to calculate any release-to-release ratio.

[`measurements.json`](measurements.json) records the exact case identifiers,
comparison direction, accepted pairs, semantic digests, identical-program
control result, CPU cost centers, ratios and interval bounds. Source result
SHA-256 values preserve the provenance of the selected records. Every selected
row passed its semantic and A/A requirements and has a qualified CPU-cost
estimate. Invalid or unresolved measurements are not used as numerical claims.

The reported reduction is `100 * (1 - ratio)`, rounded to the nearest whole
percent. Ratios use the cost of equal useful work; they are not throughput
percentages. The rows are individual operations and sizes. Do not sum their
percentages, infer an application's operation mix, or present this selection as
the complete release qualification.

For a new full comparison use the current fixed-work Pulse route in
[Performance Qualification](../../PERFORMANCE_QUALIFICATION.md). The release
controller additionally requires the complete program set, twelve valid pairs
per case and independent confirmation. The selected feature measurements here
and that full release gate have separate provenance and purposes.
