# MoonCompiler 2.0: the second release

This release makes ordinary Delphi code cheaper to execute and easier to build
and diagnose on Win64 and Linux x86-64. The changes cover the compiler, Unicode
RTL, collections, memory manager and the installed toolchain as one product.
Applications keep their Pascal source, managed types and normal library calls.

## Text and message processing

Substring search, case-insensitive name checks and UTF-8 decoding now do less
work in the common path. `Pos` uses a shared, bounded x86-64 UTF-16 search;
`SameText` checks equality directly and can reject a different short name early.
UTF-8 decoding handles adjacent two-byte characters together, while retaining
validation of malformed input. Converting an integer `Variant` to Unicode text
avoids intermediate ANSI and BSTR strings.

Searching ordinary ASCII keys in `TStringList` no longer creates uppercase
copies or invokes the full locale machinery for every candidate. Non-ASCII
inputs and user-defined comparison behavior keep their appropriate general
paths. This matters in configuration lookup, message dispatch and protocol
field processing, where comparison is repeated many times.

## Dictionaries, lists and buffers

Dictionary work improved across lookup, updates, enumeration and growth. Flat
lookup avoids repeated searches, and rehashing can transfer ownership of plain
managed values without incrementing and then decrementing their references.
Custom comparison and managed-record operations retain their contracts.

Measured Linux examples against the first release include 56% less CPU cost for
numeric-key lookup, 52% for string-key lookup, 70% for `AddOrSetValue`, and 26–37%
for enumeration. Growing dictionaries with numeric keys and string values use
36–41% less CPU in the measured sizes. These are improvements to indexes,
caches and state tables, rather than just faster construction of an empty object.

An ordinary list with reserved capacity can insert a simple element without
the general notification setup when no observer or override needs it. An exact
`TMemoryStream` can change its logical length without a buffer transaction when
the existing capacity can be retained under its normal shrink policy. A uniquely
owned string result of the required size can reuse its allocation for repeated
`Copy` operations.

## Loops and resource management

The compiler retains more useful pointers and intermediate values in registers
and removes redundant index copies. Eligible loops with a runtime bound use a
remaining-iteration counter. Ordinal `case` labels sharing the same action can
be combined into membership tests, which helps mixed byte-oriented scanners.

Short `try/finally` blocks perform normal cleanup directly while preserving the
exception path. Small implicit cleanup sequences on Win64 avoid unnecessary
dispatch on an ordinary return. Passing an already owned aggregate result to a
`const` consumer avoids technical copies without dropping user-defined
`Initialize`, `Assign` or `Finalize` operations.

These changes benefit operations such as scanning messages, walking arrays of
records, calculating a recent weighted price, and releasing local resources.
They preserve floating-point evaluation order, exception behavior and ownership.

## Selected measurements

The table shows **CPU cost removed for the same work**, rounded to whole
percentages. A 25% reduction means that the operation takes three quarters of
its former cost; it is not a 25% whole-application speedup.

| Operation | Versus Delphi 12.2, Win64 | Versus first Moon release, Win64 | Versus first Moon release, Linux |
|---|---:|---:|---:|
| Find a substring in a 64-character UTF-16 string | 24% | 53% | 59% |
| Decode 32 Cyrillic characters with `TEncoding.UTF8.GetString` | 60% | 83% | 79% |
| Decode the same text family with `UTF8ToString` | 48% | 62% | 64% |
| Convert an integer `Variant` to text | 17% | 76% | 82% |
| Find an ASCII key in a 128-entry `TStringList` | 90% | 91% | 94% |
| Add or update a numeric dictionary entry | 69% | 69% | 70% |
| Fill a reserved dictionary with 100 numeric keys and string values | 13% | 52% | 57% |
| Resize `TMemoryStream` within its existing capacity | 71% | 75% | 75% |
| Scan mixed JSON bytes, medium input | 32% | 38% | 34% |
| Loop with a short `try/finally` | 37% | 29% | 28% |

These selected examples were measured on 4 October 2026 at the integrated
release implementation `54b63f39b54e066c56e30f76625d26856370293e`. The first
release baseline is `ccaa5fbaf5ec5bfeef09a3f3f049ffe603d9509c`. Windows comparisons
use the local Ryzen system; Linux comparisons use Ryzen 7 7700. Each comparison
builds the same workload with each side's complete Release profile and requires
matching semantic digests and an accepted identical-program control. The
[measurement record](evidence/release2/README.md) gives exact case identifiers,
ratios and provenance. This is a selection of confirmed improvements, not a
complete benchmark average or a prediction for an entire application.

The bundled memory manager also remains useful independently of compiler
optimizations. With the same Windows compiler, the measured live-block ring,
fragmented mixture and `ReallocMem` growth workloads require 64%, 41% and 36%
less CPU respectively than the standard FPC memory manager. That comparison
changes the allocator, not the compiler, and is separate from the release-to-
release columns above.

## Exact decimal rounding

`RoundTo` now rounds the actual binary floating-point input to the requested
decimal position under nearest/even rounding. The ordinary path uses hardware
arithmetic; difficult half-boundaries use an exact fallback. This avoids a
slightly inaccurate decimal scale changing which side of a rounding boundary
the value lands on. The supported floating-point environment is described in
[Known Deviations](KNOWN_ISSUES.md#floating-point-edge-cases).

## Faster compilation

Large programs with many generated classes no longer repeatedly register an
already active symbol table while building virtual method tables. In the
controlled large-program experiment, a full source rebuild fell from 81.5 to
21.6 seconds. The paired executables without user debug information were byte
identical. A subsequent uninstrumented build with the original debug settings
took 23.7 seconds. This is a measured large-program example, not a universal
compiler-speed ratio; the number and structure of classes determine the benefit.

## A portable product build

The installed `fpc` owns the product profile. A normal project builds directly:

```text
fpc hello.dpr
fpc -dRELEASE hello.dpr
```

These select Debug and Release. Both use the same Unicode and runtime contract;
Release enables the product optimizations. There is no Python build driver in
the application build path. A larger project puts source paths, aliases and
defines in its adjacent `.mooncompiler` option file. Compiler-unit output is
separated by platform and profile.

The release archive contains the compiler, RTL, packages, tools and runtime
units. MoonORMot remains a separate clone next to `toolchain`. Lazarus uses an
isolated ordinary FPC ABI for the IDE and LCL, leaving the application Unicode
profile separate. See [installation](SETUP.md) and [project builds](PROJECT_BUILD.md).

## Libraries and diagnostics

The Delphi-compatible surface now includes buffered file streams, lightweight
reader/writer locks, mask matching, socket address storage, and URL/header
types. `System.ZLib` supplies one native zlib on each target. `System.Zip`,
multipart MIME and `System.Net.HttpClient` build over the project's MoonORMot,
including archive integrity checks, streamed request bodies, redirects,
cancellation and TLS validation.

`Moon.Diagnostics` provides optional local exception and all-thread reports.
It keeps the original exception context, uses embedded names and source lines,
and can attach application data or upload a saved report. Expected-error paths
can disable capture per thread or for the process. See the
[diagnostics guide](DIAGNOSTICS.md) for initialization and deployment requirements.

## Qualification and upgrading

The release route covers Windows and Linux, language and RTL contracts, the
complete generated Devil corpus, managed lifetime, threading, compiler
self-builds, mORMot, archive consumers and installation, Lazarus and Pulse.
Independent correctness tests share a bounded worker budget. Cold-build and
determinism checks still rebuild; later reuse consumes only validated PPUs.
Final Light tests the same artifact that passed Full and verifies its complete
identity. [Testing](TESTING.md) describes the reproducible route.

Install the new toolchain as a complete unit, then cleanly rebuild application
and third-party units with it. Do not mix PPUs from different compiler versions
or from the IDE and Unicode application profiles. Keep the required MoonORMot
version next to the toolchain and retain embedded debug information when using
diagnostic reports. The [supported boundaries](KNOWN_ISSUES.md) remain the
reference for compatibility.
