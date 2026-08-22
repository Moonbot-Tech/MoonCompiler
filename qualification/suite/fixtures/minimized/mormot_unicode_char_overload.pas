program mormot_unicode_char_overload;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

procedure Prepend(var Value: RawByteString; const Prefix: RawByteString); overload;
begin
  Value := 'string:' + Prefix + Value;
end;

procedure Prepend(var Value: RawByteString; Prefix: AnsiChar); overload;
begin
  Value := 'char:' + RawByteString(Prefix) + Value;
end;

function BuildResult: RawByteString;
begin
  Result := 'payload';
  Prepend(Result, #0);
end;

var
  Value: RawByteString;
begin
  Value := BuildResult;
  if (Length(Value) <> 13) or
     (Copy(Value, 1, 5) <> 'char:') or
     (Value[6] <> #0) or
     (Copy(Value, 7, MaxInt) <> 'payload') then
    Halt(1);
  WriteLn('PASS mormot-unicode-char-overload');
end.
