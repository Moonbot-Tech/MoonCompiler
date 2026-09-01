# Findings Without a Dedicated Analysis

The registry guard (`check_devil_registry.py`) checks three locations: a
folder in `findings/`, the journal, and the status table. This file lists items
that have no folder and never will, so the guard does not remain red forever and
the reason stays recorded.

## Analyses restored

Fifteen analyses lost with the working directory (dvl-0012…dvl-0026) were
restored from scratch, not from memory but by reproducing them on the current
compiler: every finding was run with the registry disabled so the discrepancy
would surface openly, and the tables contain values from that run. The earlier
wording is lost forever; the facts are current.

## No separate analysis is needed

These are differences where the oracle is wrong: there is nothing to fix, and a
journal entry is sufficient.

dvl-0008 — Delphi's `GetTypes` does not enumerate a type without explicit RTTI;
our catalog is more complete.
dvl-0009 — Delphi folds `Inf-Inf` to zero instead of NaN; our result follows
IEEE.
