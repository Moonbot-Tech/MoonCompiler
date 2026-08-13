program generic_return_mismatch_rejected;

{$mode delphi}
{$modeswitch implicitgenerics}

uses
  Generics.Collections;

type
  TPairAlias = TPair<Integer, Int64>;

function MismatchedResult: TPairAlias; forward;

function MismatchedResult: TPair<Integer, Integer>;
begin
  Result:=Default(TPair<Integer, Integer>);
end;

begin
end.
