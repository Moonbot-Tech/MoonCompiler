# An inlined getter's value read straight from its source

```text
python qualification/optimizer-core/getter-borrow/run_getter_borrow_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --output /new/directory
```

An inline getter of a string or a dynamic array (`Result := FName`,
`TList<string>.Items[I]`) owns a reference of its own only where its value
goes somewhere a routine can run before the value is read to the end: an
argument of a call, above all. Everywhere else the inliner hands the source to
the consumer (`compiler/optcall.pas`, `mark_funcret_borrow`): an element or a
character by an index without calls, a comparison, the empty test,
`Length`/`High`, the step of `Inc`/`Dec`, a store without a helper, the string
helpers and the dynamic-array assignment - also where the consumer appears
only when an enclosing inline routine is expanded, and where the getter's
object is itself the value of another inlined getter (`L[I].Name`,
`B.Child.Name`) or its list is a field (`FNames[I]`): the temp that holds the
object goes to the consumer with the value
(`compiler/ncal.pas`, `optimize_funcret_assignment`).

`getter_borrow.dpr` is run at -O2 and -O3. In the -O3 object the gate counts
every probe routine - instructions without padding and calls, a routine
together with its outlined finalizer - against `reference.json` of the target:
a routine that grew is red; one that shrank is reported, and `--record` writes
the new counts on purpose. Apart from the counts, the borrowed forms call no
assignment helper, no release and no finalizer, and `KeepToCall`,
`KeepChainToCall` and `KeepIndexCall` still take the result's own reference -
the RR-06 hole stays closed. The
compiler before the repair fails the borrowed forms: each took a reference,
a release and an implicit cleanup frame.

The same gate also runs `run_record_copy_gate.py`. An unmanaged record/array
returned by an inline getter is copied once, including a receiver or index
computed by a call and range/overflow-checked builds. `record_copy_probe.dpr`
checks whole-record values, lower/upper index bounds, exceptions before the
destination write, aliased inputs and the value snapshot passed to a mutating
`const` consumer. It inspects ten x86-64 routines for a single copy.
`aggregate_sizes.dpr` covers record and static-array sizes 1, 2, 4, 8, 16, 32
and 64 bytes with side effects and repeated temporary lifetimes. Both run at
O0/O2/O3, with checks, with automatic inlining, and without register variables.

The standalone copy gate accepts the same `--compiler`, `--config` and
`--output` arguments. The probe's optional `chain`, `index` or `simple`
argument times a fixed number of operations (second argument, default 50M).
That timing is a local mechanism benchmark, not an application or Pulse
qualification result. The default gate does not run the benchmark.
