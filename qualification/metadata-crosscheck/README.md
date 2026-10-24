# Metadata crosschecks

These tests complement the structural DWARF, immutable RTTI pool, generic-sharing,
unwind-encoding and reporting gates. They use explicit runtime values and exact
caller chains. A successful build, a positive line number or an unchanged CFI
table alone is insufficient.

`release_metadata_gate.py` runs the Invoke/report corpus on Win64 and Linux and
the instruction-PC unwind sweep on Linux. Both scripts require a new results
directory. The tests create private executables and never patch the SDK or an
application outside that directory.

## RTTI, ABI and reports

```text
python qualification/metadata-crosscheck/invoke_corpus_gate.py --compiler <toolchain/bin/fpc> --reports --results <new-directory>
```

Use `toolchain/bin/x86_64-win64/fpc.exe` on Windows. The compiler's normal product
configuration selects the SDK. Python's standard library is the only additional
runner dependency.

The corpus builds two independently compiled classes in both unit orders, hides
all their sources, and links the consumer against their PPUs. Debug and Release
exercise integer and floating register/stack overflow, mixed managed arguments,
small and large records, hidden results, open/dynamic arrays, var/out values,
interfaces, static methods, attributes and reflective exceptions. All method,
parameter and attribute names/payloads have explicit expectations. TypeInfo/VMT
identities and interface destruction are checked separately.

With `--reports`, each reflected exception produces one report inside `except`
and one after acquisition and exit from `except`. The runner checks report
completion, original exception text, exact function/file/line, nonempty raw PCs
and identical original PC lists across the two reports. The raise counter keeps
the sampled raise PC inside its source row, avoiding the documented exact-row
boundary ambiguity of the existing line-reader API. Debug's ordinary method
name and Release's qualified method name are checked independently.

A separate execution changes an input value while retaining the original
expectation. It must fail specifically on the array result. This prevents a
build-only or vacuous oracle. Omit `--reports` for the smaller reflection-only
run; the default qualification path enables reports.

## Signal-context unwind at actual instruction PCs

```text
python qualification/metadata-crosscheck/unwind_traps_gate.py --compiler <toolchain/bin/fpc> --results <new-directory>
```

Linux x86-64 requires `gcc`, `objdump` and the runtime `libunwind.so.8`; libunwind
development headers are unnecessary. The normal five configurations are O-, O2,
O3, O- plus Os, and O3 plus Os. AUTOINLINE is disabled for this fixture so its
call chain exists. The O-/Os combination must actually execute `LEAVE` in every
tested function.

Each subprocess replaces one instruction's first byte in its own private text
page with `int3`. The SIGTRAP handler restores that byte, resets RIP to the
original instruction, and traverses the kernel-provided context through
`unw_init_local2(..., UNW_INIT_SIGNAL_FRAME)`. Returning from the handler executes
the original instruction. Recovered addresses must identify every expected
caller in order: Leaf -> EH -> Middle -> Anchor, or the corresponding full
suffix. The runtime checksum and exactly three managed cleanups must also hold.

All reached instructions are tested, including entry, stack/CFA changes and
return. Cold branches that the fixed inputs do not execute are recorded as
unreached rather than counted as passed. Entry and return are mandatory for
each function. A negative control truncates recovery to the first frame; the
same oracle must reject it.

For an isolated compiler executable, `--config <flattened-product.cfg>` supplies
an absolute-path product configuration. `--optimization=-O-,-Os` selects one
configuration; repeat the option for several configurations. Results include
compiler/backend hashes, disassembly, per-PC outcome, exact recovered chains,
failures and negative-control output. Any reached incorrect chain fails the
gate; no baseline exception is silently allowlisted.

The unwind fixture also keeps seven Pascal integer results live across calls.
In O2/O3 this must produce and execute five successive nonvolatile GP pops
(RBX/R12--R15); the gate checks that this physical shape is present. A scalar
passed to an opaque C observer forces an eight-byte local slot in AuditLeaf,
so its POP RCX release is checked separately. The observer changes no value.
The original full caller-chain, checksum, cleanup and negative-control oracles
remain active at each reached instruction boundary.
