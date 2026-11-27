# Re-exporting Units - `uses export`, `--project-uses`

A unit can pass the units it uses on to the units that use it, so one name in
a uses clause brings a whole set (C# `global using`, Rust `pub use`,
TypeScript `export * from`). And a project can give every one of its units
the same uses without writing it in each file.

Available in `{$mode unleashed}` (`-Munleashed`); elsewhere `export` before a
unit name stays a syntax error.

## `uses export`

```pascal
unit Lumi;

interface

uses export UI.Forms, UI.StdCtrls, UI.Grids, Data.Window;

end.
```

```pascal
program Orders;

uses
  Lumi;          { TForm, TButton, TGrid, TDataWindow are all visible }
```

- `export` right after `uses` passes on every unit of the clause.
- `export` before a later unit passes on that unit only:
  `uses SysUtils, export UI.Forms;` keeps SysUtils private.
- Only the interface uses clause can re-export; `export` in the
  implementation uses clause is an error (`03448`): its units are invisible to
  the users of the unit anyway.
- Re-export is transitive: a unit passed on that itself re-exports passes its
  units on as well.

### Which name wins

The passed-on units are visible as if they stood in the user's uses clause
right before the re-exporting unit. So:

- the re-exporting unit's own declarations win over the units it passes on
  (`Lumi.Who` hides `UI.Forms.Who`);
- units the user names after it win over both, as with any uses clause;
- every passed-on unit is also there by its qualified name
  (`UI.Forms.TForm`), even when a closer name hides the short one.

Naming a passed-on unit again in a later uses clause (for instance the
implementation uses clause of the user) is no duplicate.

### Recompilation

A user of the re-exporting unit records the passed-on units as its own
dependencies (their checksums go into its `.ppu`): when the interface of a
passed-on unit changes, the user is compiled again, even though it names
only the re-exporting unit.

### Why not wildcards

`uses UI.*` was considered and left out: which of the matching units hides
which is not defined by the source, and adding a unit to the folder changes
what an unchanged program means. `uses export` names every unit once, in one
place, and the order is the order written.

## `--project-uses`

```text
ppcx64 --project-uses=Lumi,AppCommon ...
```

Every unit and program compiled in the run uses the listed units, as if they
stood first in its uses clause (its own units win). `-Fa` does the same for
programs only.

- A unit that is one of them does not get itself.
- The units a project unit is built from do not get it either: a unit is
  skipped while the project unit that loads it has no compiled interface yet
  (with `-B`, the project unit's dependencies are compiled in the same run;
  giving them the project unit would be a circular reference).
- Naming a project unit in a uses clause as well is no duplicate.

The Lumi build tool passes the `"uses"` list of `lumi.json` here.

## PPU format

The interface part of a `.ppu` gets an `ibreexportunits` entry (the names of
the passed-on units) when the unit re-exports anything; it counts in the
interface checksum. PPU long version 49.
