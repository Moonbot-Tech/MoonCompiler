{$ifdef BREADTH_HAS_EXTENDED_METHODS}
{ Reflection retains all index arguments and the managed value across the
  indirect call, including the argument passed beyond the register slots. }

type
  {$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublic]) FIELDS([vcPublic])}
  TBreadthRttiIndexedText = class
  public
    LastBank: Byte;
    LastTicket: Int64;
    LastPath, Text: UnicodeString;
    Reads, Writes: Integer;
    function Fetch(Bank: Byte; Ticket: Int64; const Path: UnicodeString): UnicodeString;
    procedure Store(Bank: Byte; Ticket: Int64; const Path, Value: UnicodeString);
    property Entries[Bank: Byte; Ticket: Int64; const Path: UnicodeString]: UnicodeString read Fetch write Store;
  end;
  {$RTTI INHERIT}

function TBreadthRttiIndexedText.Fetch(Bank: Byte; Ticket: Int64; const Path: UnicodeString): UnicodeString;
begin
  Inc(Reads);
  LastBank := Bank;
  LastTicket := Ticket;
  LastPath := Path;
  Result := Path + '=' + Text;
end;

procedure TBreadthRttiIndexedText.Store(Bank: Byte; Ticket: Int64; const Path, Value: UnicodeString);
begin
  Inc(Writes);
  LastBank := Bank;
  LastTicket := Ticket;
  LastPath := Path;
  Text := Value;
end;

procedure RunBreadthIndexedRtti;
type
  TFetch = function(Bank: Byte; Ticket: Int64; const Path: UnicodeString): UnicodeString of object;
var
  Context: TRttiContext;
  Indexed: TRttiIndexedProperty;
  Getter: TRttiMethod;
  Book: TBreadthRttiIndexedText;
  Link: TMethod;
  Fetch: TFetch;
  Value: UnicodeString;
begin
  Context := TRttiContext.Create;
  try
    Indexed := Context.GetType(TBreadthRttiIndexedText).GetIndexedProperty('Entries');
    Check((Indexed <> nil) and Indexed.IsReadable and Indexed.IsWritable,
      'breadth-rtti-indexed-property-discovered-with-both-accessors');
    If Indexed = nil then
      Exit;
    Check(Indexed.PropertyType.Handle = TypeInfo(UnicodeString),
      'breadth-rtti-indexed-property-reports-original-value-type');
    Getter := Indexed.ReadMethod;
    Check((Getter <> nil) and (Getter.CodeAddress <> nil), 'breadth-rtti-indexed-property-exposes-live-getter');
    If (Getter = nil) or (Getter.CodeAddress = nil) then
      Exit;
    Book := TBreadthRttiIndexedText.Create;
    try
      Book.Entries[19, OpaqueI(571000000003), 'peer'] := 'text' + #0 + #$03BB;
      Check((Book.Writes = 1) and (Book.LastBank = 19) and (Book.LastTicket = 571000000003)
        and (Book.LastPath = 'peer') and (Book.Text = 'text' + #0 + #$03BB),
        'breadth-rtti-indexed-property-direct-write-initializes-original-value');
      Link.Code := Getter.CodeAddress;
      Link.Data := Book;
      Fetch := TFetch(Link);
      Value := Fetch(Byte(OpaqueI(233)), OpaqueI(-93000000061), 'root');
      Check((Book.Reads = 1) and (Book.LastBank = 233) and (Book.LastTicket = -93000000061)
        and (Book.LastPath = 'root') and (Value = 'root=text' + #0 + #$03BB),
        'breadth-rtti-indexed-property-delivers-wide-managed-return-with-correct-receiver');
      Mix(UInt64(Length(Value)));
    finally
      Book.Free;
    end;
  finally
    Context.Free;
  end;
end;
{$endif}
