# Licensing

This repository brings together several components under different compatible
licenses. Source files and notices must not be removed when redistributing them.

## Compiler

The Free Pascal / Unleashed compiler sources are distributed under GNU GPL v2
or later. MoonCompiler compiler changes are published under the same terms.
The license text is in [compiler/COPYING.txt](../compiler/COPYING.txt).

The compiler's GPL does not automatically extend to a program it compiles: the
license applies to the compiler itself and its derivatives.

## RTL and Packages

The Runtime Library and packages retain LGPL v2.1 or later with the FPC
static-linking exception. The license text is in
[rtl/COPYING.txt](../rtl/COPYING.txt), and the exception is in
[rtl/COPYING.FPC](../rtl/COPYING.FPC). The exception permits linking the RTL
into an application without making that application an LGPL derivative solely
because of that link; changes to the RTL units themselves remain under their
original license.

## Bundled Memory Manager

`runtime/mm/mormot.core.fpcx64mm.pas` retains the original mORMot license
header: a choice of MPL 1.1 / GPL 2+ / LGPL 2.1+ with the FPC linking exception.
A copy of the notices is in [runtime/mm/LICENSE.md](../runtime/mm/LICENSE.md).

## Product mORMot Test Fixture

`qualification/vendor/mormot-product` is used only as a test fixture and
retains its own [LICENCE.md](../qualification/vendor/mormot-product/LICENCE.md).
A new public mORMot corpus is fetched from the official repository at an exact
commit and is not included in MoonCompiler Git history.

## Practical Rule

You may modify, build, and redistribute MoonCompiler, the RTL, MM, and tests,
including through a public GitHub fork, provided that license headers and
notices are retained and the source is available for MoonCompiler and every
distributed GPL/LGPL/MPL component. Your own applications may remain under
their own license within the applicable linking exceptions.
