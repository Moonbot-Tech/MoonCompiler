# Calls that only forward their result

Release can replace a register-only forwarding call with a tail jump before
the compiler creates its stack frame and unwind records. The target receives
the original caller's return address and, on Win64, its shadow space. The
wrapper has no locals, outgoing stack arguments, saved registers, exception
cleanup or meaningful work after the call. Register allocation records the
target's volatile registers, so a different calling convention cannot bypass
the wrapper's nonvolatile-register contract.

Debug keeps the original call and frame. In Release an optimized forwarding
frame no longer appears in a target's stack trace, just as an inlined frame
does not. `noinline` controls inlining; it does not demand a stack frame.
Explicit `STACKFRAMES`, stack checks, profiling, frame/caller intrinsics,
assembler and cleanup retain their existing contracts. The existing late
tail-call peepholes are not enabled more broadly.

Run `python qualification/optimizer-core/tail-forwarding/run_gate.py
--toolchain <installed-toolchain> --output <evidence-directory>`. An optional
`--compiler <ppcx64>` selects another backend with the same installed runtime.
The runner uses the installed Debug/Release configuration, records its hash,
the resolved paths, source/backend/executable hashes and every compile command.
Runtime binaries use the product's internal assembler. A separate compilation
stops at the assembly listing for structural checks; it does not supply the
executed binary. Both invocations build fresh units. The old backend fails the positive tail-jump
assertion; a runtime-only pass is insufficient.

The checks cover direct/virtual/indirect calls, reordered integer/FP arguments,
hidden record results, virtual constructors, C variadic argument metadata,
cross-ABI nonvolatile GPRs, caller cleanup, managed locals, stack arguments, local
addresses, return zero extension, explicit frames, stack introspection and the
Win64 safecall result protocol. The exception witness exercises both an
exception in the target and a nil fault inside the forwarding wrapper, with
caller handlers and finally blocks. The latter distinguishes valid leaf unwind
information from a late CALL/RET rewrite that leaves the old CFA stack offset.
Debug and Release traces record the exact frame-removal boundary.
