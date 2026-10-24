program metadata_lookup_main;

{$mode delphi}

uses SysUtils, lnfodwrf, metadata_lookup_cases;

type
  TCallback = reference to procedure;

var
  C: TClassCase;
  R: TRecordCase;
  G: TGenericCase<Integer>;
  F: TCallback;
  FuncName, FileName: ShortString;
  LineNumber: LongInt;
begin
  C := TClassCase.Create;
  G := TGenericCase<Integer>.Create;
  try
    C.Execute;
    R.Execute;
    G.Execute;
    NestedCase;
    F := procedure
      begin
        try
          raise Exception.Create('anonymous');
        except
          if not GetLineInfo(PtrUInt(ExceptAddr), FuncName, FileName, LineNumber) then
            Halt(22);
          WriteLn('ANONYMOUS|', FuncName, '|', FileName, '|', LineNumber);
          if (Pos('metadata_lookup_main.pas', FileName) = 0) or (LineNumber <= 0) then
            Halt(23);
        end;
      end;
    F();
  finally
    G.Free;
    C.Free;
  end;
  WriteLn('LOOKUP_PASS');
end.
