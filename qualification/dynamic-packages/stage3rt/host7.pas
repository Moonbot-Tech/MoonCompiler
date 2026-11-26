program host7;

{$mode delphi}

uses
  Windows,
  Classes;

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

var
  GLib: HMODULE;
  GTable: PInitFinalTable;
  I: PtrUInt;
  GCls: TPersistentClass;
  GObj: TPersistent;
begin
  GLib := LoadLibrary('PlainPkg.fpl');
  WriteLn('load    : ', GLib <> 0);

  GTable := PInitFinalTable(GetProcAddress(GLib, 'INITFINAL'));
  WriteLn('table   : ', GTable <> nil);

  for I := 1 to GTable^.TableCount do
  begin
    if Assigned(GTable^.Procs[I].InitProc) then
      GTable^.Procs[I].InitProc();
    GTable^.InitCount := I;
  end;
  WriteLn('init ran: ', GTable^.InitCount, ' units');

  { Create/free an instance - the VMT lives in the DLL that will be unloaded }
  GCls := GetClass('TPlainPlugin');
  WriteLn('getclass: ', Assigned(GCls));
  if Assigned(GCls) then
  begin
    GObj := GCls.Create;
    WriteLn('created : ', GObj.ClassName);
    GObj.Free;
    WriteLn('freed   : ok');
  end;

  while GTable^.InitCount > 0 do
  begin
    Dec(GTable^.InitCount);
    if Assigned(GTable^.Procs[GTable^.InitCount + 1].FinalProc) then
      GTable^.Procs[GTable^.InitCount + 1].FinalProc();
  end;
  WriteLn('final   : done');

  WriteLn('free    : ', FreeLibrary(GLib));
  WriteLn('host7 ok');
end.
