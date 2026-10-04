{
    This file is part of the MoonCompiler runtime.
    Copyright (c) 2026 by the MoonCompiler contributors

    The MoonORMot version the runtime units built over mORMot require.

    System.Zip, System.Net.Mime, System.Net.HttpClient and the
    Moon.Diagnostics units compile against the mORMot found on the unit
    path (the mormot directory next to the toolchain, or the project's own).
    They were written and qualified against MoonORMot, whose mormot.core.base
    declares MOONORMOT_VERSION, the number in its moonormot.version.inc.
    Each of those units names this unit in a uses clause, so a build of any
    of them runs the check below:

    - MoonORMot older than MOONORMOT_NEED_VERSION: the build stops with the
      message below; the fix is a git pull in the mormot directory.
    - MoonORMot equal or newer: accepted.  The number is a floor, not a pin.
    - a mORMot without the constant (upstream, or a fork): accepted as it
      is; declared() sees only the units named here, so mormot.core.base is
      in this unit's uses for that purpose alone.

    The number comes from ../moonormot.need.inc, which
    scripts/sync-moonormot.py keeps equal to the version on the tip of
    MoonORMot main together with the qualification pin and the bundled
    memory manager (doc/TESTING.md, "MoonORMot records").

    Author: MoonCompiler team, 2026-09-22.
}
unit MoonORMot.Need;

{$mode delphi}

interface

uses
  mormot.core.base;

const
  { The MoonORMot version this toolchain's runtime units were qualified
    with; MOONORMOT_VERSION of an older MoonORMot fails the build. }
  MOONORMOT_NEED_VERSION = {$I ..\moonormot.need.inc};

{$IF declared(MOONORMOT_VERSION)}
  {$IF MOONORMOT_VERSION < MOONORMOT_NEED_VERSION}
    {$MESSAGE FATAL 'MoonORMot is older than this toolchain requires: run git pull in the mormot directory next to the toolchain (MoonORMot.Need.pas names the version)'}
  {$IFEND}
{$IFEND}

implementation

end.
