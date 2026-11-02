# Ordinal case storage contract

Raw input can place an unnamed value in an enum or a value outside a declared
integer subrange. `case` must execute its `else`, or continue after the statement
when no `else` exists. The declared range is not proof that memory contains only
named values. A selector is evaluated exactly once.

`run_gate.py` generates independent expected results for all byte patterns and
wider storage boundaries. It covers dense, partial, sparse, grouped, single
label, range and no-else dispatch; one-, two- and four-byte enums; nonzero and
sparse enumerations; signed and unsigned subranges; full-width integer controls;
ordinary Boolean and character controls; and separately compiled producers.
O-, O1, O2, O3, size optimization, range/overflow checks and warm PPU reuse run
under the normal Windows/Linux qualification and CI.

Additional cases cover labels at the signed and unsigned 64-bit boundaries,
real `TMemoryStream` input into a class field, and constant/inlined Boolean
variants with noncanonical nonzero values. These detect comparison-tree
constant conversion failures and incorrect Boolean constant folding.

The Boolean matrix also covers typed and mixed-width labels, reversed source
order, one-arm cases, full and nonzero-only ranges, and duplicate truth labels.
It checks calls, properties, short-circuit expressions and checked indexing:
selector effects happen once and exceptions precede the selected body. Invalid
labels must produce their specific frontend diagnostic, never a compiler crash.
Existing FPC `False..True` ranges remain accepted; numeric range-order checks
precede normalization to Boolean truth values.

An internal-assembler object check also preserves the established 12/13-label
linear chains, guarded 37-label table, padded near-full tables, sparse trees,
grouped membership tests and 64-bit selector width. It needs GNU or LLVM
`objdump` (`MOON_OBJDUMP`, PATH, or the installed Windows bootstrap).

```
python qualification/optimizer-core/case-storage/run_gate.py --compiler PATH --config PATH --output NEW_DIRECTORY
```

`--delphi --compiler PATH_TO_DCC64 --output NEW_DIRECTORY` checks the shared
enum/subrange surface with Delphi 12.2. Its Int64 control is restricted to
signed 32-bit input values: the tested Delphi Win64 case does not preserve the
independent oracle on wider extrema. Moon's Int64 checks retain those values.
Delphi's limitation is not adopted as the Moon oracle.
Likewise, Delphi's dynamic C-style Boolean cases disagree with its own constant
folding for noncanonical stored values. The Delphi control uses canonical
dynamic values; Moon's independent truth oracle covers all byte patterns.
