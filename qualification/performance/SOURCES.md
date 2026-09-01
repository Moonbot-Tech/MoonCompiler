# Sources of Pulse ideas

Pulse neither publishes the results of other benchmark suites under their names
nor copies their final scores. Their primary repositories were used as an
external completeness audit only after the first independent matrix was built.

- LLVM test-suite: `SingleSource`, `MultiSource`, and `MicroBenchmarks` levels,
  mandatory reference outputs, and scientific, compression, media,
  pointer-intensive, FFT/LU/sparse-matrix/vectorization classes.
- FPC `tests/bench` and `tests/bench/shootout`: Pascal-specific division/case/
  float/RTL, spectral norm, N-body, fannkuch, binary trees, Mandelbrot,
  text/hash and thread-ring workloads.
- PolyBench/C: static-control kernels with runtime bounds, non-zero input,
  live-out digest, and dead-code-elimination protection; Pulse adopted the
  missing Floyd-Warshall and Jacobi stencil cases.
- EEMBC CoreMark: runtime seeds, controlled output, linked list, matrix,
  numeric state machine, and CRC as a connected workload.
- Google Benchmark: dynamic calibration, warm-up, repetitions, raw machine
  context, CPU vs wall timers and explicit performance counters.

The exact primary references are given in the root methodology and must be
rechecked before a public release.
