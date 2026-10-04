unit semantic_targets;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses SysUtils;

type
  TWords = array[0..16] of QWord;
  TPair = array[0..1] of QWord;

function DifferentConstant(Value: QWord): TPair;
function MixedConsumers(Value: QWord): TPair;
function CallsBetween(Value: QWord): TPair;
function BranchBetween(Value: QWord; Choose: Boolean): TPair;
function TryBetween(Value: QWord): TPair;
function NarrowWrites(Value: QWord): TPair;
function Many(Value: QWord): TWords;
function Pressure(A,B,C,D,E,F,G,H: QWord): QWord;
function Checked(Value: QWord): Boolean;
procedure AliasedWrites(var Values: TPair);

implementation

const
  K = QWord($9E3779B185EBCA87);

function Mix(Value: QWord): QWord; inline;
begin
  Result := (Value xor (Value shr 29)) * K;
end;

function DifferentConstant(Value: QWord): TPair;
begin
  Result[0] := (Value xor (Value shr 23)) * QWord($D6E8FEB86659FD93);
  Result[1] := ((Value+1) xor ((Value+1) shr 23)) * QWord($D6E8FEB86659FD93);
end;

function MixedConsumers(Value: QWord): TPair;
begin
  Result[0] := Value * K;
  Result[1] := (Value xor K) + K;
end;

function Opaque(Value: QWord): QWord; noinline;
begin
  Result := Value xor $13579BDF;
end;

function CallsBetween(Value: QWord): TPair;
begin
  Result[0] := Mix(Value);
  Result[1] := Mix(Opaque(Value));
end;

function BranchBetween(Value: QWord; Choose: Boolean): TPair;
begin
  Result[0] := Mix(Value);
  If Choose then
    Result[1] := Mix(Value+1)
  else
    Result[1] := Mix(Value+2);
end;

function TryBetween(Value: QWord): TPair;
begin
  Result[0] := Mix(Value);
  try
    Result[1] := Mix(Value+1);
  finally
    Result[0] := Result[0] xor Value;
  end;
end;

function NarrowWrites(Value: QWord): TPair;
begin
  Result[0] := QWord(Byte(Value)) * K;
  Result[1] := QWord(Word(Value shr 8)) * K;
end;

function Many(Value: QWord): TWords;
begin
  Result[0] := Mix(Value);
  Result[1] := Mix(Value+1);
  Result[2] := Mix(Value+2);
  Result[3] := Mix(Value+3);
  Result[4] := Mix(Value+4);
  Result[5] := Mix(Value+5);
  Result[6] := Mix(Value+6);
  Result[7] := Mix(Value+7);
  Result[8] := Mix(Value+8);
  Result[9] := Mix(Value+9);
  Result[10] := Mix(Value+10);
  Result[11] := Mix(Value+11);
  Result[12] := Mix(Value+12);
  Result[13] := Mix(Value+13);
  Result[14] := Mix(Value+14);
  Result[15] := Mix(Value+15);
  Result[16] := Mix(Value+16);
end;

function Pressure(A,B,C,D,E,F,G,H: QWord): QWord;
var
  P0,P1,P2,P3,P4,P5,P6,P7: QWord;
begin
  P0 := Mix(A);
  P1 := Mix(B);
  P2 := Mix(C);
  P3 := Mix(D);
  P4 := Mix(E);
  P5 := Mix(F);
  P6 := Mix(G);
  P7 := Mix(H);
  Result := P0 xor P1 xor P2 xor P3 xor P4 xor P5 xor P6 xor P7;
end;

procedure AliasedWrites(var Values: TPair);
begin
  Values[0] := Mix(Values[1]);
  Values[1] := Mix(Values[0]);
end;

{$Q+}
function Checked(Value: QWord): Boolean;
var
  A,B: QWord;
begin
  try
    A := Value * K;
    B := (Value+1) * K;
    Result := (A=0) and (B=K);
  except
    on E: EIntOverflow do
      Result := False;
  end;
end;
{$Q-}

end.
