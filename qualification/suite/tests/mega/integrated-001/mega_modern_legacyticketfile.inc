{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A typed Delphi file uses record positions, even for an older packed disk layout. }

type
  TBreadthLegacyTicket = packed record
    Ticket: UInt32;
    Quantity: SmallInt;
    Venue: Byte;
  end;

procedure RunBreadthLegacyTicketFile;
const
  Existing: array[0..13] of Byte = ($04, $03, $02, $01, $6B, $FE, 3, $67, $45, $23, $F1, $A8, $61, 2);
  Expected: array[0..20] of Byte = (
    $44, $33, $22, $81, $E2, $04, 9, $67, $45, $23, $F1, $A8, $61, 2, $21, $43, $65, $F7, $E3, $FF, 5);
var
  Tickets: file of TBreadthLegacyTicket;
  Row: TBreadthLegacyTicket;
  Path: string;
  Wire: TFileStream;
  Data: TBytes;
  PreviousMode: Byte;
begin
  Path := TPath.GetTempFileName;
  PreviousMode := FileMode;
  try
    Wire := TFileStream.Create(Path, fmCreate);
    try
      Wire.WriteBuffer(Existing, SizeOf(Existing));
    finally
      Wire.Free;
    end;

    AssignFile(Tickets, Path);
    FileMode := fmOpenReadWrite;
    Reset(Tickets);
    try
      Check((SizeOf(Row) = 7) and (FileSize(Tickets) = 2), 'breadth-ticket-file-counts-packed-rows');
      Seek(Tickets, Integer(OpaqueI(1)));
      Read(Tickets, Row);
      Check((Row.Ticket = $F1234567) and (Row.Quantity = 25000) and (Row.Venue = 2)
        and (FilePos(Tickets) = 2) and Eof(Tickets), 'breadth-ticket-file-seeks-to-existing-row-in-record-units');

      Seek(Tickets, 0);
      Row.Ticket := $81223344;
      Row.Quantity := 1250;
      Row.Venue := 9;
      Write(Tickets, Row);
      Seek(Tickets, FileSize(Tickets));
      Row.Ticket := $F7654321;
      Row.Quantity := -29;
      Row.Venue := 5;
      Write(Tickets, Row);
      Check((FilePos(Tickets) = 3) and (FileSize(Tickets) = 3), 'breadth-ticket-file-appends-after-random-update');
    finally
      CloseFile(Tickets);
    end;

    Data := TFile.ReadAllBytes(Path);
    Check((Length(Data) = SizeOf(Expected)) and CompareMem(Pointer(Data), @Expected[0], SizeOf(Expected)),
      'breadth-ticket-file-exports-exact-legacy-bytes-with-neighbor-intact');
    Mix(UInt64(Length(Data)));
  finally
    FileMode := PreviousMode;
    TFile.Delete(Path);
  end;
end;
{$endif}
