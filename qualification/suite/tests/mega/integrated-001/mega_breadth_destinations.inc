{ Managed output storage and stateful indexed RTL containers. }

type
  TBreadthPacketEnvelope = record
    Slot: TBreadthExitPacket;
    Carry: IInterface;
    Base: Int64;
  end;

function BreadthReplacePacket(var Frame: TBreadthPacketEnvelope; out Slot: TBreadthExitPacket;
  Build: Boolean; Delta: Int64): Boolean;
begin
  Check((Frame.Slot.Owner = nil) and (Frame.Slot.Trail = AnsiString('')), 'breadth-out-clears-managed-field-through-other-alias');
  Check(Frame.Carry <> nil, 'breadth-out-does-not-clear-neighbor-interface');
  Result := Build;
  If not Result then
    Exit;
  Slot.Owner := TIntersectionOwner.Create;
  Slot.Value := Frame.Base + Delta;
  Slot.Trail := 'ready';
end;

procedure RunBreadthAliasedOutRecord;
var
  Frame: TBreadthPacketEnvelope;
  Built: Boolean;
begin
  TIntersectionOwner.Destroyed := 0;
  Frame.Base := OpaqueI(24000000073);
  Frame.Carry := TIntersectionOwner.Create;
  Frame.Slot.Owner := TIntersectionOwner.Create;
  Frame.Slot.Trail := 'old';
  Built := BreadthReplacePacket(Frame, Frame.Slot, True, OpaqueI(-9000000051));
  Check(Built and (Frame.Slot.Value = 15000000022) and (Frame.Slot.Trail = AnsiString('ready')),
    'breadth-out-writes-record-through-bound-field');
  Check((Frame.Slot.Owner <> nil) and (TIntersectionOwner.Destroyed = 1), 'breadth-out-replacement-releases-previous-owner');
  Mix(UInt64(Frame.Slot.Value));
  Built := BreadthReplacePacket(Frame, Frame.Slot, False, 0);
  Check(not Built and (Frame.Slot.Owner = nil) and (TIntersectionOwner.Destroyed = 2),
    'breadth-out-early-exit-releases-replacement');
  Check(Frame.Base = 24000000073, 'breadth-out-retains-neighbor-scalar');
  Frame.Carry := nil;
  Check(TIntersectionOwner.Destroyed = 3, 'breadth-out-neighbor-released-separately');
end;

procedure RunBreadthQuotedList;
const
  Expected: array[0..4] of string = ('a', 'b|c', '', 'd"e', ' two words ');
var
  Parts: TStringList;
  Serialized: string;
  Pass, I: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := '|';
    Parts.QuoteChar := '"';
    Serialized := 'a|"b|c"|""|"d""e"| two words ';
    for Pass := 1 to 2 do begin
      Parts.DelimitedText := Serialized;
      Check(Parts.Count = Length(Expected), 'breadth-delimited-count-includes-empty-field');
      for I := Low(Expected) to High(Expected) do
        Check((I < Parts.Count) and (Parts[I] = Expected[I]), 'breadth-delimited-fields-roundtrip');
      Serialized := Parts.DelimitedText;
      Parts.Clear;
    end;
    Mix(UInt64(Length(Expected)));
  finally
    Parts.Free;
  end;
end;

procedure RunBreadthBitVectorResize;
const
  Positions: array[0..7] of Integer = (0, 1, 31, 32, 63, 64, 127, 129);
var
  Bits: TBits;
  Model: array[0..129] of Boolean;
  I, Position, Count: Integer;
begin
  Bits := TBits.Create;
  try
    Bits.Size := Length(Model);
    FillChar(Model, SizeOf(Model), 0);
    for I := Low(Positions) to High(Positions) do begin
      Position := Integer(OpaqueI(Positions[I]));
      Bits[Position] := True;
      Model[Positions[I]] := True;
    end;
    Check(Bits.OpenBit = 2, 'breadth-bits-finds-first-clear-bit');
    for I := Low(Model) to High(Model) do
      Check(Bits[I] = Model[I], 'breadth-bits-index-crosses-word-boundaries');
    Bits.Size := 64;
    Count := 0;
    for I := 0 to Bits.Size - 1 do begin
      Check(Bits[I] = Model[I], 'breadth-bits-shrink-keeps-prefix');
      Inc(Count, Ord(Bits[I]));
    end;
    Check(Count = 5, 'breadth-bits-resized-population');
    Bits.Size := 0;
    Bits.Size := Length(Model);
    Check(Bits.OpenBit = 0, 'breadth-bits-reopened-first-slot-clear');
    for I := Low(Model) to High(Model) do
      Check(not Bits[I], 'breadth-bits-zero-size-releases-previous-bits');
    Mix(UInt64(Count));
  finally
    Bits.Free;
  end;
end;

procedure RunBreadthDestinationForms;
begin
  RunBreadthAliasedOutRecord;
  RunBreadthQuotedList;
  RunBreadthBitVectorResize;
end;
