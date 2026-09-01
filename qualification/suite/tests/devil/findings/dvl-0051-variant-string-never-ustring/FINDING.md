# dvl-0051 — fixed: a Unicode string in `Variant` has the Delphi subtype and a complete runtime path

Found by the `resident` layer, in the `shape-variant-transit` and
`shape-variant-states` stages, with Delphi 12.2 as the oracle.

## What happens

Which type does a Variant receive when a string is assigned to it:

| assigned value | ours | Delphi 12.2 |
|---|---|---|
| `string` variable | `8` (`varOleStr`) | `258` (`varUString`) |
| `UnicodeString` | `8` | `258` |
| non-ASCII literal | `8` | `258` |
| **ASCII-only literal** | **`256` (`varString`)** | `258` |
| `WideString` | `8` | `8` |

`varUString` never appeared in any case. Wide strings became `varOleStr`, while
an ASCII-only literal became `varString`, that is, a byte string.

## The data remains intact

This was checked by round-tripping a string made of the characters `0410 20AC
0041`: by assigning a variable, using a literal, and using
`VarAsType(..., varOleStr)`. In every case, the returned content was identical
character by character. Comparing the Variants to each other was also correct.
No encoding was lost; only the declared type differed.

## Why this still matters

The Variant type is not decorative; code makes decisions from it:

```pascal
case VarType(V) of
  varUString, varString: Text := V;   { every string reaches this branch in Delphi }
  varInteger:            Number := V;
end;
```

A parser written for Delphi that distinguishes `varUString` would never take
that branch with our compiler. Conversely, a caller checking `varString` would
unexpectedly receive an ASCII literal, causing a “byte string” branch to run
where the programmer intended a wide string.

The inconsistency **within our own runtime** was separately problematic: the
same literal in semantic terms produced `varString` when it was ASCII-only and
`varOleStr` when it contained even one higher character. The Variant type thus
depended on data content rather than expression type, so code decoding a Variant
could behave differently for different input data.

## Reproduction

`probe/varstr.dpr`: the characters are specified by code point rather than as
source letters, so the result does not depend on the file encoding. It is built
by the standard driver; the oracle is Delphi 12.2 `dcc64` with
`-U<lib\win64\release> -NSSystem`.

## Status: fixed

Both root causes were fixed: Unicode assignment now creates `varUString`, and
assignment-operator lookup no longer loses the AST form of an ASCII literal.
The first run afterwards revealed a neighbouring runtime defect: VariantManager
did not classify `varUString` as any common type and crashed during comparison.
That is fixed as well: copy/cast/clear, Unicode comparison, and concatenation
now form a complete path. The full language layer then revealed the final gap:
writing `varUString` to a Variant `SAFEARRAY` crashed. It was fixed at the
shared `sysvararrayput` point: a Pascal-managed string is stored in the OLE
array as a BSTR, exactly as in Delphi.

`tdelphivariantstring1` compares one source against Delphi 12.2; independently
preserves `WideString -> varOleStr` and `AnsiString -> varString`; checks the
complete 3×3 matrix of concatenation result subtypes; and covers direct
`VarArrayOf`, element-wise assignment, and Unicode assignment overloads outside
a Variant. It runs in O-/O2/O3; a separate Delphi oracle confirms BSTR storage
inside the SAFEARRAY.
