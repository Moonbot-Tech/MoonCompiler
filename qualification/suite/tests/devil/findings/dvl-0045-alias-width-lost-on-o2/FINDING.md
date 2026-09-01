# dvl-0045 — fixed: a PPU alias preserves unsigned narrowing

## Current status

The common long-distance narrow-extension repair closed this form too. The exact
`ppu` layer, seed 5, 25 cases, Debug/O1/O2/Release, and PPU reuse produced 24
identical checks for each variant, one digest, and 0 findings.
The entry was removed from `known_findings.json`; the original diagnosis is
retained below.

Found by the new `ppu` layer on its first run. This was the fourth path for the
same disease as dvl-0001, dvl-0026, and dvl-0043, with one important difference:
it occurred **not under `release`**, but under `o2`.

## What happens

The producer module declares an alias:

```pascal
type
  TDvlPpuNarrow = type SmallInt;
```

The consumer sees only the compiled module and asks two questions: the type
width and an unsigned reading of the value:

```pascal
var V: TDvlPpuNarrow := TDvlPpuNarrow(-32767);
Answer := UInt64(Cardinal(SizeOf(V))) shl 16;
Answer := Answer or UInt64(Word(V));
```

| Build | Answer |
|---|---|
| `debug`, `o1`, `release` | `$00028001` — width 2, value `$8001`, correct |
| Delphi 12.2 | `$00028001` — correct |
| **`o2`** | **`$FFFF8001`** |

`$FFFF8001` is sign extension instead of narrowing to `Word`: its signature is
identical to dvl-0001. The width is then overwritten because the narrowing
result occupies every high bit.

## Difference from its relatives

| Finding | Path | Profile |
|---|---|---|
| dvl-0001 | Ordinary cast, module boundary | `release` |
| dvl-0026 | Generic-method result | `release` |
| dvl-0043 | Assignment inside `with` | `release` |
| **dvl-0045** | **Type alias declared in another module** | **`o2`** |

The profile matters: `o2` is not the production profile, but it demonstrates
that the defect is not tied to the full optimization set. Its root is therefore
not one `-O3` pass, but the narrowing rule itself, which activates earlier.

## Reproduction

```
run_devil_gate.py --seeds 5 --cases 25 --layers ppu --profiles debug,o1,o2,release --dcc ...
```

The `dvl-ppu-alias-width` observation and the `ppu` layer subtotal turn red,
and only in the `o2` build.

## Why this is costly

A `type SmallInt` alias declared in a shared module and used everywhere else
is an ordinary form for protocol and domain types. A value read as unsigned
arrives sign-extended, silently: there is no error or warning. The
profile-dependent difference makes it still worse—the build used for
verification may be correct while the shipped one is not.
