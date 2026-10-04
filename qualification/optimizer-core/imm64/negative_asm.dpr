program negative_asm;
{$mode delphi}{$H+}{$Q-}{$R-}{$asmmode intel}
type TPair = array[0..1] of QWord;
const K = QWord($9E3779B185EBCA87);
function AcrossAsm(Value: QWord): TPair; noinline;
begin
  Result[0] := (Value xor (Value shr 29)) * K;
  asm nop end;
  Inc(Value);
  Result[1] := (Value xor (Value shr 29)) * K;
end;
var I: Integer; Value: QWord; P: TPair;
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
    P := AcrossAsm(Value);
    WriteLn(Value,',',P[0],',',P[1]);
  end;
end.
