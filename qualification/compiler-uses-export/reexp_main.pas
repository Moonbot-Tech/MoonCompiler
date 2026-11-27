program reexp_main;

{$mode unleashed}

uses
  ReexpBundle;

var
  A: TReexpA;
  B: TReexpB;
begin
  A.X := 7;
  B := TReexpB.Create;
  { the bundle's own Who wins; the re-exported unit is there by its qualified name }
  WriteLn(Who, ' ', ReexpA.Who, ' ', OnlyA, ' ', A.X, ' ', B.Name);
  B.Free;
end.