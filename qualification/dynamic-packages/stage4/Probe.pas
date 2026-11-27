program Probe;

{$mode delphi}

uses
  SysUtils,
  Windows;

type
  TProcedure = procedure;

  TRegProcRec = record
    Proc: TProcedure;
    UnitName: ^ShortString;
  end;

  PRegProcTable = ^TRegProcTable;
  TRegProcTable = record
    TableCount: PtrUInt;
    Procs: array[1..1024] of TRegProcRec;
  end;

var
  GLib: HMODULE;
  GPtr: ^LongWord;
  GTable: PRegProcTable;
  I: PtrUInt;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: Probe <package.fpl>');
    Halt(2);
  end;

  GLib := LoadLibrary(PChar(ParamStr(1)));
  if GLib = 0 then
  begin
    WriteLn('load failed: ', GetLastError);
    Halt(1);
  end;

  GPtr := GetProcAddress(GLib, 'PACKAGEFLAGS');
  if GPtr = nil then
  begin
    WriteLn('PACKAGEFLAGS missing');
    Halt(1);
  end;

  WriteLn('image base = ', IntToHex(PtrUInt(GLib), 16));
  WriteLn('PACKAGEFLAGS = ', GPtr^);

  { "No export at all" and "export present with TableCount 0" are different
    results. The former means the package is RUNONLY and cannot be installed;
    the latter means it is installable but has no units to register. The two
    cases are printed distinctly. }
  GTable := PRegProcTable(GetProcAddress(GLib, 'REGPROCS'));
  if GTable = nil then
  begin
    WriteLn('REGPROCS missing (no export at all)');
  end
  else
  begin
    WriteLn('REGPROCS present, TableCount = ', GTable^.TableCount);
    WriteLn('REGPROCS: ', GTable^.TableCount, ' unit(s)');
    for I := 1 to GTable^.TableCount do
    begin
      { Proc is the record's first field, so the record's address is the
        field's address. In delphi mode `@procvar` yields the variable's
        value (the code address), not its address, hence this workaround.
        The value should lie within the DLL image's address range. }
      WriteLn('  - ', GTable^.Procs[I].UnitName^,
              '  proc=', IntToHex(PPtrUInt(@GTable^.Procs[I])^, 16));
    end;
  end;
end.
