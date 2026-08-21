program tunicodeguidparse1;

{$mode delphi}

uses
  SysUtils;

const
  GuidText = '{4D5A0001-1234-ABCD-9876-0000524553FF}';
  GuidTextLower = '{4d5a0001-1234-abcd-9876-0000524553ff}';

var
  Guid,
  RoundTrip: TGUID;
  ShortGuid: ShortString;

procedure CheckGuid(const Value: TGUID; ErrorCode: Integer);
begin
  If (Value.D1<>$4D5A0001) or
    (Value.D2<>$1234) or
    (Value.D3<>$ABCD) or
    (Value.D4[0]<>$98) or
    (Value.D4[1]<>$76) or
    (Value.D4[2]<>$00) or
    (Value.D4[3]<>$00) or
    (Value.D4[4]<>$52) or
    (Value.D4[5]<>$45) or
    (Value.D4[6]<>$53) or
    (Value.D4[7]<>$FF) then
    Halt(ErrorCode);
end;

begin
  If not TryStringToGUID(GuidText,Guid) then
    Halt(1);
  CheckGuid(Guid,2);

  If not TryStringToGUID(GuidTextLower,Guid) then
    Halt(3);
  CheckGuid(Guid,4);

  ShortGuid:=GuidText;
  If not TGUID.FromString(ShortGuid,Guid) then
    Halt(5);
  CheckGuid(Guid,6);

  RoundTrip:=StringToGUID(GUIDToString(Guid));
  If not IsEqualGUID(Guid,RoundTrip) then
    Halt(7);

  If not TryStringToGUID('{00000000-0000-0000-0000-000000000000}',Guid) or
    not Guid.IsEmpty then
    Halt(8);
  If not TryStringToGUID('{FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF}',Guid) then
    Halt(9);

  If TryStringToGUID('4D5A0001-1234-ABCD-9876-0000524553FF',Guid) then
    Halt(10);
  If TryStringToGUID('{4D5A0001_1234-ABCD-9876-0000524553FF}',Guid) then
    Halt(11);
  If TryStringToGUID('{4D5A0001-1234-ABCD-9876-0000524553FG}',Guid) then
    Halt(12);
end.
