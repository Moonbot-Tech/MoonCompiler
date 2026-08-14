program delphi_mixed_uint64_pair_ambiguous;

{$mode delphi}

var
  S: Int64;
  U: UInt64;

function PairKind(A,B:Int64):Byte;overload;
begin
  Result:=1;
end;

function PairKind(A,B:UInt64):Byte;overload;
begin
  Result:=2;
end;

begin
  S:=1;
  U:=1;
  Halt(PairKind(S,U));
end.
