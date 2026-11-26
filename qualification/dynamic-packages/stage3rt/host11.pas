program host11;

{ Check 2: if host4 crashes on exit because "a temporary AnsiString from a
  WriteLn in main still points at the constant string ('sales-plugin') in
  SalesPkg.fpl's data section and survives until main's epilogue, so that
  after unload FPC_ANSISTR_DECR_REF reads the refcount field of an unmapped
  image", then isolating the plugin code in a separate procedure, so that
  the temporaries are released *before* unload, should make it clean.
  This isolation is the only difference from host4. }

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
    Exit;

  for I := 1 to LTable^.TableCount do
  begin
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

  FreeLibrary(AHandle);
end;

{ Same as host4's main body - except that the temporary AnsiStrings are
  released in this procedure's epilogue (= before unload) }
procedure RunPlugin;
var
  LCls: TPersistentClass;
  LObj: TPluginBase;
begin
  LCls := GetClass('TSalesPlugin');
  WriteLn('GetClass         : ', Assigned(LCls));
  if not Assigned(LCls) then
    Exit;

  LObj := TPluginBase(LCls.Create);
  try
    WriteLn('Describe         : ', LObj.Describe);
    WriteLn('ClassName        : ', LObj.ClassName);
    WriteLn('is TPluginBase   : ', LObj is TPluginBase);
    WriteLn('Parent           : ', LObj.ClassParent.ClassName);
  finally
    LObj.Free;
  end;
end;

var
  GLib: HMODULE;
begin
  GLib := LoadPackage('SalesPkg.fpl');
  WriteLn('LoadPackage      : ', GLib <> 0);
  if GLib = 0 then
  begin
    Halt(1);
  end;

  RunPlugin;

  UnloadPackage(GLib);
  WriteLn('GetClass unloaded: ', Assigned(GetClass('TSalesPlugin')));
  WriteLn('host11 ok');
end.
