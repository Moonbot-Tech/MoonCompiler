# dvl-0044 — rejected: `-gl` changes program composition, not only metadata

## Result of the causal check

This is not a compiler defect. By FPC contract, the `-gl` switch pulls in the
`LineInfo` unit; on Win64 it pulls in `ExeInfo`. An exact standalone probe
enumerated two types present only with `-gl`: `LineInfoCache` and `TExeFile`.
Without `-gl`, the corresponding units are absent from the program, so the
static RTTI catalog correctly does not contain their types.

The original modes gate compared different unit graphs and incorrectly called
the behavioral difference metadata-dependent. The check now compares DWARF2
with DWARF3: the debug-information format changes, but linked units do not.

The initial analysis is retained below as the history of a false hypothesis.

Found by the new **modes gate**: it builds the same source with different build
knobs that are forbidden to affect behavior, comparing not image bytes but what
the program counted.

## What happens

One source, one `release` profile, differing only in the debug-information
switch:

| Build | Types returned by `TRttiContext.GetTypes` |
|---|---|
| With debug information (`-gl -gw3`, as in the driver) | **6867** (`$1AD3`) |
| Without it (`-g-`) | **6865** (`$1AD1`) |

Two types appeared in the catalog only because debug information was enabled.
The program's root digest also differed, so this was not merely a “measurement
wobble”—behavior differed.

## Why it seemed costly

Debug information is a build knob, not part of the program. Anything depending
on it ceases to be a property of the code:

- **Catalog traversal gives a different result in debug and release.** Code
  enumerating types (serializer registration, descendant discovery, DI
  containers) sees two additional types in a debug build. “Works in debug, not
  in release” is the most expensive class of diagnostic failure.
- No diagnostic occurs: both builds succeed and both are “correct.”

## Reproduction

```
run_devil_modes_gate.py --seed 5 --cases 25
```

The `no-debug-info` mode turns red: its `digest` and
`dvl-rtti-<N>-gettypes` observation differ. The direct check is to build one
source twice, with and without `-g-`, and compare the
`DEVIL_NOTE …-gettypes` line.

## Boundaries

Checked with the `release` profile. The other seven knobs exercised by the
gate (smart linking, symbol stripping, verbosity, disabled assertions, and a
build over ready PPU) **do not** change behavior; only debug information
diverged.
