# Plant Application-Topology Gate

Plant tests application structure rather than a large arithmetic corpus. It
combines forms that meet in production programs: a C-style export table and
callback, lazy static registries, engines registered during unit
initialization, class factories, reference-counted services, and legal unit
dependency cycles.

The gate varies three independent axes:

- Debug, O1, O2, and Release profiles;
- every optimizer switch enabled alone over O1 and disabled alone from
  Release;
- four legal orders of the units in the program `uses` list.

## Oracle

`plant.dpr` recomputes the channel, engine, and service results with flat
arithmetic. It also requires exactly two registered engine kinds, one callback
per ticket, and zero live engines or services after cleanup. Only that complete
check prints `PLANT_OK`.

The Python runner requires every build to print the same `PLANT_OK` line. A
compile failure, a changed value, or a result that does not start with the
marker is a finding.

## Run

From the repository root, run the complete matrix with explicit evidence
paths:

```text
python qualification/suite/scripts/run_plant_gate.py --work .qualification/plant --report .qualification/plant.json
```

`--quick` retains the four profiles and four initialization orders but omits
the individual optimizer-switch matrix, so it is a local diagnostic cycle, not
the complete Plant gate.

Plant is also a mandatory stage of the full Devil command documented in
[Devil](../devil/README.md#running). The broader role of this composition layer
is described in [MoonCompiler Test System](../../docs/TESTS.md#additional-devil-axes).
