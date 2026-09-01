# dvl-0003 — O2/O3 invert the finalization order while unwinding an exception

## Current status

Fixed by a shared lexical reverse-finalization repair. Permanent regressions:
`tests/test/cg/tdelphilocalfinalize1.pp` and
`tests/test/cg/tdelphilocalfinalizedefer1.pp`.

Found by Devil, `life` layer, `exception-unwind-deep` form, seeds 11 and 13,
cases `dvl-life-00004/00021/00053`. It was caught not by a value check but by an
observation: the layer prints the destruction order of managed locals as a
string, and the gate compared it between builds.

## Repro

`repro.dpr`: a recursive procedure holds a managed local at every level, throws
an exception at the bottom, and the destructor appends its tag to the trail.

| build | trail |
|---|---|
| Delphi 12.2 Win64 | `abx` |
| ours `-O-` | `abx` |
| ours `-O1` | `abx` |
| ours **`-O2`** | **`bax`** |
| ours **`-O3`** | **`bax`** |

`a` is the local in the deepest frame, `b` the outer local, and `x` entry into
the handler. Correct unwinding releases frames from inner to outer, that is,
`ab`. At O2/O3, the outer frame releases its reference before the inner one.

## Why this is dangerous

The order is not cosmetic. If an inner object refers to an outer one (owner,
buffer, connection), inversion means the inner destructor operates on an
already freed outer object. In normal code, that manifests as a rare AV on an
exception path, reproducible only under release optimization.

## Boundaries

- the optimization level is the only switch: `-O1` is correct, `-O2` is not;
- recursion depth 2 is sufficient;
- the value and number of checks do not change: the mismatch is visible only in
  the observable order, so an ordinary value test would not catch it.
