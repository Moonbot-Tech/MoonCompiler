# Moon.Diagnostics

The Pascal sources in this directory are part of the MoonCompiler runtime and
use LGPL v2.1 or later with the FPC static-linking exception, like the RTL.
See [the license](../../rtl/COPYING.txt) and
[the linking exception](../../rtl/COPYING.FPC).

Linux loads the system `libunwind.so.8`; its implementation is not copied into
this directory. Preserve that library's own notices if distributing it with
an application. Win64 uses operating-system unwind APIs.

ZIP and HTTP delivery use the external
[`Moonbot-Tech/MoonORMot`](https://github.com/Moonbot-Tech/MoonORMot) checkout
under its own license and third-party notices.
Preserve the notices for mORMot and its compression/TLS dependencies when
distributing an application. No libcurl or libarchive implementation is added.
