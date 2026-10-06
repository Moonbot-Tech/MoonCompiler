# Direct Windows SDK bindings: source and modifications

These bindings are distributed under the Mozilla Public License 1.1 option
offered in their original notices. The full license is in `MPL-1.1.txt`.
Individual files retain the original Microsoft, Marcel van Brakel and other
attributions and the original alternative LGPL option. The FPC static-linking
exception must not be assumed for a file which does not grant it.

The original open-source Pascal bindings are retained in this repository under
`packages/winunits-jedi/src`. They are not Embarcadero Delphi RTL source. The
following map identifies every imported source; the product does not depend
on or install those original Jwa units.

| Product source in `src` | Original in `packages/winunits-jedi/src` |
| --- | --- |
| accctrl.pp | jwaaccctrl.pas |
| aclapi.pp | jwaaclapi.pas |
| cpl.pp | jwacpl.pas |
| dlgs.pp | jwadlgs.pas |
| ipexport.pp | jwaipexport.pas |
| iphlpapi.pp | jwaiphlpapi.pas |
| iprtrmib.pp | jwaiprtrmib.pas |
| iptypes.pp | jwaiptypes.pas |
| psapi.pp | jwapsapi.pas |
| qos.pp | jwaqos.pas |
| regstr.pp | jwaregstr.pas |
| tlhelp32.pp | jwatlhelp32.pas |
| userenv.pp | jwauserenv.pas |
| wincred.pp | jwawincred.pas |
| winsafer.pp | jwawinsafer.pas |
| winsvc.pp | jwawinsvc.pas |
| wtsapi32.pp | jwawtsapi32.pas |
| profinfo.pp | jwaprofinfo.pas |
| wbemcli.pp | jwawbemcli.pas |

MoonCompiler modifications, 6 October 2026: use direct SDK unit names and common
Windows/WinSock2/ActiveX types; remove Jwa runtime dependencies and dynamic
loader branches; select ANSI/Unicode declarations with the product profile;
correct native entry-point selection, pointer indirection and Win64 packing;
add public profile aliases and supporting SDK constants. Small SDK macro
translations inherited from the open sources retain their original notices.

`src/winapi.support.pp` is a MoonCompiler support unit: shared native aliases
and the public SDK formulas for converting error codes into HRESULT values.
No proprietary Delphi implementation is incorporated.

The complete original and modified source is publicly available with each
release tag at https://github.com/Moonbot-Tech/MoonCompiler (release 2.3.0:
https://github.com/Moonbot-Tech/MoonCompiler/tree/v2.3.0/packages/winunits-base).
The source includes the notices above and all modifications needed to rebuild
the distributed units. Binary toolchains carry this notice and the MPL text
in `share/doc/mooncompiler`.
