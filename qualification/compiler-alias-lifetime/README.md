# Strong alias lifetime

`run_alias_lifetime_gate.py --compiler <pp> --config <moon-base.cfg> --output <new-directory>`
builds the producer at O-/O2/O3, physically hides its source, and runs the PPU
consumer. It checks enum/subrange, managed records, value objects, class
inheritance, packed/array layout, and inline functions. The ordinary compiler
checks semantics; `--ownership` also requires zero counters from the instrumented
compiler.

`run_alias_reload_gate.py --source <compiler-source> --compiler <pp> --build-config
<vanilla-fpc.cfg> --msg2inc <installed-msg2inc> --config <moon-base.cfg>
--output <new-directory>` runs only in its own copy of the source tree. For a
clean source checkout, it generates `msgtxt.inc`/`msgidx.inc` there with the
installed `msg2inc`. A separate stand can pass `--command <build.json>` instead of
`--compiler/--build-config`; the JSON contains the argument array for an ordinary
`pp.pas` build with `-Fu{source}`, `-FU{output}`, and `-FE{output}` placeholders.
That form also needs `--msg2inc` if its source has no generated message includes.

The full runner adds two direct ownership counters to TSymtable and traces actual
`re_resolve`, builds the instrumented compiler, runs the PPU gate, adds three
cross-unit strong aliases, and changes interface AASMTAI. Clean and incremental
selfbuilds must finish with zero tables and zero refs; the incremental build must
actually execute `re_resolve`. Compilers built by both paths then compile the
same source; the resulting binaries must match byte for byte.

The full runner is a targeted check of compiler lifetime. It does not replace
product qualification or claim anything about compilation speed.
