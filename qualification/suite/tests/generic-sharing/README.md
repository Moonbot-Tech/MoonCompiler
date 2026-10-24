# Shared generic type contracts

Run `qualification/build-driver/generic_sharing_gate.py` with the installed SDK
compiler and a new `--results` directory. Both CI platforms run this gate.

The fixtures cover identity across independent units, distinct nominal types,
nested types, virtual/interface dispatch, managed state, class constructors and
destructors, RTTI discovery/Invoke/attributes and component streaming. Definition
RTTI policy must survive a different policy in the consuming unit.

Debug, O2 and O3 each run together, with reversed unit order, and from source-free
PPUs. Cached rebuilds change method bodies, layouts and interfaces and introduce
an implementation dependency cycle. A mixed Debug/optimized exception fixture
checks unwind ownership and actual function/file/line lookup with full Debug and
compact Release diagnostic tables, in both link orders.

Constant arguments distinguish full integer payloads, real values, sets and
strings; equal supported arguments share their owner. Anonymous string/set
constants can retain separate identities. A shared owner's field and return-type
RTTI must match direct TypeInfo references from each consumer, including generic
arrays, named nested pointer/callback/class-reference types, anonymous arrays and
records, distinct sibling fields, and managed `TValue` reads/writes. Standalone
generic routine address-taking is outside this optimization.

SDK upgrades require rebuilding PPUs: the generic symbol ABI uses PPU long version
48. The PPU header remains version 208.
