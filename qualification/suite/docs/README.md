# Qualification Suite Documentation

These documents describe the qualification contracts behind the commands in
the [suite README](../README.md). Start with the test-system map; use the other
documents only for the specialized environment or MM question they cover.

| Document | Use it for |
|---|---|
| [MoonCompiler Test System](TESTS.md) | Test layers, oracles, accepted deviations, runner contracts, focused and full routes, and the release order. |
| [Additional Reference Toolchains](LAB_SETUP.md) | Historical A/B compilers and the comparison toolchain needed by the PPU-version gate. These are not prerequisites for an ordinary product build. |
| [Measuring the Bundled Memory Manager](MEMORY_BENCHMARK.md) | MM benchmark shapes, cross-machine normalization, evidence rules, and the boundary between correctness and speed. |

Executable inputs are indexed in [`tests`](../tests/README.md). Commands should
be taken from the suite README or the relevant test-system README so the pinned
compiler, runtime profile, and oracle are preserved.
