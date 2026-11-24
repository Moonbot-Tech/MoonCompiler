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
The weak-field PPU test assigns a weak record field across a unit boundary
and checks that it clears when its target is destroyed. Three compile-time
probes also check the diagnostics for passing that field to a strong `var` or
`out` interface parameter and for exposing a weak `class threadvar` subfield
directly as an RTTI property. [Test source](cases/RttiWeakPpu.dpr).

Every process must exit successfully, print its completion marker and emit
exactly one `FPCX64MM_DIAGNOSTIC live-blocks=0` result. A correct value and exit
code alone do not prove absence of leaks. `test_gate.py` checks that missing,
duplicate and nonzero balance reports fail acceptance.

The default matrix has 198 Windows and 189 Linux executions. Both qualification
and release archive checks run it. Linux callback tests use libffi (`libffi-dev`
on Debian/Ubuntu). `--group`, `--profiles`, `--config`, `--bindir` and repeated
`--unit-dir` options support isolated repair stands; release checks use only the
installed SDK driver, without private replacement units.
