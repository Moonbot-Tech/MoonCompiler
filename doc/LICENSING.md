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

The Runtime Library and FPC packages carrying the FPC linking notice retain
LGPL v2.1 or later with that static-linking exception. Other bundled components
retain their individual licenses, listed below; the exception does not apply
automatically to every package. The RTL license text is in
[rtl/COPYING.txt](../rtl/COPYING.txt), and the exception is in
[rtl/COPYING.FPC](../rtl/COPYING.FPC). The exception permits linking the RTL
into an application without making that application an LGPL derivative solely
because of that link; changes to the RTL units themselves remain under their
original license.

## Bundled Memory Manager

`runtime/mm/mormot.core.fpcx64mm.pas` retains the original mORMot license
header: a choice of MPL 1.1 / GPL 2+ / LGPL 2.1+ with the FPC linking exception.
A copy of the notices is in [runtime/mm/LICENSE.md](../runtime/mm/LICENSE.md).

## Bundled Brotli Decoder

The optional `Moon.HttpClient.Brotli` unit links Google's Brotli 1.2.0 decoder
under the MIT license. Using `System.Net.HttpClient` alone does not link it.
Its unmodified source archive, build script and license are retained in
[`packages/vcl-compat/native/brotli`](../packages/vcl-compat/native/brotli).
Binary distributions include `share/doc/mooncompiler/BROTLI-MIT.txt`.

## Static Regular Expression Engine

The Delphi compatibility regex units link PCRE2 10.49 under its BSD license and
exception. The source archive includes the separate BSD notice for its SLJIT
backend. Windows also links the GCC stack-probe runtime fragment under GPLv3
with the GCC Runtime Library Exception. Its original source, license and
exception are retained with the [native build recipe](../packages/libpcre/native).
The binary toolchain includes the applicable notices in `share/doc/mooncompiler`.

## Windows SDK Declarations

The direct SDK units derived from the existing open FPC/JEDI headers retain
their individual MPL 1.1 / LGPL notices and attribution. We distribute these
under the MPL 1.1 option. Removing Jwa unit dependencies does not remove those
licenses. The [source map and dated modifications](../packages/winunits-base/NOTICE-WINDOWS-SDK.md)
and [full MPL text](../packages/winunits-base/MPL-1.1.txt) accompany the Win64
toolchain. The declarations and small SDK macro translations are not copied
from Embarcadero's proprietary RTL.

## Optional Diagnostic Reports

`runtime/reporting` uses the RTL license and linking exception; see its
[notice](../runtime/reporting/LICENSE.md). Linux uses a dynamically loaded
system libunwind, which is not bundled in this source directory.

## External mORMot Qualification Inputs

Qualification fetches
[`Moonbot-Tech/MoonORMot`](https://github.com/Moonbot-Tech/MoonORMot) and a
separate public upstream mORMot compiler corpus at exact commits. Neither full
source tree is included in MoonCompiler Git history; each retains its own
license and third-party notices.

## Practical Rule

You may modify, build, and redistribute MoonCompiler, the RTL, MM, and tests,
including through a public GitHub fork, provided that license headers and
notices are retained and the source is available for MoonCompiler and every
distributed GPL/LGPL/MPL component. Your own applications may remain under
their own license within the applicable linking exceptions.
