unit provider;
{$mode delphi}{$INLINE ON}
interface
function ReadValue: LongInt; inline;
implementation
type
  TFill = array[0..1] of array[0..1] of Byte;
var
  Filler: TFill;
type
  TPayload = record
    Value: LongInt;
  end;
var
  Payload: TPayload;

function ReadValue: LongInt;
begin
  Result:=Payload.Value;
end;

initialization
  FillChar(Filler,SizeOf(Filler),0);
  Payload.Value:=23;
end.
