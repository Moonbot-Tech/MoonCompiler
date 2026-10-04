program countdown_semantic;
{$mode delphi}{$Q-}{$R-}
uses SysUtils;
type TSmall=1..20;
var Calls,FinalValue: Integer;

function SubRange(N: TSmall): Integer; noinline;
var I: TSmall;
begin
  Result:=0;
  for I:=1 to N do Inc(Result,I);
end;

function Bound(N: Integer): Integer; noinline;
begin
  Inc(Calls);
  Result:=N;
end;

function Visit(N,Start: Integer): Int64; noinline;
var I,J: Integer;
begin
  Result:=0;
  if Start=0 then
    for I:=0 to Bound(N) do
    begin
      N:=-1;
      if I mod 3=1 then Continue;
      for J:=0 to 2 do
      begin
        if J=1 then Continue;
        Result:=Result+I+J;
      end;
    end
  else
    for I:=1 to Bound(N) do
    begin
      N:=-1;
      if I mod 3=1 then Continue;
      for J:=0 to 2 do
      begin
        if J=1 then Continue;
        Result:=Result+I+J;
      end;
    end;
end;

function ByteRange(N: Byte): Integer; noinline;
var I: Byte;
begin
  Result:=0;
  for I:=0 to N do
    Inc(Result,I);
  FinalValue:=I;
end;

function SignedRange(N: ShortInt): Integer; noinline;
var I: ShortInt;
begin
  Result:=0;
  for I:=0 to N do
    Inc(Result,I);
end;

function WideBreak(N: QWord): QWord; noinline;
var I: QWord;
begin
  Result:=0;
  for I:=0 to N do
  begin
    Inc(Result,I);
    if I=3 then Break;
  end;
end;

function EarlyExit(N: Integer): Integer; noinline;
var I: Integer;
begin
  Result:=0;
  for I:=1 to N do
    try
      Inc(Result,I);
      if I=3 then Exit;
    finally
      FinalValue:=I;
    end;
end;

function Exceptions(N: Integer): Integer; noinline;
var I: Integer;
begin
  Result:=0;
  try
    for I:=0 to N do
      try
        if I=1 then Continue;
        if I=4 then raise Exception.Create('stop');
        Inc(Result,I);
      finally
        Inc(Result,10);
        FinalValue:=I;
      end;
  except
    on E: Exception do Inc(Result,100);
  end;
end;

procedure Change(var I: Integer); noinline;
begin
  I:=4;
end;

function AliasCounter(N: Integer): Integer; noinline;
var I: Integer; P: PInteger;
begin
  Result:=0;
  P:=@I;
  for I:=0 to N do
  begin
    if I=0 then Change(P^);
    Inc(Result,I);
  end;
end;

function CapturedCounter(N: Integer): Integer; noinline;
var I: Integer;
  procedure SetI;
  begin I:=4 end;
begin
  Result:=0;
  for I:=0 to N do
  begin
    if I=0 then SetI;
    Inc(Result,I);
  end;
end;

{$push}{$Q+}{$R+}
function Checked(N: Integer): Integer; noinline;
var I: Integer;
begin
  Result:=0;
  for I:=0 to N do Inc(Result,I);
end;
{$pop}

var N,S,I: Integer; Expected: Int64;
begin
  for N:=-2 to 100 do
    for S:=0 to 1 do
    begin
      Expected:=0;
      for I:=S to N do
        if I mod 3<>1 then Expected:=Expected+I*2+2;
      Calls:=0;
      if Visit(N,S)<>Expected then Halt(1);
      if Calls<>1 then Halt(2);
    end;
  for N:=0 to 255 do
    if ByteRange(N)<>N*(N+1) div 2 then Halt(3);
  if FinalValue<>255 then Halt(4);
  for N:=-128 to 127 do
  begin
    if N<0 then Expected:=0 else Expected:=N*(N+1) div 2;
    if SignedRange(N)<>Expected then Halt(5);
  end;
  if WideBreak(High(QWord))<>6 then Halt(6);
  if WideBreak(2)<>3 then Halt(7);
  if Exceptions(10)<>155 then Halt(8);
  if FinalValue<>4 then Halt(9);
  if AliasCounter(10)<>49 then Halt(10);
  if CapturedCounter(10)<>49 then Halt(11);
  if Checked(10)<>55 then Halt(12);
  if SubRange(20)<>210 then Halt(13);
  if EarlyExit(10)<>6 then Halt(14);
  if FinalValue<>3 then Halt(15);
end.
