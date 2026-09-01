# MoonCompiler Performance Qualification

Pulse is MoonCompiler's in-repository benchmark system. It measures the
compiler, RTL, and memory manager from one Pascal source file and does not
accept a speed result until the semantic digest matches.

## What is measured

Tests are grouped by what they measure, not by the order in which they were
added:

| Group | Examples |
|---|---|
| Codegen and ABI | calls, loops, branches, integer/FP, records, managed ABI |
| RTL | strings, numbers, formatting, streams, encodings, tasks |
| Collections | list/queue/stack/dictionary, growth, search, deletion, managed values |
| Memory manager | small/medium/large allocation, realloc, threads, fragmentation |
| Algorithms | sort, search, hash, crypto, compression, numeric kernels |
| JSON | parse/generate through the mORMot API actually used |
| Heartbeat | compact models of parser, order book, buffers, correlation, FFT, and server hot paths |

A microbenchmark reports the cost of one specific operation. Heartbeat checks
that local wins survive in a composition where pointers, managed values, calls,
loops, and register pressure coexist.

## Compared systems

- `delphi` — Delphi 12.2 Win64 with its standard FastMM4;
- `moon` — MoonCompiler with the bundled MM;
- `moon-default` — the same MoonCompiler with the standard FPC MM;
- `moon-baseline`/`moon-candidate` — two MoonCompiler versions for causal A/B.

Stock FPC is not a common column: it does not build the tested Delphi 12.2
surface with the same Unicode RTL. Its components are compared in isolation
where physically possible; for example, `moon` versus `moon-default` separates the
allocator's contribution from the compiler and RTL.

## Measurement rules

Every case:

1. is built by the compared systems from one source file;
2. performs the same workload and prints a semantic digest;
3. is warmed up before measurement;
4. runs in several separate processes;
5. is compared by a stable central cluster of TSC samples.

Process drift, a mismatched digest, or a cluster that is too short or unstable
does not become a performance number. Such cases remain correctness checks but
are excluded from aggregates.

In reports, the ratio is `Moon / reference`:

- `0.80×` — MoonCompiler takes 80% of the reference time, so is `1.25×`
  faster;
- `1.00×` — parity;
- `1.20×` — MoonCompiler is 20% slower.

Aggregates are geometric means: one long case cannot hide many small
regressions, or vice versa.

## Final snapshot

Summary of the accepted release point:

| Workload | Reference | Cases | MoonCompiler result |
|---|---|---:|---:|
| Common cases before/after the repair series | original Moon/Unleashed baseline | 243 | `1.31×` faster |
| Full stable matrix | Delphi 12.2 + FastMM4 | 744 | `1.20×` faster |
| Heartbeat | Delphi 12.2 + FastMM4 | 20 | `1.22×` faster |
| RTL | Delphi 12.2 + FastMM4 | 77 | `1.45×` faster |
| Collections | Delphi 12.2 + FastMM4 | 48 | `1.37×` faster |
| JSON | Delphi 12.2 + FastMM4 | 18 | `1.16×` faster |
| Allocation | standard FPC MM with the same MoonCompiler | 15 | bundled MM `1.65×` faster |

Across the 243 common cases, the original baseline was at parity with Delphi
(`0.9978×`), while the final snapshot was `0.7625×`. The gain across that common
set therefore comes from the MoonCompiler repair series, rather than being
inherited from the original fork.

Full data:

- [final report](../qualification/performance/evidence/release-final-20260830/REPORT.md);
- [evidence and methodology for this run](../qualification/performance/evidence/release-final-20260830/EVIDENCE.md);
- [history of every substantial stage](../qualification/performance/PULSE_HISTORY.html);
- [known deferred tail](BACKLOG.md).

## How to reproduce

Win64 medium slice from a RAD Studio command environment:

```powershell
python qualification\performance\tools\pulse.py run `
  --mode medium --systems delphi,moon,moon-default `
  --tag local-medium
```

Without Delphi, Linux measures MoonCompiler and the contribution of the bundled
MM:

```bash
python3 qualification/performance/tools/pulse.py run \
  --mode long --systems moon,moon-default \
  --tag linux-long
```

`quick` is for checking the direction of a local repair, `medium` for working
A/B, and `long` for final evidence on an idle machine. First run the correctness
gates for the affected area; a benchmark does not substitute for semantic
qualification.

## How to accept an optimization

A change is accepted only when all four conditions hold:

1. the oracles and target ABI match;
2. the claimed buyer becomes faster;
3. neighbouring forms have no sustained regression;
4. ASM or a phase split shows exactly which work disappeared.

If the ratio changes without a machine-code change, that is placement/noise, not
a compiler repair. If a composite slows down, first separate allocation,
copying, lifetime, and the algorithm itself; one aggregate number is not a
license for an arbitrary RTL change.
