{ Lifetime and data movement at boundaries between code generation and RTL. }

type
  TBreadthOwnedError = class(Exception)
  public
    Owner: IInterface;
    Number: Integer;
    class var Destroyed: Integer;
    destructor Destroy; override;
  end;

destructor TBreadthOwnedError.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

procedure RunBreadthAcquireException;
var
  First, Saved, Other, SavedInner: TBreadthOwnedError;
begin
  TIntersectionOwner.Destroyed := 0;
  TBreadthOwnedError.Destroyed := 0;
  First := TBreadthOwnedError.Create('retained error');
  First.Owner := TIntersectionOwner.Create;
  First.Number := Integer(OpaqueI(-113));
  try
    raise First;
  except
    on Current: TBreadthOwnedError do
    begin
      Saved := TBreadthOwnedError(AcquireExceptionObject);
      Check(Saved = Current, 'breadth-acquire-original-object');
      try
        Other := TBreadthOwnedError.Create('nested error');
        Other.Number := Integer(OpaqueI(37));
        raise Other;
      except
        on Inner: TBreadthOwnedError do
        begin
          SavedInner := TBreadthOwnedError(AcquireExceptionObject);
          Check(SavedInner = Inner, 'breadth-acquire-nested-object');
        end;
      end;
      Check(TBreadthOwnedError.Destroyed = 0, 'breadth-acquire-inner-survives-handler');
    end;
  end;
  Check((Saved <> nil) and (SavedInner <> nil) and (TBreadthOwnedError.Destroyed = 0),
    'breadth-acquire-both-survive-handler');
  If (Saved <> nil) and (SavedInner <> nil) and (TBreadthOwnedError.Destroyed = 0) then begin
    Check(SavedInner.Number = 37, 'breadth-acquire-retains-inner-payload');
    Check((Saved.Number = -113) and (Saved.Owner <> nil), 'breadth-acquire-still-owns-payload');
    SavedInner.Free;
    Check(TIntersectionOwner.Destroyed = 0, 'breadth-acquire-owned-member-alive');
    Saved.Free;
  end;
  Check((TBreadthOwnedError.Destroyed = 2) and (TIntersectionOwner.Destroyed = 1), 'breadth-acquire-explicit-cleanup');
  Mix(UInt64(TBreadthOwnedError.Destroyed));
end;

type
  {$M+}
  TBreadthRttiBinding = class
  protected
    FValue: IInterface;
    function Current: IInterface; virtual;
    procedure Bind(const AValue: IInterface); virtual;
    function IsBound: Boolean;
  published
    property BoundValue: IInterface read Current write Bind stored IsBound;
  end;
  {$M-}

  TBreadthRttiOverride = class(TBreadthRttiBinding)
  public
    Calls: Integer;
    Block: Boolean;
    procedure Bind(const AValue: IInterface); override;
  end;

function TBreadthRttiBinding.Current: IInterface;
begin
  Result := FValue;
end;

procedure TBreadthRttiBinding.Bind(const AValue: IInterface);
begin
  FValue := AValue;
end;

function TBreadthRttiBinding.IsBound: Boolean;
begin
  Result := FValue <> nil;
end;

procedure TBreadthRttiOverride.Bind(const AValue: IInterface);
begin
  Inc(Calls);
  If Block then
    raise EAbort.Create('reflected setter');
  inherited Bind(AValue);
end;

procedure BreadthReflectInterfaceBody;
var
  Target: TBreadthRttiOverride;
  Info: PPropInfo;
  Owner: IInterface;
  Caught: Boolean;
begin
  Target := TBreadthRttiOverride.Create;
  try
    Info := GetPropInfo(Target, 'BoundValue');
    Check(Info <> nil, 'breadth-rtti-inherited-interface-property');
    If Info = nil then
      Exit;
    Check(not IsStoredProp(Target, Info), 'breadth-rtti-stored-empty');
    Owner := TIntersectionOwner.Create;
    SetInterfaceProp(Target, Info, Owner);
    Check(IsStoredProp(Target, Info), 'breadth-rtti-stored-after-set');
    Check(GetInterfaceProp(Target, Info) = Owner, 'breadth-rtti-interface-identity');

    Target.Block := True;
    Caught := False;
    try
      SetInterfaceProp(Target, Info, nil);
    except
      on EAbort do Caught := True;
    end;
    Check(Caught and (Target.Calls = 2), 'breadth-rtti-dispatches-throwing-override');
    Check(IsStoredProp(Target, Info) and (GetInterfaceProp(Target, Info) = Owner), 'breadth-rtti-throw-preserves-property');
    Target.Block := False;
    SetInterfaceProp(Target, Info, nil);
    Check((Target.Calls = 3) and (GetInterfaceProp(Target, Info) = nil), 'breadth-rtti-clear-routes-through-override');
    Check(not IsStoredProp(Target, Info), 'breadth-rtti-cleared-stored');
  finally
    Target.Free;
  end;
end;

procedure RunBreadthReflectInterface;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthReflectInterfaceBody;
  Check(TIntersectionOwner.Destroyed = 1, 'breadth-rtti-no-temporary-owner-leak');
  Mix(UInt64(TIntersectionOwner.Destroyed));
end;

type
  TBreadthMoveBuffer = array[0..79] of Byte;

procedure BreadthMoveOverlap(var Data: TBreadthMoveBuffer; Mode: Integer);
begin
  case Mode of
    0: Move(Data[12], Data[13], 15);
    1: Move(Data[13], Data[12], 16);
    2: Move(Data[7], Data[12], 17);
    3: Move(Data[16], Data[8], 31);
    4: Move(Data[2], Data[9], 32);
    5: Move(Data[14], Data[10], 33);
  else
    Move(Data[3], Data[11], OpaqueI(57));
  end;
end;

procedure RunBreadthMoveOverlap;
const
  Sources: array[0..6] of Integer = (12, 13, 7, 16, 2, 14, 3);
  Destinations: array[0..6] of Integer = (13, 12, 12, 8, 9, 10, 11);
  Lengths: array[0..6] of Integer = (15, 16, 17, 31, 32, 33, 57);
var
  Data: TBreadthMoveBuffer;
  I, ActualIndex, Mode: Integer;
  AllValid: Boolean;
begin
  for Mode := Low(Sources) to High(Sources) do
  begin
    for I := Low(Data) to High(Data) do
      Data[I] := Byte(7 + I * 3);
    BreadthMoveOverlap(Data, Integer(OpaqueI(Mode)));
    AllValid := True;
    for I := Low(Data) to High(Data) do
    begin
      ActualIndex := I;
      If (I >= Destinations[Mode]) and (I < Destinations[Mode] + Lengths[Mode]) then
        ActualIndex := I - Destinations[Mode] + Sources[Mode];
      AllValid := AllValid and (Data[I] = 7 + ActualIndex * 3);
    end;
    Check(AllValid, 'breadth-move-overlap-snapshot-and-guards');
    Mix(Data[Destinations[Mode] + Lengths[Mode] - 1]);
  end;
end;

type
  TBreadthGrid = array of TCrossEntries;

procedure RunBreadthRectangularResize;
var
  Grid: TBreadthGrid;
  OldRow: TCrossEntries;
  I, J, Height, Width: Integer;
begin
  SetLength(Grid, 2, 2);
  Grid[0, 0].Code := Integer(OpaqueI(101));
  Grid[0, 1].Code := Integer(OpaqueI(-713));
  Grid[1, 0].Code := Integer(OpaqueI(19));
  Grid[1, 1].Code := Integer(OpaqueI(53));
  Grid[1, 1].Text := AnsiString('old row');
  OldRow := Grid[1];
  Height := Integer(OpaqueI(3));
  Width := Integer(OpaqueI(4));
  SetLength(Grid, Height, Width);
  Check(Length(Grid) = 3, 'breadth-grid-resize-outer');
  for I := Low(Grid) to High(Grid) do
    Check(Length(Grid[I]) = 4, 'breadth-grid-resize-inner');
  Check((Grid[0, 0].Code = 101) and (Grid[0, 1].Code = -713) and (Grid[1, 0].Code = 19)
    and (Grid[1, 1].Code = 53), 'breadth-grid-copied-corner');
  for I := Low(Grid) to High(Grid) do
    for J := Low(Grid[I]) to High(Grid[I]) do
      If (I >= 2) or (J >= 2) then
        Check((Grid[I, J].Code = 0) and (Grid[I, J].Text = AnsiString('')), 'breadth-grid-initializes-new-cells');
  Grid[1, 1].Text := AnsiString('new row');
  Check((Length(OldRow) = 2) and (OldRow[1].Text = AnsiString('old row')), 'breadth-grid-detaches-shared-inner-row');
  Mix(UInt64(Grid[1, 1].Code));
end;

type
  TBreadthSparseStream = class(TStream)
  private
    FStart, FPosition: Int64;
  public
    constructor Create(Start: Int64);
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  TBreadthBinaryHeader = packed record
    MessageType: Word;
    Sequence: UInt64;
    Flags: Byte;
  end;

const
  BreadthStreamPayload: array[0..12] of Byte = ($B3, $E1, $EF, $BE, $88, $77, $66, $55, $44, $33, $22, $11, $E7);

constructor TBreadthSparseStream.Create(Start: Int64);
begin
  inherited Create;
  FStart := Start;
  FPosition := Start;
end;

function TBreadthSparseStream.Read(var Buffer; Count: LongInt): LongInt;
var
  Index: Int64;
begin
  Index := FPosition - FStart;
  If (Index < 0) or (Index >= Length(BreadthStreamPayload)) or (Count <= 0) then
    Exit(0);
  Result := Length(BreadthStreamPayload) - Integer(Index);
  If Count < Result then
    Result := Count;
  Move(BreadthStreamPayload[Index], Buffer, Result);
  Inc(FPosition, Result);
end;

function TBreadthSparseStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  raise EWriteError.Create('read-only payload');
end;

function TBreadthSparseStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent: Inc(FPosition, Offset);
    soEnd: FPosition := FStart + Length(BreadthStreamPayload) + Offset;
  end;
  Result := FPosition;
end;

procedure RunBreadthSparseStreamABI;
const
  Base = Int64($123400000000);
var
  Source: TStream;
  Header: TBreadthBinaryHeader;
  Marker: Byte;
  Missing: LongInt;
  ShortRead: Boolean;
begin
  Source := TBreadthSparseStream.Create(OpaqueI(Base));
  try
    Source.Position := OpaqueI(Base + 2);
    Source.ReadBuffer(Header, SizeOf(Header));
    Check((Header.MessageType = $BEEF) and (Header.Sequence = UInt64($1122334455667788)) and (Header.Flags = $E7),
      'breadth-stream-virtual-read-packed-header');
    Check(Source.Position = Base + 13, 'breadth-stream-position-retains-upper-bits-after-read');
    Check(Source.Seek(-1, soEnd) = Base + 12, 'breadth-stream-seek-from-high-end');
    ShortRead := False;
    try
      Source.ReadBuffer(Missing, SizeOf(Missing));
    except
      on EReadError do ShortRead := True;
    end;
    Check(ShortRead and (Source.Position = Base + 13), 'breadth-stream-readbuffer-partial-progress');
    Source.Seek(-13, soCurrent);
    Source.ReadBuffer(Marker, SizeOf(Marker));
    Check((Marker = $B3) and (Source.Position = Base + 1), 'breadth-stream-resumes-after-short-read');
    Mix(Header.Sequence xor UInt64(Source.Position));
  finally
    Source.Free;
  end;
end;

procedure RunBreadthUtf8Lengths;
const
  PrefixLengths: array[0..5] of Integer = (13, 14, 15, 16, 17, 31);
  Bytes: array[0..10] of Byte = ($F0, $9D, $84, $9E, $C3, $A9, 0, $E2, $82, $AC, $5A);
var
  Raw, Returned: RawByteString;
  WithNul, UntilNul: UnicodeString;
  N, I, CaseIndex: Integer;
begin
  for CaseIndex := Low(PrefixLengths) to High(PrefixLengths) do
  begin
    N := Integer(OpaqueI(PrefixLengths[CaseIndex]));
    SetLength(Raw, N + Length(Bytes));
    for I := 1 to N do
      Raw[I] := 'q';
    Move(Bytes[0], Raw[N + 1], SizeOf(Bytes));
    WithNul := UTF8ToString(Raw);
    UntilNul := UTF8ToString(PAnsiChar(Raw));
    Check((Length(WithNul) = N + 6) and (Length(UntilNul) = N + 3), 'breadth-utf8-length-aware-vs-pointer-overload');
    Check((Ord(WithNul[N + 1]) = $D834) and (Ord(WithNul[N + 2]) = $DD1E)
      and (Ord(WithNul[N + 3]) = $E9), 'breadth-utf8-surrogate-crosses-ascii-boundary');
    Check((WithNul[N + 4] = #0) and (Ord(WithNul[N + 5]) = $20AC) and (WithNul[N + 6] = 'Z'),
      'breadth-utf8-len-overload-decodes-past-zero');
    Check(UntilNul = Copy(WithNul, 1, N + 3), 'breadth-utf8-pointer-stops-at-zero');
    Returned := UTF8Encode(WithNul);
    Check((Length(Returned) = Length(Raw)) and CompareMem(Pointer(Returned), Pointer(Raw), Length(Raw)),
      'breadth-utf8-roundtrip-exact-bytes');
    Mix(UInt64(Length(WithNul) * 100 + Length(UntilNul)));
  end;
end;

type
  TBreadthShortField = string[7];
  TBreadthShortPacket = packed record
    Head: Byte;
    Text: TBreadthShortField;
    Tail: UInt64;
  end;

procedure BreadthAssignShortField(var Target: TBreadthShortField; const Source: UnicodeString);
begin
  Target := ShortString(Source);
end;

procedure RunBreadthShortStringCapacity;
const
  TailGuard = UInt64($D72916C85201A3BE);
var
  Packet: TBreadthShortPacket;
  Source, RoundTrip: UnicodeString;
  N: Integer;
begin
  Packet.Head := $B1;
  Packet.Tail := TailGuard;
  Source := UnicodeString('AB'#0'CDEFGHI');
  BreadthAssignShortField(Packet.Text, Source);
  Check((Length(Packet.Text) = 7) and (Packet.Text[3] = #0) and (Packet.Text[7] = 'F'),
    'breadth-shortstring-narrow-field-truncation-and-nul');
  Check((Packet.Head = $B1) and (Packet.Tail = TailGuard), 'breadth-shortstring-capacity-neighbor-guards');
  N := Integer(OpaqueI(5));
  SetLength(Packet.Text, N);
  Packet.Text[N] := '@';
  RoundTrip := UnicodeString(Packet.Text);
  Check(RoundTrip = UnicodeString('AB'#0'C@'), 'breadth-shortstring-shrink-and-embedded-nul-roundtrip');
  Check((Length(Source) = 10) and (Source[10] = 'I'), 'breadth-shortstring-conversion-leaves-source-intact');
  BreadthAssignShortField(Packet.Text, 'Z');
  Check((Length(Packet.Text) = 1) and (Packet.Text[1] = 'Z') and (Packet.Tail = TailGuard),
    'breadth-shortstring-packed-reassign');
  Mix(UInt64(Length(RoundTrip) * 10 + Length(Packet.Text)));
end;

procedure RunBreadthRuntimeForms;
begin
  RunBreadthAcquireException;
  RunBreadthReflectInterface;
  RunBreadthMoveOverlap;
  RunBreadthRectangularResize;
  RunBreadthSparseStreamABI;
  RunBreadthUtf8Lengths;
  RunBreadthShortStringCapacity;
end;
