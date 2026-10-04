{ %OPT=-O3 -OoAUTOINLINE -Fu../packages/rtl-objpas/src/inc }
program tmoonconstresult1;
{$mode delphiunicode}{$inline on}
uses SysUtils, Variants, umoonconstresult1;
var OldCopy: procedure(var Dest: TVarData; const Source: TVarData);
    Copies, FailAt, Caught: Integer;
procedure CountCopy(var Dest: TVarData; const Source: TVarData);
begin
  Inc(Copies);
  if (FailAt<>0) and (Copies=FailAt) then raise Exception.Create('copy');
  OldCopy(Dest,Source);
end;
function Calc(const V: Variant): Variant;
begin
  Result:=V*3+7;
end;
procedure CheckVariant;
var V: Variant;
    I: Integer;
begin
  for I:=0 to 15 do
  begin
    V:=I;
    V:=Calc(V);
    if Integer(V)<>I*3+7 then Halt(3);
  end;
end;
procedure FailCopy;
var V: Variant;
begin
  V:=11;
  try
    V:=Calc(V);
    Halt(4);
  except
    on E: Exception do
      if E.Message='copy' then Inc(Caught) else raise;
  end;
end;
var I: Integer;
    Total: Int64;
begin
  Total:=0;
  for I:=1 to 32 do
    Inc(Total,Nested(I));
  if Total<>6624 then Halt(1);
  if Pair(Triple(7),Triple(8))<>51 then Halt(2);
  OldCopy:=VarCopyProc;
  VarCopyProc:=@CountCopy;
  try
    CheckVariant;
    WriteLn('copies=',Copies);
    FailAt:=Copies+2;
    FailCopy;
    if Caught<>1 then Halt(5);
  finally
    VarCopyProc:=OldCopy;
  end;
  WriteLn('const result ok');
end.
