{ Str writes a packed ShortString field according to its declared capacity. }

procedure RunBreadthPackedStr;
var
  Packet: packed record
    Prefix: Byte;
    Text: string[12];
    Tail: UInt64;
  end;
  SignedValue: Int64;
  UnsignedValue: UInt64;
  Width: Integer;
begin
  Packet.Prefix := $B9;
  Packet.Tail := UInt64($F017000000000021);
  SignedValue := OpaqueI(-90000000017);
  Width := Integer(OpaqueI(16));
  Str(SignedValue:Width, Packet.Text);
  Check((Length(Packet.Text) = 12) and (Packet.Text = '    -9000000'), 'breadth-packed-str-truncates-padded-signed-result');

  UnsignedValue := UInt64(OpaqueI(-1));
  Width := Integer(OpaqueI(4));
  Str(UnsignedValue:Width, Packet.Text);
  Check((Length(Packet.Text) = 12) and (Packet.Text = '184467440737'), 'breadth-packed-str-unsigned-64-bit-digits');
  SignedValue := OpaqueI(-51);
  Width := Integer(OpaqueI(6));
  Str(SignedValue:Width, Packet.Text);
  Check((Length(Packet.Text) = 6) and (Packet.Text = '   -51'), 'breadth-packed-str-shorter-write-updates-length-byte');
  Check((Packet.Prefix = $B9) and (Packet.Tail = UInt64($F017000000000021)), 'breadth-packed-str-keeps-neighbor-fields');
  Mix(UInt64(Length(Packet.Text)));
end;
