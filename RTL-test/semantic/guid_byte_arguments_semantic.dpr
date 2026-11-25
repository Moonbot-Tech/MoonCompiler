program guid_byte_arguments_semantic;
{$ifdef FPC}{$mode delphiunicode}{$endif}
{$apptype console}
uses SysUtils, Types;

procedure Check(Value: Boolean; const Detail: string);
begin
  if not Value then begin WriteLn('FAIL ',Detail); Halt(1) end;
end;

procedure CheckSlice(Size: Integer; Start: Cardinal; Accept: Boolean);
var Bytes: TBytes; Id: TGUID; Bad: Boolean; I: Integer;
begin
  SetLength(Bytes,Size);
  for I:=0 to High(Bytes) do Bytes[I]:=I;
  Bad:=False;
  try
    Id:=TGUID.Create(Bytes,Start,TEndian.Big);
    if Accept then Check(Id.D4[7]=Start+15,'last byte at offset');
  except on E: EArgumentException do Bad:=True end;
  Check(Bad<>Accept,'indexed GUID byte count');
end;

procedure CheckTail(Size: Integer; Accept: Boolean);
var Bytes: TBytes; Id: TGUID; Bad: Boolean;
begin
  SetLength(Bytes,Size);
  Bad:=False;
  try
    Id:=TGUID.Create(1,2,3,Bytes);
    if Accept then Check(Id.D1=1,'structured GUID');
  except on E: EArgumentException do Bad:=True end;
  Check(Bad<>Accept,'eight-byte GUID tail');
end;

begin
  CheckSlice(0,0,False);
  CheckSlice(15,0,False);
  CheckSlice(16,0,True);
  CheckSlice(17,1,True);
  CheckSlice(17,2,False);
{$ifdef FPC}  CheckSlice(17,High(Cardinal),False); {$endif}
  CheckTail(7,False);
  CheckTail(8,True);
  CheckTail(9,False);
  WriteLn('GUID_BYTE_ARGUMENTS_PASS');
end.
