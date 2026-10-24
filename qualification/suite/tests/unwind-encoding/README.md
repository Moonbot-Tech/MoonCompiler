# Linux x86-64 unwind encoding regression

These tests preserve the compact unwind encoding contract. They require a built
candidate SDK, Python 3 and GNU binutils (`readelf`, `nm`, `ld`). No Python packages
or machine-specific paths are required. Each results directory must be new.

The ordinary fast gate:

```sh
python3 qualification/build-driver/unwind_encoding_gate.py \
  --compiler /path/to/toolchain/bin/ppcx64 \
  --config /path/to/expanded-product.cfg \
  --results /path/to/new-unwind-results
```

`--config` is optional when the compiler finds its installed configuration.
When supplied, paths and includes must be valid for that compiler invocation,
just as for the other build-driver gates.

It checks two named functions independently through `nm` and `readelf`: a frame
without LSDA must use `zR` and have no LSDA slot; a frame with cleanup must use
`zPLR` and the proper LSDA/FDE widths. Both functions retain nonempty PC ranges.
The program proves 1000 catches and managed/finally cleanups at runtime. Builds
cover the internal assembler, `-Xa`, external `-Aas`, and genuine ET_DYN PIE.
GNU ld may relativize the native-width personality in PIE; that valid linker
rewrite is accepted, but the LSDA/FDE encodings remain exact assertions.
A separate tiny object proves that a PC32 displacement beyond 2 GiB fails
explicitly while `-Xa` links successfully.

The slower signed-range gate uses disposable compiler copies:

```sh
python3 qualification/build-driver/unwind_range_guard_gate.py \
  --compiler-source /path/to/candidate/compiler \
  --bootstrap /path/to/toolchain/ide/bin/ppcx64 \
  --bootstrap-config /path/to/toolchain/ide/etc/fpc.cfg \
  --config /path/to/expanded-product.cfg \
  --results /path/to/new-unwind-boundaries
```

The source directory must contain the generated `msgtxt.inc` and `msgidx.inc`
from a compiler build. The bootstrap configuration uses the ordinary FPC/IDE ABI.
Only copied sources are instrumented: after actual symbol-difference resolution,
the test substitutes MaxInt, MaxInt+1 and -1. The first value must compile; the
other two must fail with the explicit range-overflow diagnostic. `-Xa` keeps the
64-bit path. This tests the real assembler check without allocating a 2 GiB
function; it does not pretend to execute such an image. No production test hooks
or compiler-source modifications are needed.

The fixtures deliberately use vanilla runtime and exit status instead of Pascal
I/O. Existing baseline `-Xa` failures in the product MM and Writeln are outside
this metadata contract; the same exception and cleanup assertions still run.

Do not duplicate the broader matrix here:

- `generic_sharing_gate.py` already checks mixed optimization, reverse link order,
  source-free PPUs, generic COMDAT selection and actual unwind/symbolization.
- `run_reporting_gate.py` checks real reports, AV, worker rethrows and libunwind.
- `qualification/rtl-ownership/run_gate.py --group exception` checks exception
  identity, replacement, Acquire/Release and destruction.
- Existing Win64 generic/pdata gates own native unwind verification; this Linux
  encoding change does not replace those tests.

Both gates write commands' output and `results.json` with the compiler/source
hash. A format regression must fail even if exception handling still happens to
work with the larger legacy format.
