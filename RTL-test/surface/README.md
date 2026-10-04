# RTL surface closure

This directory turns RTL coverage into a source inventory rather than an
informal list of interesting regressions.

`scope.json` is the exact Win64 product surface taken from the installed RTL,
RTL-ObjPas, RTL-Generics, FCL-Base, FCL-STL and VCL-compat packages. The check
always reports both closed and still-open units; one reviewed unit can no
longer make the whole product look green.

For every closed unit, `manifest.json` pins all public routine declarations
and all implementation routine bodies. The listed executable tests must
contain at least as many named call sites as the unit exposes overloads; review
maps those sites to signatures, and the compiler resolves and type-checks them
in every selected build mode. A changed declaration, a new overload, a new
implementation helper, or a deleted test makes the check fail until the unit
is reviewed and its tests are updated.

Run the structural gate from the repository root:

```text
uv run python RTL-test/surface/check_surface.py --verbose
```

The final closure gate is stricter:

```text
uv run python RTL-test/surface/check_surface.py --require-complete
```

It remains red until every unit in `scope.json` has been inventoried and has
executable semantic tests.

Run the executable oracles separately with `RTL-test/run.py`. Structural
closure prevents silent holes in the inventory; runtime tests still need
independent expected values and boundary cases for every branch. A unit is not
added to the manifest until both parts are present.
