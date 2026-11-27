program host14;

{ Regression for the *discrimination* of the second-round notification -
  machine-checked version.

  host13 checks that "entries of an image unmapped as a dependency are
  cleared". This test checks the opposite side: **no over-removal**.

  The TPersistent checks in host12/host13 cannot test this discrimination.
  TPersistent lives in rtlpkg, which is bound at load time via -FPrtlpkg
  and whose reference count can never reach 0 - they only prove "not
  everything is wiped". The discrimination the second round actually
  depends on is this:

    A required package that was loaded dynamically and is *still referenced
    by another loaded package* must stay mapped, and registrations belonging
    to it must survive.

  Setup: RegPkg and Reg2Pkg **both** require BasePkg. The host links only
  rtlpkg, so BasePkg is mapped solely through the imports of these two
  packages (reference count 2).

    unload RegPkg  -> BasePkg refcount 1, stays mapped
                      => TBaseThing **must survive**  (key guard)
    unload Reg2Pkg -> BasePkg refcount 0, unmapped
                      => TBaseThing must disappear

  Everything is machine-checked with Halt(1); nothing passes by merely
  printing values. }

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

var
  GFailed: Boolean = False;

{ Records any mismatch on the spot; Halt(1) at the end. }
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

procedure CallRegisterProcs(AModule: HMODULE);
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

  for I := 1 to LTable^.TableCount do
  begin
    if Assigned(LTable^.Procs[I].Proc) then
    begin
      LTable^.Procs[I].Proc();
    end;
  end;
end;

function IsMapped(const AName: string): Boolean;
begin
  Result := GetModuleHandle(PChar(AName)) <> 0;
end;

var
  GReg: HMODULE;
  GReg2: HMODULE;
begin
  GReg := LoadPackage('RegPkg.fpl');
  GReg2 := LoadPackage('Reg2Pkg.fpl');
  CallRegisterProcs(GReg);
  CallRegisterProcs(GReg2);

  WriteLn('== both loaded, after register ==');
  Expect('BasePkg mapped', IsMapped('BasePkg.fpl'), True);
  Expect('TBaseThing', Assigned(GetClass('TBaseThing')), True);
  Expect('TRegDemo', Assigned(GetClass('TRegDemo')), True);
  Expect('TReg2Demo', Assigned(GetClass('TReg2Demo')), True);

  { Unload only RegPkg. Reg2Pkg still holds BasePkg, so BasePkg is not
    unmapped. If the second round is right to decide on staleness alone,
    TBaseThing must survive. }
  UnloadPackage(GReg);
  WriteLn('== only RegPkg unloaded (Reg2Pkg still references BasePkg) ==');
  Expect('BasePkg mapped', IsMapped('BasePkg.fpl'), True);
  Expect('TRegDemo (owned by RegPkg, must be cleared)', Assigned(GetClass('TRegDemo')), False);
  Expect('TBaseThing (must survive - key guard)', Assigned(GetClass('TBaseThing')), True);
  Expect('TReg2Demo (Reg2Pkg still alive)', Assigned(GetClass('TReg2Demo')), True);

  { Releasing the last referrer unmaps BasePkg as a dependency. Now the
    entry must be cleared - otherwise the next GetClass dies. }
  UnloadPackage(GReg2);
  WriteLn('== Reg2Pkg unloaded too (BasePkg refcount 0) ==');
  Expect('BasePkg mapped', IsMapped('BasePkg.fpl'), False);
  Expect('TReg2Demo (owned by Reg2Pkg, must be cleared)', Assigned(GetClass('TReg2Demo')), False);
  Expect('TBaseThing (dependency unmapped, must be cleared)', Assigned(GetClass('TBaseThing')), False);
  Expect('TPersistent (rtlpkg is pinned)', Assigned(GetClass('TPersistent')), True);

  if GFailed then
  begin
    WriteLn('host14 FAILED');
    Halt(1);
  end;

  WriteLn('host14 ok');
end.
