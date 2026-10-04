# Numbers of the x86-64 inline assembler

Both readers of inline assembler - AT&T (`compiler/raatt.pas`,
`compiler/x86/rax86att.pas`) and Intel (`compiler/x86/rax86int.pas`) - turn
text into numbers: integers in every base, characters and strings, floating
point, constant expressions, immediates, displacements, scale factors and
alignments.  Each spelling must become the number it says, or stop the
compilation; it must never become another number silently.

`forms.tsv` is the inventory of those spellings.  An `accept` row carries the
bytes the form assembles to - for AT&T the bytes of GNU as 2.46 assembling the
same text, for Intel those of Delphi 12.2 (`dcc64`) or the written value, for
a float the correctly rounded value; where the encoding differs from the
reference (`movabs` for `mov r/m64, imm32`, a SIB absolute address for
Delphi's RIP-relative one) the row keeps the operand the text says.  A
`refuse` row carries the message that must stop the compilation: a value the
field cannot hold, two operands without an operator, an alignment the
directive cannot carry, an operator GNU as or Delphi reads differently.

`run_gate.py` builds the accepted forms of each group into one program at
`-O-` and `-O3`; the program finds every form between marker bytes in its own
code and compares it with the table (`a|b`: either encoding of the same
instruction - with optimization on, the reader writes `[idx*2+d]` as the
shorter `[idx+idx+d]`; `HEX@GVX:N`: HEX, then the address of the variable
`GVX` plus N as the linker writes it; `align:N`: the form ends on N with a
padding shorter than N, `align:N:HEX` the same after the form's own bytes
HEX).  Every refused
form is compiled alone and must fail with its message.  The forms may name
`CFIVE` (5), `CTWO` (2), the record `TRR` (field `B` at 4) and the variable
`GVX`, which the gate declares.  Everything is compiled in Delphi mode, the
mode of the product configuration (`fpc.cfg`) and of the inventory: there
`dword ptr 5` is a constant, in ObjFPC mode a reference.

The table comes from an inventory of 924 spellings, each assembled by the
compiler and by its reference (GNU as for AT&T, Delphi for Intel); 49 are
left out of it with their reason: the host precision of 80-bit reals, syntax
the reader does not have (such as `.double 1.5` without `0d`), a relocated
value in a 32-bit field, a form of another class.  An integer in a float
directive is read by its base, as in the integer directives (`.double 010` is
8.0, `0x10` 16.0), where GNU as reads a decimal flonum (10.0); the table keeps
that reading.  On the compiler before the repair the gate fails: 115 refused
forms compile, and the byte comparison of the accepted forms meets 94 other
readings.

```powershell
python qualification/compiler-asm-numbers/run_gate.py
python qualification/compiler-asm-numbers/run_gate.py `
  --compiler <ppcx64.exe> --rtl <units/x86_64-win64/rtl>
```
