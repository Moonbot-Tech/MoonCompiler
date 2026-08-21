program tdelphiconstref1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

type
  TPayload = record
    Number: Integer;
    Text: UnicodeString;
  end;

var
  Payload: TPayload;
  ExpectedAddress: Pointer;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

procedure AfterConst(const [ref] Value: TPayload);
begin
  Check(@Value = ExpectedAddress, 1);
  Check((Value.Number = 42) and (Value.Text = 'managed'), 2);
end;

procedure BeforeConst([ref] const Value: TPayload);
begin
  Check(@Value = ExpectedAddress, 3);
  Check((Value.Number = 42) and (Value.Text = 'managed'), 4);
end;

{$ifdef FPC}
procedure NativeConstRef(constref Value: TPayload);
begin
  Check(@Value = ExpectedAddress, 5);
  Check((Value.Number = 42) and (Value.Text = 'managed'), 6);
end;
{$endif}

begin
  Payload.Number := 42;
  Payload.Text := 'managed';
  ExpectedAddress := @Payload;
  AfterConst(Payload);
  BeforeConst(Payload);
{$ifdef FPC}
  NativeConstRef(Payload);
{$endif}
end.
