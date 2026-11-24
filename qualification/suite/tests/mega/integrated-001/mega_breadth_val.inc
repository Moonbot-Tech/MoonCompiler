{ Val selects the requested ordinal domain and writes into unaligned record destinations. }

procedure RunBreadthPackedVal;
var
  Fields: packed record
    Prefix: Byte;
    UnsignedValue: UInt64;
    Status: Integer;
    SignedValue: Int64;
    NarrowValue: Cardinal;
    Tail: Word;
  end;
  Text: UnicodeString;
begin
  FillChar(Fields, SizeOf(Fields), 0);
  Fields.Prefix := $A6;
  Fields.Tail := $D172;

  Text := UnicodeString(StringOfChar('0', Integer(OpaqueI(253)))) + '7X';
  Val(Text, Fields.UnsignedValue, Fields.Status);
  Check(Fields.Status = 255, 'breadth-packed-val-error-position-at-last-code-unit-of-255-char-input');
  Delete(Text, Length(Text), 1);
  Val(Text, Fields.UnsignedValue, Fields.Status);
  Check((Fields.Status = 0) and (Fields.UnsignedValue = 7), 'breadth-packed-val-valid-long-prefix-within-255');

  Text := '4294967296';
  Val(Text, Fields.NarrowValue, Fields.Status);
  Check((Fields.Status = 0) and (Fields.NarrowValue = 0), 'breadth-packed-val-cardinal-wraps-to-requested-width');
  Val(Text, Fields.UnsignedValue, Fields.Status);
  Check((Fields.Status = 0) and (Fields.UnsignedValue = 4294967296), 'breadth-packed-val-uint64-accepts-same-lexeme');

  Text := '-9223372036854775808';
  Val(Text, Fields.SignedValue, Fields.Status);
  Check((Fields.Status = 0) and (Fields.SignedValue = Low(Int64)), 'breadth-packed-val-signed-minimum-exact');
  Check((Fields.Prefix = $A6) and (Fields.Tail = $D172) and (Fields.UnsignedValue = 4294967296),
    'breadth-packed-val-output-widths-preserve-adjacent-storage');
  Mix(UInt64(Fields.SignedValue) xor Fields.UnsignedValue);
end;
