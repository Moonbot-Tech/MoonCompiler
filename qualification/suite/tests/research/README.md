# Research probes

These programs preserve executable evidence for deliberately unsupported edge
contracts and experiments that are not release gates. They must not be added to
the ordinary smoke route unless the corresponding product contract changes.

- [`numeric_edge_contracts.pas`](numeric_edge_contracts.pas) exercises exact
  decimal rounding, extreme cancellation, subnormal values and externally
  modified x87/SSE state. The normal product contract and its rationale are in
  [Known Deviations](../../../../doc/KNOWN_ISSUES.md#floating-point-edge-cases).
