{ Decode one unaligned packed header, then emit an independently populated header into a bounded byte window. }

type
  TBreadthWireQuote = packed record
    Venue: Word;
    Ticket: UInt64;
    Price: Single;
    Kind: Byte;
  end;

procedure RunBreadthBitConverterWindow;
const
  Expected: array[0..14] of Byte = ($71, $CA, $E0, $CD, $AB, $89, $67, $45, $23, $81, 0, 0, $20, $3F, $91);
var
  Input, Output: TBytes;
  Received, Produced: TBreadthWireQuote;
  Offset: Integer;
begin
  Input := [$18, 0, $73, $35, $8A, $10, $32, $54, $76, $98, $BA, $DC, $FE, 0, 0, $50, $C0, $4F, $FE];
  Offset := Integer(OpaqueI(3));
  Received := TBitConverter.InTo<TBreadthWireQuote>(Input, Offset);
  Check((Received.Venue = $8A35) and (Received.Ticket = UInt64($FEDCBA9876543210))
    and (Received.Price = -3.25) and (Received.Kind = $4F), 'breadth-bitconverter-decodes-packed-fields-at-unaligned-offset');

  Produced.Venue := $CA71;
  Produced.Ticket := UInt64(OpaqueI(Int64($8123456789ABCDE0)));
  Produced.Price := 0.625;
  Produced.Kind := $91;
  SetLength(Output, 20);
  FillChar(Output[0], Length(Output), $D7);
  TBitConverter.From<TBreadthWireQuote>(Produced, Output, Offset);
  Check(CompareMem(@Output[3], @Expected[0], SizeOf(Expected)), 'breadth-bitconverter-encodes-independent-packed-fields');
  Check((Length(Output) = 20) and (Output[0] = $D7) and (Output[1] = $D7) and (Output[2] = $D7)
    and (Output[18] = $D7) and (Output[19] = $D7), 'breadth-bitconverter-keeps-bytes-outside-destination-window');
  Mix(Received.Ticket xor Produced.Ticket);
end;
