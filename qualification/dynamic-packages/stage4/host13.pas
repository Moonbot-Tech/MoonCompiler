program host13;

{ Regression: dangling registrations left in ClassList when a dependency
  package is unloaded together with the package that requires it.

  RegPkg requires BasePkg, and TRegDemo = class(TBaseThing).
  RegisterClass registers the whole ancestor chain, so RegPkg's single
  Register also puts TBaseThing, which belongs to BasePkg, into ClassList.

  The host links only rtlpkg (-FPrtlpkg). BasePkg is mapped solely through
  RegPkg's PE imports, so when FreeLibrary(RegPkg) drops its reference count
  to 0 it is unmapped *without a module-unload notification of its own*.

  At notification time BasePkg is still mapped and committed, so neither the
  ownership check nor the staleness check catches it. Before the fix, the
  TBaseThing entry was therefore left pointing into an unmapped image, and
  the next GetClass walk raised an access violation as soon as it read that
  VMT.

  RegPkg has two contained units with a Register procedure (RegUnit,
  RegUnit2); BaseRegUnit belongs to a required package and must be left
  out. So TableCount itself is machine-checked too - if values were only
  printed, a walk that handles just one entry, or one that wrongly includes
  BaseRegUnit, would pass silently. The TBaseThing expectation is also met
  through ancestor-chain registration, so it alone cannot catch the latter.
  TRegDemo2 is checked separately - only that class reveals whether the
  second entry was actually called.

  Expected (after the fix):
    REGPROCS entries              = 2
    after load     BasePkg mapped = TRUE
    after register TRegDemo2      = TRUE
    after register TBaseThing     = TRUE
    after unload   BasePkg mapped = FALSE  (unmapped along as a dependency)
    after unload   TBaseThing     = FALSE  (removed by the second-round staleness sweep)
    after unload   TPersistent    = TRUE   (no over-removal for live images)
    exit 0

  Before the fix, output stops at "about to call GetClass" and the program
  dies with an access violation.

  Everything is machine-checked with Halt(1) - if values were only printed,
  over-removal would pass silently. Note, however, that TPersistent here
  belongs to rtlpkg, which is bound at load time, so this only proves "not
  everything is wiped". The real discrimination (live dependencies must
  remain) is checked by host14. }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes;

type
  TRegisterProc = procedure;

  TRegProcRec = record
    Proc: TRegisterProc;
    UnitName: ^ShortString;
  end;

  PRegProcTable = ^TRegProcTable;
  TRegProcTable = record
    TableCount: PtrUInt;
    Procs: array[1..1024] of TRegProcRec;
  end;

{ Walks the design-time registration table and calls the Register procedure
  of every contained unit - a minimal imitation of what the IDE does. Returns
  the number of entries called so the caller can check the table size too. }
function CallRegisterProcs(AModule: HMODULE): PtrUInt;
var
  LTable: PRegProcTable;
  I: PtrUInt;
begin
  LTable := PRegProcTable(GetProcAddress(AModule, 'REGPROCS'));
  if LTable = nil then
  begin
    WriteLn('REGPROCS missing - not a design-time package');
    Halt(1);
  end;

  WriteLn('REGPROCS TableCount: ', LTable^.TableCount);
  for I := 1 to LTable^.TableCount do
  begin
    if Assigned(LTable^.Procs[I].Proc) then
    begin
      LTable^.Procs[I].Proc();
    end;
  end;

  Result := LTable^.TableCount;
end;

function IsMapped(const AName: string): Boolean;
begin
  Result := GetModuleHandle(PChar(AName)) <> 0;
end;

var
  GFailed: Boolean = False;

{ Records any mismatch with the expectation; Halt(1) at the end. }
procedure Expect(const AWhat: string; AActual, AExpected: Boolean);
const
  NAMES: array[Boolean] of string = ('FALSE', 'TRUE');
begin
  if AActual = AExpected then
  begin
    WriteLn('  [OK]   ', AWhat, ' = ', NAMES[AActual]);
  end
  else
  begin
    WriteLn('  [FAIL] ', AWhat, ' = ', NAMES[AActual], ' (expected ', NAMES[AExpected], ')');
    GFailed := True;
  end;
end;

var
  GLib: HMODULE;
  GCount: PtrUInt;
begin
  Expect('BasePkg mapped before load', IsMapped('BasePkg.fpl'), False);

  { LoadPackage raises EPackageError on failure. Returning at all means
    success, so comparing the handle with 0 is always true - check instead
    that the dependency package was mapped along with it. }
  GLib := LoadPackage('RegPkg.fpl');
  Expect('BasePkg mapped after load (mapped as dependency)', IsMapped('BasePkg.fpl'), True);

  GCount := CallRegisterProcs(GLib);
  { Only RegUnit + RegUnit2. BaseRegUnit belongs to a required package
    (BasePkg) and must not be in RegPkg's table - 3 means the skip rule is
    broken, 1 means the multi-entry walk is broken. }
  Expect('REGPROCS has 2 entries (RegUnit, RegUnit2)', GCount = 2, True);

  Expect('TRegDemo after register', Assigned(GetClass('TRegDemo')), True);
  { Was the second entry actually called? TRegDemo2 is registered only by
    RegUnit2.Register and is not pulled in by any ancestor chain. }
  Expect('TRegDemo2 after register (second entry)', Assigned(GetClass('TRegDemo2')), True);
  Expect('TBaseThing after register (ancestor-chain registration)', Assigned(GetClass('TBaseThing')), True);

  UnloadPackage(GLib);
  Expect('BasePkg mapped after unload (unmapped without notification)', IsMapped('BasePkg.fpl'), False);

  { The problem zone starts here. Before the fix, the GetClass below
    reads a VMT in an unmapped image and dies. }
  WriteLn('about to call GetClass');
  Expect('TBaseThing after unload', Assigned(GetClass('TBaseThing')), False);
  Expect('TRegDemo after unload', Assigned(GetClass('TRegDemo')), False);
  Expect('TPersistent after unload (no over-removal)', Assigned(GetClass('TPersistent')), True);

  if GFailed then
  begin
    WriteLn('host13 FAILED');
    Halt(1);
  end;

  WriteLn('host13 ok');
end.
