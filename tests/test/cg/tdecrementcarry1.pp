program tdecrementcarry1;
{$mode delphi}{$Q-}{$R-}
uses SysUtils;

function Check8(X: Byte): Integer; noinline;
begin
  Dec(X);
  if X=High(Byte) then Result:=1 else Result:=2;
end;
function Check16(X: Word): Integer; noinline;
begin
  Dec(X);
  if X<>High(Word) then Result:=2 else Result:=1;
end;
function Check32(X: Cardinal): Integer; noinline;
begin
  Dec(X);
  if X=High(Cardinal) then Result:=1 else Result:=2;
end;
function Check64(X: QWord): Integer; noinline;
begin
  Dec(X);
  if X<>High(QWord) then Result:=2 else Result:=1;
end;
function CheckSigned(X: Int64): Integer; noinline;
begin
  Dec(X);
  if X=-1 then Result:=1 else Result:=2;
end;
function MoreFlags(X: Cardinal): Integer; noinline;
begin
  Dec(X);
  if X=High(Cardinal) then Result:=1
  else if X<High(Cardinal) then Result:=2
  else Result:=3;
end;
{$push}{$Q+}
function Checked(X: Int64): Integer; noinline;
begin
  Dec(X);
  if X=-1 then Result:=1 else Result:=2;
end;
{$pop}
var X: Cardinal; E: Integer; V: array[0..7] of QWord; I: Integer;
begin
  for X:=0 to 65535 do
  begin
    if X=0 then E:=1 else E:=2;
    if Check16(X)<>E then Halt(1);
    if Check32(X)<>E then Halt(2);
    if Check64(X)<>E then Halt(3);
    if CheckSigned(X)<>E then Halt(4);
    if MoreFlags(X)<>E then Halt(5);
    if Checked(X)<>E then Halt(6);
    if X<256 then
      if Check8(X)<>E then Halt(7);
  end;
  V[0]:=0; V[1]:=1; V[2]:=High(Cardinal); V[3]:=QWord(1) shl 32;
  V[4]:=QWord(1) shl 63; V[5]:=High(Int64); V[6]:=High(QWord)-1; V[7]:=High(QWord);
  for I:=0 to High(V) do
  begin
    if V[I]=0 then E:=1 else E:=2;
    if Check64(V[I])<>E then Halt(8);
    if CheckSigned(Int64(V[I]))<>E then Halt(9);
  end;
  try
    Checked(Low(Int64));
    Halt(10);
  except
    on E: EIntOverflow do ;
  end;
end.
