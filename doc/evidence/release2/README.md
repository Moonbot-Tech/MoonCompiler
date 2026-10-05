# Selected second-release measurements

This is the measurement record for the examples in the
[release notes](../../RELEASE_NOTES.md). It contains preselected useful
operations, not a release-wide average.

The 5 October 2026 comparisons use the release 2.0 compiler, RTL and bundled
memory manager. The full Pulse workloads were built and measured at
`83315fe3b92b2bafc478c9a16ec9424fa8a62382`; exact toolchain identities are
recorded below. The first-release baseline is
`ccaa5fbaf5ec5bfeef09a3f3f049ffe603d9509c`. Windows measurements use
Ryzen 7 5800X (BRO-3); Linux measurements use Intel Xeon W-2295 (HEL1).
Delphi 12.2 comparisons are Windows-only. Old and new Moon builds use their
complete product Release profiles. The old published August table is not used
to calculate release-to-release ratios.

[`measurements.json`](measurements.json) records the exact case identifiers,
comparison direction, accepted pairs, semantic digests, identical-program
controls, CPU cost centers, ratios and interval bounds. Source result and raw
SHA-256 values preserve the provenance of the selected records. Each refreshed
runtime comparison has twelve accepted pairs, matching semantics and a qualified
CPU-cost estimate. Windows measurements use three samples with a 60 ms total
work target. The Moon-to-Moon comparisons use the twelve-phase stack grid on
both platforms. The Delphi comparison uses the supported fixed stack mode on
both sides; it does not mix a Moon phase grid with a fixed Delphi call frame.

The operation list was selected before these measurements. The Windows
release-to-release column uses only those preselected rows that have twelve
clean pairs and matching digests; their sample metrics were independently
recomputed from the saved raw records. It does not claim that the complete
Windows Pulse corpus passed. A dash in the release notes means that no refreshed
number is published for that comparison. The Linux source passed the complete
Pulse validator, including independent confirmation. Bounded completion filled
its rejected indices using the original executable bytes, CPUs, work counts,
stack phases and variant order after a fresh identical-program control.
Original accepted pairs were retained. The record keeps original source and
raw hashes separately from the completion revision. The Delphi column is a
separate ten-operation comparison with twelve clean pairs and fresh controls.

Exact `RoundTo` is qualified against the mathematical result of the actual
binary input stream. Where that result differs from the first release's
rounding, the row is not a like-for-like performance comparison and contributes
no speed claim here. The release validator retains the differing digests and
requires a separate reproducible correctness proof.

The reported reduction is `100 * (1 - ratio)`, rounded to the nearest whole
percent. Ratios use the cost of equal useful work; they are not throughput
percentages. The rows are individual operations and sizes. Do not sum their
percentages or infer an application's operation mix from this selection.

The three bundled-versus-standard-FPC allocator examples retain their separate
4 October provenance and six-pair plan under `historical_allocator_measurements`.
They compare allocators with the same Windows compiler; they are neither Delphi results nor
release-to-release compiler measurements.

For a new full comparison use the fixed-work Pulse route in
[Performance Qualification](../../PERFORMANCE_QUALIFICATION.md). The release
controller additionally requires the complete program set, twelve valid pairs
per case and independent confirmation. The selected feature measurements here
and that full release gate have separate purposes. Release correctness and
delivery qualification can explicitly exclude Pulse with `--skip-pulse`; its
result records that scope rather than implying a performance qualification.
