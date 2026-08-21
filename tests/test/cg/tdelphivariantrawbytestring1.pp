program tdelphivariantrawbytestring1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef FPC}
  Variants;
{$else}
  System.Variants;
{$endif}

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Value: Variant;
  OleValue: OleVariant;
  Raw: RawByteString;
begin
  Value:='variant raw';
  Raw:=RawByteString(Value);
  Check(Raw='variant raw',1);

  OleValue:='ole raw';
  Raw:=RawByteString(OleValue);
  Check(Raw='ole raw',2);

  Check(AnsiString(Value)='variant raw',3);
  Check(UTF8String(Value)='variant raw',4);
end.
