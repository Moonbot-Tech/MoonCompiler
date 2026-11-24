{ Positional formatting consumes width and precision before its selected floating argument. }

function BreadthPositionalFormat(const Settings: TFormatSettings; const Args: array of const; Reject: Boolean): string;
begin
  If Reject then
    Result := Format('%5:d', Args, Settings)
  else
    Result := Format('%2:*.*f|%0:s|%1:d', Args, Settings);
end;

procedure RunBreadthPositionalFormat;
const
  Expected = '    12,75|A'#0'B|-70000000013';
var
  Settings: TFormatSettings;
  Text, Pending: string;
  Caught: Boolean;
begin
  Settings := Default(TFormatSettings);
  Settings.DecimalSeparator := ',';
  Text := BreadthPositionalFormat(Settings, [UnicodeString('A'#0'B'), OpaqueI(-70000000013),
    Integer(OpaqueI(9)), Integer(OpaqueI(2)), OpaqueD(12.75)], False);
  Check((Length(Text) = 26) and (Text = Expected), 'breadth-positional-format-selects-width-precision-and-wide-arguments');
  Caught := False;
  try
    Pending := BreadthPositionalFormat(Settings, [UnicodeString('unused'), OpaqueI(-70000000013),
      Integer(OpaqueI(9)), Integer(OpaqueI(2)), OpaqueD(12.75)], True);
    Text := Pending;
  except
    on EConvertError do Caught := True;
  end;
  Check(Caught, 'breadth-positional-format-rejects-out-of-range-argument-index');
  Check(Text = Expected, 'breadth-positional-format-preserves-prior-result-on-rejection');
  Mix(UInt64(Length(Text)));
end;
