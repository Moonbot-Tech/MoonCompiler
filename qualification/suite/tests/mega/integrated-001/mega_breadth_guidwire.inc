{ Read one network-order ID from a frame and independently emit a different ID in both byte orders. }

procedure RunBreadthGuidByteWindow;
const
  NetworkOrder: array[0..15] of Byte =
    ($87, $65, $43, $21, $81, $23, $4F, $ED, $B2, $01, $70, $A9, $B8, 0, $13, $7E);
  LittleOrder: array[0..15] of Byte =
    ($21, $43, $65, $87, $23, $81, $ED, $4F, $B2, $01, $70, $A9, $B8, 0, $13, $7E);
var
  Frame, NetworkBytes, LittleBytes: TBytes;
  Incoming, Outgoing: TGUID;
begin
  Frame := [$D8, $19, $FA, $C0, $DE, $74, $56, $31, $40, $82, $AB, $99, $FF, $08, $11, 0, $69, $5C, $FE];
  Incoming := TGUID.Create(Frame, Cardinal(OpaqueI(2)), TEndian.Big);
  Check((Incoming.D1 = Cardinal($FAC0DE74)) and (Incoming.D2 = $5631) and (Incoming.D3 = $4082)
    and (Incoming.D4[0] = $AB) and (Incoming.D4[7] = $5C), 'breadth-guid-read-nonzero-network-window-keeps-all-field-widths');
  Check(GUIDToString(Incoming) = '{FAC0DE74-5631-4082-AB99-FF081100695C}',
    'breadth-guid-read-wire-value-has-expected-text-identity');
  Outgoing := TGUID.Create('{87654321-8123-4FED-B201-70A9B800137E}');
  NetworkBytes := Outgoing.ToByteArray(TEndian.Big);
  LittleBytes := Outgoing.ToByteArray(TEndian.Little);
  Check((Length(NetworkBytes) = 16) and CompareMem(@NetworkBytes[0], @NetworkOrder[0], SizeOf(NetworkOrder)),
    'breadth-guid-write-exact-big-endian-wire-value');
  Check((Length(LittleBytes) = 16) and CompareMem(@LittleBytes[0], @LittleOrder[0], SizeOf(LittleOrder)),
    'breadth-guid-write-exact-little-endian-wire-value');
  Mix(UInt64(Incoming.D1) shl 32 or UInt64(Outgoing.D1));
end;
