# Qualification Benchmark

This is the suite's compact correctness-digested benchmark, separate from the
published Pulse and Heartbeat performance system. It is useful for comparing
compiler, RTL, and MM candidates only after every workload produces the
independently proven result.

Seven workloads cover 64-bit integer mixing, signed division and remainder,
floating-point affine updates, byte and UTF-8 scans, 256-byte `Move`, and small
managed allocations. `benchmark_portable.pas` is the shared Pascal
implementation; `benchmark_oracle.py` independently models the same work.

## Run

The runner is Linux-only: it records Linux host topology, requires `taskset`,
and pins measurement to the CPU selected by `runner_manifest.json`. From
`qualification/suite`:

```bash
python3 runner.py benchmark \
  --compiler moonbot-compiler-beta --option O3
```

The runner first executes the Python oracle at the short proof length and
checks the versioned long-run proof for the actual warmup and measurement
lengths. It then builds one executable for each selected compiler/profile,
runs one semantic sample, and only after that runs the pinned performance
samples.

## Verdict and measurements

Every warmup and sample must report the expected workload name, iteration
count, and digest. A compile error, timeout, nonzero exit, incomplete sample
set, or semantic mismatch makes the case fail.

The manifest requests nine performance samples. The report retains wall and
thread-CPU time, host and affinity data, all raw samples, and derived rates. Its
primary metric is the median CPU nanoseconds per iteration among the three best
samples; if the best-three stability ratio exceeds the manifest limit, the
measurement is marked noisy rather than promoted as a performance result.

For the full release order and the rule that correctness precedes speed, see
[MoonCompiler Test System](../../docs/TESTS.md#benchmark). Pulse methodology
and published application-level comparisons are documented separately in
[`qualification/performance`](../../../performance/README.md).
