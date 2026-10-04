unit umoonconstresult1;
{$mode delphiunicode}{$inline on}
interface
uses SysUtils;
type
  TTriple = record A, B, C: Int64; end;
  TFixed = array[0..3] of Int64;
function Triple(V: Int64): TTriple; inline;
function Fixed(V: Int64): TFixed; inline;
function Sum(const V: TTriple): Int64; inline;
function Pair(const A, B: TTriple): Int64; inline;
function SumFixed(const V: TFixed): Int64; inline;
function Nested(V: Int64): Int64; inline;
implementation
function Triple(V: Int64): TTriple;
begin
  Result.A:=V;
  Result.B:=V+1;
  Result.C:=V+2;
end;
function Fixed(V: Int64): TFixed;
begin
  Result[0]:=V;
  Result[1]:=V+1;
  Result[2]:=V+2;
  Result[3]:=V+3;
end;
function Sum(const V: TTriple): Int64;
var Scratch: TTriple;
begin
  Scratch:=Triple(100);
  Result:=V.A+V.B+V.C+Scratch.A-100;
end;
function Pair(const A, B: TTriple): Int64;
begin
  Result:=Sum(A)+Sum(B);
end;
function SumFixed(const V: TFixed): Int64;
begin
  Result:=V[0]+V[1]+V[2]+V[3];
end;
function Nested(V: Int64): Int64;
begin
  Result:=Pair(Triple(V),Triple(V+10))+SumFixed(Fixed(V));
end;
end.
