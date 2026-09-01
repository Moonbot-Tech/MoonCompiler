# dvl-0026 — `release` loses narrowing after return from a generic method

The analysis was reconstructed from the current gate run (seed 916, `gen` layer).

## What happens

The value `SmallInt(-32767)` passes through a generic method that returns its
argument and is then narrowed to `Word`.

| build | layer digest |
|---|---|
| `debug`, `o1`, `o2` | `B6D26FBE62BAD980` — matches the oracle |
| Delphi 12.2 | `B6D26FBE62BAD980` |
| **`release`** | **`D4D520F91CB7D980`** |

Check `dvl-gen-<N>-echo` turns red: unsigned narrowing is not performed and
the value arrives sign-extended.

## Related findings

This is the second of four known paths of the same defect:

| finding | path | profile |
|---|---|---|
| dvl-0001 | ordinary conversion and a unit boundary | `release` |
| **dvl-0026** | **return from a generic method** | **`release`** |
| dvl-0043 | assignment inside `with` | `release` |
| dvl-0045 | alias from another unit | `o2` |

The relationship matters: repairing one path does not close the others. That
is exactly how dvl-0026 survived the dvl-0001 repair.

## Reproduction

```
run_devil_gate.py --seeds 916 --cases 16 --layers gen --profiles debug,release --dcc ...
```

It does not reproduce in an isolated small program: inlining and
specialization decisions depend on unit size.
