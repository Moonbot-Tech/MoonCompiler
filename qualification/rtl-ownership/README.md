# RTL ownership contracts

Run `python qualification/rtl-ownership/run_gate.py` against the installed product
SDK, or pass `--compiler` to an unpacked SDK's `fpc` driver. The gate builds fresh
programs in Debug, Release O2 and Release O3, then checks observable values,
destructor counts, restored exception stacks and product memory-manager balance.
No timing measurements or external services are involved.

Coverage includes managed RTTI fields, properties and callback var/out arguments;
empty values, self-assignment, failed casts, custom record copying and fresh
result buffers; static property metadata consumed from a PPU without its source;
acquired exceptions, nested replacement, bare rethrow, cross-thread ownership,
`TThread.FatalException`, finally replacement and hardware exceptions. Windows
also checks Exit/Break/Continue through a throwing finally inside an outer catch.
Class-threadvar RTTI accessors are outside this gate; ordinary static class
storage and direct thread-local access are distinct contracts.

Every process must exit successfully, print its completion marker and emit
exactly one `FPCX64MM_DIAGNOSTIC live-blocks=0` result. A correct value and exit
code alone do not prove absence of leaks. `test_gate.py` checks that missing,
duplicate and nonzero balance reports fail acceptance.

The default matrix has 195 Windows and 186 Linux executions. Both qualification
and release archive checks run it. Linux callback tests use libffi (`libffi-dev`
on Debian/Ubuntu). `--group`, `--profiles`, `--config`, `--bindir` and repeated
`--unit-dir` options support isolated repair stands; release checks use only the
installed SDK driver, without private replacement units.
