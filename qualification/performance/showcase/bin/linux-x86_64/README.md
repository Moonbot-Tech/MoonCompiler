# Ready-made Linux programs

Run all three comparisons from the parent showcase directory with
`./reproduce.sh run`. The four executables are both sides of the comparison:
`showcase_moon`, `showcase_rust`, `orderbook_moon`, `orderbook_rust`.

Requires Linux x86-64, glibc 2.34 or newer and `libgcc_s.so.1`.
These are ordinary x86-64 builds without host-specific CPU tuning.
[SHA256SUMS](SHA256SUMS) identifies the supplied files.

Build them from the included sources with `./reproduce.sh build`.
The public SDK is MoonCompiler 2.5.3; MoonORMot is
`f62a8f24ba6f05b8289adf938fc5199395db3cf9`; Rust is 1.97.1.
