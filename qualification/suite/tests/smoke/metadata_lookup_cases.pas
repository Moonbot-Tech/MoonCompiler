unit metadata_lookup_cases;

{$mode delphi}

interface

type
  TClassCase = class
    procedure Execute;
  end;

  TRecordCase = record
    procedure Execute;
  end;

  TGenericCase<T> = class
    procedure Execute;
  end;

procedure NestedCase;
procedure Check(const LabelName, Expected: ShortString; Address: PtrUInt);

implementation

uses SysUtils, lnfodwrf;

procedure Check(const LabelName, Expected: ShortString; Address: PtrUInt);
var
  FuncName, FileName: ShortString;
  LineNumber: LongInt;
begin
  if not GetLineInfo(Address, FuncName, FileName, LineNumber) then
    Halt(20);
  WriteLn(LabelName, '|', FuncName, '|', FileName, '|', LineNumber);
  if (Pos(Expected, FuncName) = 0) or
     (Pos('metadata_lookup_cases.pas', FileName) = 0) or
     (LineNumber <= 0) then
    Halt(21);
end;

procedure TClassCase.Execute;
begin
  try
    raise Exception.Create('class');
  except
    Check('CLASS', 'Execute', PtrUInt(ExceptAddr));
  end;
end;

procedure TRecordCase.Execute;
begin
  try
    raise Exception.Create('record');
  except
    Check('RECORD', 'Execute', PtrUInt(ExceptAddr));
  end;
end;

procedure TGenericCase<T>.Execute;
begin
  try
    raise Exception.Create('generic');
  except
    Check('GENERIC', 'Execute', PtrUInt(ExceptAddr));
  end;
end;

procedure NestedCase;
  procedure Inner;
  begin
    try
      raise Exception.Create('nested');
    except
      Check('NESTED', 'Inner', PtrUInt(ExceptAddr));
    end;
  end;
begin
  Inner;
end;

initialization
  try
    raise Exception.Create('init');
  except
    Check('INIT', '_init', PtrUInt(ExceptAddr));
  end;
finalization
  try
    raise Exception.Create('final');
  except
    WriteLn('FINAL_PC=', HexStr(PtrUInt(ExceptAddr), 16));
  end;
end.
