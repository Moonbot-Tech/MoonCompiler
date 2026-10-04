program abi_imm64_semantic;

{$mode delphi}{$H+}{$Q-}{$R-}

uses pulse_abi_targets, semantic_targets;

var
  Value: QWord;
  I,J: Integer;
  R16: TRec16;
  R24: TRec24;
  R32: TRec32;
  Pair: TPair;
  Words: TWords;

procedure EmitPair(const Name: ShortString; const Pair: TPair);
begin
  WriteLn(Name,',',Value,',',Pair[0],',',Pair[1]);
end;

begin
  Value := 0;
  for I := 0 to 259 do begin
    case I of
      0: Value := 0;
      1: Value := High(QWord);
      2: Value := QWord(1) shl 63;
      3: Value := (QWord(1) shl 32)-1;
      else Value := Value * QWord($5851F42D4C957F2D) + 1442695040888963407;
    end;
    R16 := ReturnRecord16(Value);
    R24 := ReturnRecord24(Value);
    R32 := ReturnRecord32(Value);
    WriteLn('return16,',Value,',',R16.A,',',R16.B);
    WriteLn('return24,',Value,',',R24.A,',',R24.B,',',R24.C);
    WriteLn('return32,',Value,',',R32.A,',',R32.B,',',R32.C,',',R32.D);
    EmitPair('different',DifferentConstant(Value));
    EmitPair('mixed',MixedConsumers(Value));
    EmitPair('call',CallsBetween(Value));
    EmitPair('branch0',BranchBetween(Value,False));
    EmitPair('branch1',BranchBetween(Value,True));
    EmitPair('try',TryBetween(Value));
    EmitPair('narrow',NarrowWrites(Value));
    Words := Many(Value);
    Write('many,',Value);
    for J := 0 to High(Words) do
      Write(',',Words[J]);
    WriteLn;
    WriteLn('pressure,',Value,',',Pressure(Value,Value+1,Value+2,Value+3,Value+4,Value+5,Value+6,Value+7));
    Pair[0] := Value;
    Pair[1] := Value+1;
    AliasedWrites(Pair);
    EmitPair('alias',Pair);
    WriteLn('checked,',Value,',',Ord(Checked(Value)));
  end;
end.
