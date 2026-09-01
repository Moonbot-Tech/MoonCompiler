# dvl-0013 — casting between byte strings recodes instead of reinterpreting

The analysis was reconstructed from facts in the current run; the previous text
was lost with the working directory.

## Status

Fixed at the first broken boundary. An explicit Delphi cast between
`AnsiString(CP)`/`UTF8String`/`RawByteString` is now a storage view and preserves
the pointer, bytes, and actual code-page header. Ordinary assignment still
recodes. Both paths are checked by `tests/test/cg/tdelphibytestringcast1.pp`;
the ObjFPC control preserves the previous FPC semantics.

## What happens

A byte string with one code page is cast to a byte string with another. By
contract, the cast must **reinterpret** the same bytes — change the label, not
the content. The observations record the result length and first byte.

| observation | ours | Delphi 12.2 |
|---|---|---|
| length after cast (`uni` layer) | **8**, **2**, **12** in different forms | expected: unchanged from before the cast |
| first byte (`uni` layer) | **`$D0`**, **`$D1`** | expected: original byte |
| length in a chain (`chain` layer) | **4** | **2** |
| first byte in a chain | **`$D0`** | **`$C6`** |

`$D0`/`$D1` are the first UTF-8 bytes of Cyrillic characters, while `$C6` is the
same character in a single-byte encoding. The length doubled. This is the
signature of recoding: the string was not relabelled, it was translated.

## Why this is costly

Casting between byte types is a normal protocol-parsing technique: bytes arrive
and must be read as a string of the required code page without changing them.
Instead, translation happens here, placing different bytes on the wire. The
length changes as well, so the subsequent size is wrong too.

## Reproduction

```
run_devil_gate.py --seeds 3,4 --cases 60 --layers uni,lang --profiles debug,release --dcc ...
run_devil_gate.py --seeds 3,4 --cases 40 --layers chain --profiles debug,release --dcc ...
```

`dvl-uni-<N>-cast-byte`, `dvl-uni-<N>-cast-length`, and the same forms inside
chains fail.

## Boundaries

Checked in `debug`, `o1`, `o2`, and `release` — identical in all profiles.
