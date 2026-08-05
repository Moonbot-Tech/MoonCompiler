{ %OPT=-O3 -OoAUTOINLINE }
program tautoinline3;

{$mode delphi}

type
  TBigRec = record
    A, B, C, D: Int64;
  end;

var
  GRec: TBigRec;
  OutputFile: Text;
  Value: Int64;

procedure PokeG;
begin
  GRec.B := GRec.B + 5;
end;

function TwoReads(const R: TBigRec): Int64;
begin
  Result := R.B;
  PokeG;
  Result := Result * 1000 + R.B;
end;

begin
  GRec.B := 7;
  Assign(OutputFile, 'tautoinline3.tmp');
  Rewrite(OutputFile);
  WriteLn(OutputFile, TwoReads(GRec));
  Close(OutputFile);
  Reset(OutputFile);
  ReadLn(OutputFile, Value);
  Close(OutputFile);
  Erase(OutputFile);
  if Value <> 7012 then
    Halt(1);
end.
