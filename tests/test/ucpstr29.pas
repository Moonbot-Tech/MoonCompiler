unit ucpstr29;

{$mode delphi}
{$H+}

interface

type
  TAnsi866 = type AnsiString(866);
  TAnsi1251 = type AnsiString(1251);
  TUtf8 = type AnsiString(65001);

procedure FoldInUnit(out S: TAnsi866);
procedure FormatInUnit(out S: TAnsi1251);
procedure LiveInUnit(out S: TUtf8; Value: Integer);
procedure InlineFoldFromPpu(out S: TAnsi866); inline;

implementation

procedure FoldInUnit(out S: TAnsi866);
begin
  Str(456, S);
end;

procedure FormatInUnit(out S: TAnsi1251);
begin
  Str(-123:8, S);
end;

procedure LiveInUnit(out S: TUtf8; Value: Integer);
begin
  Str(Value, S);
end;

procedure InlineFoldFromPpu(out S: TAnsi866);
begin
  Str(321, S);
end;

end.
