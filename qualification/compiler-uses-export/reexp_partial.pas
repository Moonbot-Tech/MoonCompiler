program reexp_partial;

{$mode unleashed}

uses
  ReexpPartial;

var
  B: TReexpB;
begin
  B := TReexpB.Create;
  WriteLn(B.Name);
  B.Free;
end.