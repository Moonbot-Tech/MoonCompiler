{ %OPT=-O3 }
program tmooncaptureshadow1;

{$mode delphiunicode}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch inlinevars}

type
  TIntReader = reference to function: Integer;
  TStringReader = reference to function: UnicodeString;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

procedure CaptureSiblingNames(out First, Second: TIntReader);
begin
  begin
    var Value := 17;
    First := function: Integer
      begin
        Result := Value;
      end;
  end;
  begin
    var Value := 29;
    Second := function: Integer
      begin
        Result := Value;
      end;
  end;
end;

procedure CaptureDifferentTypes(out Number: TIntReader; out Text: TStringReader);
begin
  begin
    var Value := 41;
    Number := function: Integer
      begin
        Result := Value;
      end;
  end;
  begin
    var Value := UnicodeString('shadow');
    Text := function: UnicodeString
      begin
        Result := Value;
      end;
  end;
end;

var
  First, Second: TIntReader;
  Text: TStringReader;
begin
  CaptureSiblingNames(First, Second);
  Check((First() = 17) and (Second() = 29), 1);
  First := nil;
  Second := nil;

  CaptureDifferentTypes(First, Text);
  Check((First() = 41) and (Text() = 'shadow'), 2);
  First := nil;
  Text := nil;
end.
