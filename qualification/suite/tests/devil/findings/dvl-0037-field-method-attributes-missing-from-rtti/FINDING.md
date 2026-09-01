# dvl-0037 — attributes on fields and methods do not reach RTTI: code compiles, the framework finds nothing

## Current status

Closed by a causal repair to extended RTTI. The product default publishes
class/record fields, public properties/methods, and their attributes without a
directive in source; explicit visibility also governs the payload. The exact
Delphi/FPC attribute layer is pinned in
`RTL-test/semantic/attribute_rtti_semantic.dpr` together with dvl-0040.

Found while investigating dvl-0033: once an attribute with its own constructor
compiles, it must be visible through RTTI. Not everything is visible.

## What happens

The same `[Mark(N)]` attribute is placed on different targets; the program reads
them back through `TRttiContext` and sums the tags.

| attribute target | ours | Delphi 12.2 |
|---|---|---|
| class | reaches RTTI | reaches RTTI |
| record | reaches RTTI | reaches RTTI |
| interface | reaches RTTI | reaches RTTI |
| enumeration | reaches RTTI | reaches RTTI |
| `published` property | reaches RTTI | reaches RTTI |
| **`public` property** | **empty** | reaches RTTI |
| class field | reaches RTTI | reaches RTTI |
| record field | reaches RTTI | reaches RTTI |
| **method** | **empty** | reaches RTTI |
| `class var` | does not compile (dvl-0032) | reaches RTTI |
| parameter | does not compile (dvl-0032) | reaches RTTI |

After Delphi-default RTTI was enabled, fields were fixed. An attribute on a
method or a `public` property is still **silently accepted and not written to
the tables** by the compiler. `GetAttributes` returns an empty array, with no
errors or warnings.

The boundary is now narrower: default visibility creates field records, but the
writer still does not form method and `public` property records with attributes
consistently.

## Why this is costly

This is the worst possible form of rejection. With dvl-0033 the module does not
compile—the author sees the problem immediately. Here everything compiles, but
the framework reading attributes simply does not see the annotations: a
serializer finds no fields, an ORM finds no columns, and a DI container finds no
injection points. The error surfaces far from the cause—as empty JSON, an empty
database string, or `nil` in a field—and it will be sought in the framework
rather than the compiler.

Methods and properties are primary attribute targets alongside the already fixed
fields: routing, DI, RPC, and serializer policies are built on them.

## Reproduction

`repro-standalone.dpr` prints the sum of tags across three targets at once:
after the repair, ours is `15` (type + field), Delphi is `24` (type + field +
method).

Through the suite: the `attr` layer, cases `dvl-attr-<target>-readback`.

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: identical in all profiles;
this is table generation. Adjacent: attributes on a parameter, inline variable,
and `class var` do not parse at all (dvl-0032); an attribute without its own
constructor does not compile in any position (dvl-0033).

## Status: fully fixed

The root of the remaining defect was not the writer: tables for methods and
`public` properties with attributes were emitted into the binary in full (asm
confirms it: method records carry references to attribute tables and the VMT
slot is populated), and the TypInfo layer read them. The break was in the Rtti
layer: `DefaultUsePublishedOnly` in the non-dotted `rtti.pp` branch was
hardcoded to `True`, and every `TRttiContext` filtered members down to
`published`, although the `TObject.SystemHasExtendedRTTI` runtime gate for the
Delphi profile had long been ready. Both branches are aligned to
`Not TObject.SystemHasExtendedRTTI`.

DCC64 matrix: type 1, fields 2, methods 20 with two declared methods, and
`public` property 8—byte-for-byte. Pin:
`RTL-test/semantic/attribute_rtti_semantic.dpr` (green under DCC64 too,
together with the directive part of dvl-0040). The registry entry was removed.
