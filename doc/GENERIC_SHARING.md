# Generic types across units

Win64 and Linux link one runtime instance of a generic type for the same generic
declaration and the same concrete arguments. Independent units
can therefore use the same dictionary, list or application generic without
retaining a separate copy of its methods, class tables and RTTI in every unit.
No application source change or extra compiler switch is required.

The shared class has one identity and one set of class variables. Managed class
variables, class constructors and destructors are initialized and finalized once;
unit initialization order remains significant. Distinct nominal types and
different argument tuples retain distinct instances. RTTI follows the policy at
the generic declaration, including when a consuming unit uses another policy.

The linker keeps exception-unwind data with the selected method implementation.
Full Debug information and compact Release diagnostics remain available. RTTI
discovery returns each shared type once, retaining its first catalog position.

There are no new lookups or guards in ordinary method calls, field accesses or
dictionary operations. Shared managed state uses bookkeeping during unit startup
and shutdown. `TRttiContext.GetTypes` uses a temporary pointer set to remove
duplicate catalog entries; the set is released when the enumeration returns.

Sharing also includes dependent generic arrays, named nested types and anonymous
field types, so field and method RTTI matches direct `TypeInfo` references from
every consuming unit. Distinct anonymous sibling declarations stay distinct.
Standalone generic routines retain their existing behavior. Anonymous string/set
constant arguments can conservatively retain separate instances.

Rebuild all application and third-party PPUs when upgrading. PPU long version 48
records the new generic symbol ABI; incompatible cached PPUs are rejected. The
PPU header stays at version 208.

The permanent cross-platform gate covers clean/cached builds, separate and
source-free units, reversed uses order, Debug/O2/O3, nominal and constant argument
identity, initialization/finalization, RTTI, component streaming and mixed-codegen
exception unwinding. See
[`generic_sharing_gate.py`](../qualification/build-driver/generic_sharing_gate.py).
