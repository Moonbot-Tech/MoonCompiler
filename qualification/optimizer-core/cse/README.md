# Managed-load CSE profitability gate

`run_managed_load_gate.py` compiles the semantic witness with CSE disabled,
enabled explicitly, and enabled through the `-O3` default. All three programs
must preserve dynamic-array, `AnsiString`, and managed-record lifetime and
produce the same deterministic digest.

The assembly check covers direct local dynamic-array and string descriptor
loads plus a string field inside a managed record. Until immutable managed
value temps have a sound register location, moving any of these cheap
descriptors to a memory-backed CSE temp adds a load and store and cannot remove
any original consumer loads. Explicit CSE and no-CSE must therefore emit the
same normalized bodies for all three routines. A true record/static-array/
object CSE root is a separate boundary: CSE stores its address rather than its
managed value, so the profitability guard leaves that carrier path enabled.
`ThreadTextProduct` supplies the positive profitability boundary: a managed
threadvar access is expensive enough that explicit/default CSE must still
differ from no-CSE and share the value after one access.

On Linux the runner resolves `libgcc_s` through the host GCC driver, so a clean
invocation needs no machine-specific `-Fl` argument. Additional compiler
options remain available through repeated `--compiler-option` arguments.
