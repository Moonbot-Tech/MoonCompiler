# `uses export` and `--project-uses`

```text
python qualification/compiler-uses-export/run_gate.py \
  --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
```

See `unleashed/docs/uses-export.md`.

| Case | What it checks |
|---|---|
| `uses-export` | `uses export ReexpA, ReexpB;` in a unit's interface: a program using that unit sees ReexpA and ReexpB, the unit's own names win (`Who`), a passed-on unit is reachable by its qualified name (`ReexpA.Who`) |
| `uses-export-item`, `uses-export-item-only` | `uses ReexpA, export ReexpB;`: only the marked unit is passed on; a type of the other one is unknown to the users |
| `uses-export-implementation` | `export` in the implementation uses clause is an error (03448) |
| `uses-export-no-unused-hint` | A unit used only for the names it passes on gets no "unit not used" hint (`-vh`) |
| `uses-export-recompile` | A unit that names only the bundle is compiled again when the interface of a passed-on unit changes |
| `project-uses` | `--project-uses=ReexpBundle`: a unit without a uses clause and the program get the unit; the program naming it again is no duplicate |
| `project-uses-build-all` | The same with `-B`: the units the bundle is built from are compiled in the same run and do not get the bundle (no circular reference) |