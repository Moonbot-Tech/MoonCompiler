program host10;

{ Check 1: if host8 crashes because "CommonPkg is loaded only as a
  dependency of SalesPkg and is unmapped along with FreeLibrary(SalesPkg)",
  then pinning CommonPkg beforehand should make walking GetClass after
  FreeLibrary (including the leftover TPluginBase entry) safe. }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes,
  SharedIntf;

type
  TProcedure = procedure;
  TInitFinalRec = record
    InitProc: TProcedure;
    FinalProc: TProcedure;
    UnitName: ^ShortString;
  end;
  PInitFinalTable = ^TInitFinalTable;
  TInitFinalTable = record
    TableCount: PtrUInt;
    InitCount: PtrUInt;
    Procs: array[1..1024] of TInitFinalRec;
  end;

procedure Probe(const AName: string);
var
  LCls: TPersistentClass;
begin
  LCls := GetClass(AName);
  if LCls = nil then
    WriteLn(Format('    %-16s (none)', [AName]))
  else
    WriteLn(Format('    %-16s vmt=%p', [AName, Pointer(LCls)]));
end;

var
  GPin: HMODULE;
  GLib: HMODULE;
  GTable: PInitFinalTable;
  I: PtrUInt;
begin
  { Pin CommonPkg explicitly so that FreeLibrary(SalesPkg) cannot unmap it }
  GPin := LoadLibrary('CommonPkg.fpl');
  WriteLn('CommonPkg pinned : ', GPin <> 0);

  GLib := LoadLibrary('SalesPkg.fpl');
  GTable := PInitFinalTable(GetProcAddress(GLib, 'INITFINAL'));
  for I := 1 to GTable^.TableCount do
  begin
    if Assigned(GTable^.Procs[I].InitProc) then
      GTable^.Procs[I].InitProc();
    GTable^.InitCount := I;
  end;

  while GTable^.InitCount > 0 do
  begin
    Dec(GTable^.InitCount);
    if Assigned(GTable^.Procs[GTable^.InitCount + 1].FinalProc) then
      GTable^.Procs[GTable^.InitCount + 1].FinalProc();
  end;

  FreeLibrary(GLib);

  WriteLn('== after FreeLibrary (CommonPkg still pinned) ==');
  Probe('TSalesPlugin');
  Probe('TPluginBase');
  Probe('TPersistent');

  WriteLn('host10 ok');
end.
