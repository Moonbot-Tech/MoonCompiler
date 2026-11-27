program host5;

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes,
  SharedIntf;

{ ── Minimal implementation of Delphi's LoadPackage ──────────────
  A package DLL exports its own initialization table as 'INITFINAL'.
  Walk it to run the initialization sections of the contained units. }
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

function LoadPackage(const AName: string): HMODULE;
var
  LTable: PInitFinalTable;
  I: PtrUInt;
begin
  Result := LoadLibrary(PChar(AName));
  if Result = 0 then
    Exit;

  LTable := PInitFinalTable(GetProcAddress(Result, 'INITFINAL'));
  if LTable = nil then
  begin
    WriteLn('  warning: no INITFINAL export');
    Exit;
  end;

  WriteLn('  initializing ', LTable^.TableCount, ' unit(s)');
  for I := 1 to LTable^.TableCount do
  begin
    if Assigned(LTable^.Procs[I].UnitName) then
      WriteLn('    - ', LTable^.Procs[I].UnitName^);
    if Assigned(LTable^.Procs[I].InitProc) then
      LTable^.Procs[I].InitProc();
    LTable^.InitCount := I;
  end;
end;

procedure UnloadPackage(AHandle: HMODULE);
var
  LTable: PInitFinalTable;
begin
  LTable := PInitFinalTable(GetProcAddress(AHandle, 'INITFINAL'));
  if LTable <> nil then
    while LTable^.InitCount > 0 do
    begin
      Dec(LTable^.InitCount);
      if Assigned(LTable^.Procs[LTable^.InitCount + 1].FinalProc) then
        LTable^.Procs[LTable^.InitCount + 1].FinalProc();
    end;

  { FreeLibrary omitted - to isolate the exit path }
end;

var
  GLib: HMODULE;
  GCls: TPersistentClass;
  GObj: TPluginBase;
begin
  WriteLn('GetClass pre-load: ', Assigned(GetClass('TSalesPlugin')));

  GLib := LoadPackage('SalesPkg.fpl');
  WriteLn('LoadPackage      : ', GLib <> 0);
  if GLib = 0 then
  begin
    WriteLn('  GetLastError = ', GetLastError);
    Halt(1);
  end;

  GCls := GetClass('TSalesPlugin');
  WriteLn('GetClass loaded  : ', Assigned(GCls));
  if not Assigned(GCls) then
  begin
    UnloadPackage(GLib);
    Halt(2);
  end;

  GObj := TPluginBase(GCls.Create);
  try
    WriteLn('Describe         : ', GObj.Describe);
    WriteLn('ClassName        : ', GObj.ClassName);
    WriteLn('is TPluginBase   : ', GObj is TPluginBase);
    WriteLn('Parent           : ', GObj.ClassParent.ClassName);
  finally
    GObj.Free;
  end;

  UnloadPackage(GLib);
  WriteLn('GetClass unloaded: ', Assigned(GetClass('TSalesPlugin')));
  WriteLn('host4 ok');
end.
