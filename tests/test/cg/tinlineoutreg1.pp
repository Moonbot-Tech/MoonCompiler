program tinlineoutreg1;

{$mode delphiunicode}

uses
  SysUtils;

var
  Escaped: PInteger;

procedure NextOut(I: Integer; out A,B: Integer); inline;
begin
  A:=I+1;
  B:=I+2;
end;

procedure NextVar(I: Integer; var A,B: Integer); inline;
begin
  A:=I+1;
  B:=I+2;
end;

procedure SetText(out Value: UnicodeString); inline;
begin
  Value:='managed';
end;

procedure SaveAddress(var Value: Integer); noinline;
begin
  Escaped:=@Value;
end;

procedure EscapeAddress(var Value: Integer); inline;
begin
  SaveAddress(Value);
end;

function TestOut(N: Integer): QWord; noinline;
var
  A,B,I: Integer;
begin
  Result:=0;
  for I:=1 to N do
    begin
      NextOut(I,A,B);
      Result:=Result+UInt32(A xor B);
    end;
end;

function TestVar(N: Integer): QWord; noinline;
var
  A,B,I: Integer;
begin
  A:=0;
  B:=0;
  Result:=0;
  for I:=1 to N do
    begin
      NextVar(I,A,B);
      Result:=Result+UInt32(A xor B);
    end;
end;

procedure Fail(const Name: string);
begin
  WriteLn('FAIL ',Name);
  Halt(1);
end;

procedure CheckSemantics;
var
  A: Integer;
  S: UnicodeString;
begin
  A:=0;
  NextOut(5,A,A);
  if A<>7 then
    Fail('aliased-out');
  NextVar(8,A,A);
  if A<>10 then
    Fail('aliased-var');
  SetText(S);
  if S<>'managed' then
    Fail('managed-out');
  A:=41;
  EscapeAddress(A);
  Inc(Escaped^);
  if A<>42 then
    Fail('real-address-escape');
  if TestOut(1000)<>TestVar(1000) then
    Fail('out-var-result');
end;

begin
  CheckSemantics;
  WriteLn('INLINE_OUT_REG_OK');
end.
