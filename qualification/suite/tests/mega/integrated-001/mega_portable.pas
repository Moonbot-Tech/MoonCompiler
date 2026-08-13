unit mega_portable;

{$ifdef FPC}
  {$mode delphi}{$H+}{$codepage utf8}
{$endif}

interface

uses
  SysUtils, Classes;

type
  EPortableFailure = class(Exception);

  TPortableResult = record
    Checks: Int64;
    Digest: UInt64;
  end;

procedure RunPortableScenario(Seed: UInt64; WorkerId, Phase: Integer;
  out ScenarioResult: TPortableResult);
procedure FoldPortableResult(var Digest: UInt64;
  const ScenarioResult: TPortableResult; WorkerId, Phase: Integer);

implementation

const
  MaxCells = 64;
  MaxBufferSize = 4096;
  HashOffset = UInt64($CBF29CE484222325);
  HashPrime = UInt64($100000001B3);

type
  IPortableValue = interface
    ['{97314072-4B4F-43E7-BC47-038CE31ACEC9}']
    function GetValue: Int64;
    function GetTag: RawByteString;
  end;

  TPortableValue = class(TInterfacedObject, IPortableValue)
  private
    FValue: Int64;
    FTag: RawByteString;
  public
    constructor Create(AValue: Int64; const ATag: RawByteString);
    function GetValue: Int64;
    function GetTag: RawByteString;
  end;

  TInt64Array = array of Int64;

  TPortableCell = record
    Id: LongInt;
    Version: LongInt;
    RawText: RawByteString;
    WideText: UnicodeString;
    Bytes: TBytes;
    Numbers: TInt64Array;
    Ref: IPortableValue;
    Stamp: UInt64;
  end;

  TPortableCellArray = array of TPortableCell;

  TByteSpan = array[0..MaxBufferSize - 1] of Byte;
  PByteSpan = ^TByteSpan;

constructor TPortableValue.Create(AValue: Int64; const ATag: RawByteString);
begin
  inherited Create;
  FValue := AValue;
  FTag := ATag;
end;

function TPortableValue.GetValue: Int64;
begin
  Result := FValue;
end;

function TPortableValue.GetTag: RawByteString;
begin
  Result := FTag;
end;

{$ifdef FPC}
  {$push}
{$else}
  {$ifopt Q+}{$define RESTORE_OVERFLOW_CHECKS}{$endif}
{$endif}
{$Q-}
function NextRandom(var State: UInt64): UInt64;
begin
  State := State xor (State shr 12);
  State := State xor (State shl 25);
  State := State xor (State shr 27);
  Result := State * UInt64($2545F4914F6CDD1D);
end;

procedure Mix(var Digest: UInt64; Value: UInt64);
begin
  Digest := (Digest xor Value) * HashPrime;
end;

function InitialState(Seed: UInt64; WorkerId, Phase: Integer): UInt64;
begin
  Result := Seed xor (UInt64(WorkerId + 1) * UInt64($9E3779B97F4A7C15)) xor
    (UInt64(Phase + 1) * UInt64($D1B54A32D192ED03));
  if Result = 0 then
    Result := UInt64($A0761D6478BD642F) xor UInt64(WorkerId + Phase + 1);
end;
{$ifdef FPC}
  {$pop}
{$else}
  {$ifdef RESTORE_OVERFLOW_CHECKS}{$Q+}{$undef RESTORE_OVERFLOW_CHECKS}{$endif}
{$endif}

function RandomLongInt(var State: UInt64): LongInt;
var
  Bits: LongWord;
begin
  Bits := LongWord(NextRandom(State) and UInt64($FFFFFFFF));
  Move(Bits, Result, SizeOf(Result));
end;

function LongWordBits(Value: LongInt): LongWord;
begin
  Move(Value, Result, SizeOf(Result));
end;

function Int64Bits(Value: Int64): UInt64;
begin
  Move(Value, Result, SizeOf(Result));
end;

procedure PortableCheck(Condition: Boolean; const Name: RawByteString;
  var ScenarioResult: TPortableResult);
begin
  Inc(ScenarioResult.Checks);
  if not Condition then
    raise EPortableFailure.Create(String(Name));
end;

function BoundarySize(var State: UInt64; Limit: Integer): Integer;
const
  Boundaries: array[0..17] of Integer =
    (0, 1, 2, 3, 7, 8, 15, 16, 17, 31, 32, 63, 64, 127, 128, 255, 256, 257);
var
  Candidate: Integer;
begin
  if (NextRandom(State) and 3) <> 0 then
    Candidate := Boundaries[Integer(NextRandom(State) mod
      UInt64(Length(Boundaries)))]
  else
    Candidate := Integer(NextRandom(State) mod UInt64(Limit + 1));
  if Candidate > Limit then
    Candidate := Limit;
  Result := Candidate;
end;

procedure BuildCell(var Cell: TPortableCell; Id, Version, PayloadSize: Integer);
var
  I: Integer;
  Tag: RawByteString;
begin
  Cell.Id := Id;
  Cell.Version := Version;
  Cell.RawText := RawByteString(Format('%d/%d/', [Id, Version])) +
    RawByteString(#$C3#$A9);
  Cell.WideText := UnicodeString(Format('cell:%d:%d:', [Id, Version])) +
    UnicodeString(WideChar($03BB));
  SetLength(Cell.Bytes, PayloadSize);
  for I := 0 to High(Cell.Bytes) do
    Cell.Bytes[I] := Byte((Int64(Id) * 17 + Int64(Version) * 31 + I * 13) and $FF);
  SetLength(Cell.Numbers, (PayloadSize mod 11) + 1);
  for I := 0 to High(Cell.Numbers) do
    Cell.Numbers[I] := Int64(Id) * 1000003 + Int64(Version) * 97 - I * 29;
  Tag := RawByteString(IntToStr(Version)) + ':' + RawByteString(IntToStr(Id));
  Cell.Ref := TPortableValue.Create(Int64(Id) * 65537 + Version, Tag);
  Cell.Stamp := (UInt64(LongWordBits(Id)) shl 32) or
    UInt64(LongWordBits(Version));
end;

procedure CheckCell(const Cell: TPortableCell; Id, Version: Integer;
  var ScenarioResult: TPortableResult; var Digest: UInt64);
var
  I, FirstSlash, SecondSlash, ParsedId, ParsedVersion: Integer;
  Prefix, VersionText: RawByteString;
begin
  PortableCheck(Cell.Id = Id, 'cell-id', ScenarioResult);
  PortableCheck(Cell.Version = Version, 'cell-version', ScenarioResult);
  FirstSlash := Pos('/', String(Cell.RawText));
  SecondSlash := Pos('/', String(Copy(Cell.RawText, FirstSlash + 1, MaxInt)));
  PortableCheck((FirstSlash > 1) and (SecondSlash > 1), 'cell-raw-separators',
    ScenarioResult);
  Prefix := Copy(Cell.RawText, 1, FirstSlash - 1);
  VersionText := Copy(Cell.RawText, FirstSlash + 1, SecondSlash - 1);
  ParsedId := StrToInt(String(Prefix));
  ParsedVersion := StrToInt(String(VersionText));
  PortableCheck(ParsedId = Id, 'cell-raw-id', ScenarioResult);
  PortableCheck(ParsedVersion = Version, 'cell-raw-version', ScenarioResult);
  PortableCheck(Copy(Cell.RawText, Length(Cell.RawText) - 1, 2) =
    RawByteString(#$C3#$A9), 'cell-raw-utf8-tail', ScenarioResult);
  PortableCheck(Cell.WideText = UnicodeString('cell:') +
    UnicodeString(IntToStr(Id)) + ':' + UnicodeString(IntToStr(Version)) + ':' +
    UnicodeString(WideChar($03BB)), 'cell-wide-text', ScenarioResult);
  for I := 0 to High(Cell.Bytes) do
  begin
    PortableCheck(Cell.Bytes[I] = Byte((Int64(Id) * 17 +
      Int64(Version) * 31 + I * 13) and $FF), 'cell-byte', ScenarioResult);
    Mix(Digest, UInt64(Cell.Bytes[I]) + (UInt64(I) shl 8));
  end;
  PortableCheck(Length(Cell.Numbers) = (Length(Cell.Bytes) mod 11) + 1,
    'cell-number-count', ScenarioResult);
  for I := 0 to High(Cell.Numbers) do
  begin
    PortableCheck(Cell.Numbers[I] = Int64(Id) * 1000003 +
      Int64(Version) * 97 - I * 29, 'cell-number', ScenarioResult);
    Mix(Digest, Int64Bits(Cell.Numbers[I]));
  end;
  PortableCheck(Assigned(Cell.Ref), 'cell-interface', ScenarioResult);
  PortableCheck(Cell.Ref.GetValue = Int64(Id) * 65537 + Version,
    'cell-interface-value', ScenarioResult);
  PortableCheck(Cell.Ref.GetTag = RawByteString(IntToStr(Version)) + ':' +
    RawByteString(IntToStr(Id)), 'cell-interface-tag', ScenarioResult);
  PortableCheck(Cell.Stamp = ((UInt64(LongWordBits(Id)) shl 32) or
    UInt64(LongWordBits(Version))), 'cell-stamp', ScenarioResult);
  Mix(Digest, Cell.Stamp);
  Mix(Digest, Length(Cell.RawText));
  Mix(Digest, Length(Cell.WideText));
end;

procedure CheckCells(const Cells: TPortableCellArray;
  const ModelIds, ModelVersions, ModelSizes: array of Integer; Count: Integer;
  var ScenarioResult: TPortableResult; var Digest: UInt64);
var
  I: Integer;
begin
  PortableCheck(Length(Cells) = Count, 'cell-count', ScenarioResult);
  for I := 0 to Count - 1 do
  begin
    PortableCheck(Length(Cells[I].Bytes) = ModelSizes[I], 'cell-size',
      ScenarioResult);
    CheckCell(Cells[I], ModelIds[I], ModelVersions[I], ScenarioResult, Digest);
  end;
end;

procedure FillBlock(Block: Pointer; Id, Version, Size: Integer);
var
  I: Integer;
begin
  for I := 0 to Size - 1 do
    PByteSpan(Block)^[I] := Byte((Int64(Id) * 43 +
      Int64(Version) * 71 + I * 19) and $FF);
end;

procedure CheckBlock(Block: Pointer; Id, Version, Size: Integer;
  var ScenarioResult: TPortableResult; var Digest: UInt64);
var
  I: Integer;
begin
  PortableCheck(Assigned(Block), 'heap-block-assigned', ScenarioResult);
  for I := 0 to Size - 1 do
  begin
    PortableCheck(PByteSpan(Block)^[I] = Byte((Int64(Id) * 43 +
      Int64(Version) * 71 + I * 19) and $FF), 'heap-block-byte',
      ScenarioResult);
    Mix(Digest, UInt64(PByteSpan(Block)^[I]) + (UInt64(I) shl 8));
  end;
end;

procedure RunHeapStateMachine(var State: UInt64;
  var ScenarioResult: TPortableResult; var Digest: UInt64);
const
  MaxBlocks = 32;
  MaxBlockSize = 1024;
var
  Blocks: array[0..MaxBlocks - 1] of Pointer;
  ModelIds, ModelVersions, ModelSizes: array[0..MaxBlocks - 1] of Integer;
  Count, I, J, Op, Position, NewSize, PreservedSize: Integer;
begin
  Count := 0;
  for I := 0 to High(Blocks) do
    Blocks[I] := nil;
  try
    for I := 0 to 1599 do
    begin
      Op := Integer(NextRandom(State) mod 5);
      if ((Op = 0) or (Count = 0)) and (Count < MaxBlocks) then
      begin
        ModelIds[Count] := RandomLongInt(State);
        ModelVersions[Count] := 0;
        ModelSizes[Count] := BoundarySize(State, MaxBlockSize);
        if ModelSizes[Count] = 0 then
          ModelSizes[Count] := 1;
        GetMem(Blocks[Count], ModelSizes[Count]);
        FillBlock(Blocks[Count], ModelIds[Count], ModelVersions[Count],
          ModelSizes[Count]);
        Inc(Count);
      end
      else if (Op = 1) and (Count > 0) then
      begin
        Position := Integer(NextRandom(State) mod UInt64(Count));
        NewSize := BoundarySize(State, MaxBlockSize);
        if NewSize = 0 then
          NewSize := 1;
        PreservedSize := ModelSizes[Position];
        if NewSize < PreservedSize then
          PreservedSize := NewSize;
        ReallocMem(Blocks[Position], NewSize);
        for J := 0 to PreservedSize - 1 do
          PortableCheck(PByteSpan(Blocks[Position])^[J] =
            Byte((Int64(ModelIds[Position]) * 43 +
            Int64(ModelVersions[Position]) * 71 + J * 19) and $FF),
            'heap-realloc-preserved-byte', ScenarioResult);
        Inc(ModelVersions[Position]);
        ModelSizes[Position] := NewSize;
        FillBlock(Blocks[Position], ModelIds[Position],
          ModelVersions[Position], NewSize);
      end
      else if (Op = 2) and (Count > 0) then
      begin
        Position := Integer(NextRandom(State) mod UInt64(Count));
        Inc(ModelVersions[Position]);
        FillBlock(Blocks[Position], ModelIds[Position],
          ModelVersions[Position], ModelSizes[Position]);
      end
      else if Count > 0 then
      begin
        Position := Integer(NextRandom(State) mod UInt64(Count));
        CheckBlock(Blocks[Position], ModelIds[Position],
          ModelVersions[Position], ModelSizes[Position], ScenarioResult, Digest);
        FreeMem(Blocks[Position]);
        Blocks[Position] := nil;
        if Position < Count - 1 then
        begin
          for J := Position to Count - 2 do
            Blocks[J] := Blocks[J + 1];
          Move(ModelIds[Position + 1], ModelIds[Position],
            (Count - Position - 1) * SizeOf(ModelIds[0]));
          Move(ModelVersions[Position + 1], ModelVersions[Position],
            (Count - Position - 1) * SizeOf(ModelVersions[0]));
          Move(ModelSizes[Position + 1], ModelSizes[Position],
            (Count - Position - 1) * SizeOf(ModelSizes[0]));
        end;
        Dec(Count);
        Blocks[Count] := nil;
      end;

      if Count > 0 then
      begin
        Position := (I * 17 + Count) mod Count;
        CheckBlock(Blocks[Position], ModelIds[Position],
          ModelVersions[Position], ModelSizes[Position], ScenarioResult, Digest);
      end;
      if ((I and 63) = 0) or (I = 1599) then
        for J := 0 to Count - 1 do
          CheckBlock(Blocks[J], ModelIds[J], ModelVersions[J], ModelSizes[J],
            ScenarioResult, Digest);
    end;

    while Count > 0 do
    begin
      Position := Integer(NextRandom(State) mod UInt64(Count));
      CheckBlock(Blocks[Position], ModelIds[Position], ModelVersions[Position],
        ModelSizes[Position], ScenarioResult, Digest);
      FreeMem(Blocks[Position]);
      if Position < Count - 1 then
      begin
        Blocks[Position] := Blocks[Count - 1];
        ModelIds[Position] := ModelIds[Count - 1];
        ModelVersions[Position] := ModelVersions[Count - 1];
        ModelSizes[Position] := ModelSizes[Count - 1];
      end;
      Dec(Count);
      Blocks[Count] := nil;
    end;
  finally
    for I := 0 to Count - 1 do
      if Assigned(Blocks[I]) then
        FreeMem(Blocks[I]);
  end;
end;

procedure RunCellStateMachine(var State: UInt64;
  var ScenarioResult: TPortableResult; var Digest: UInt64);
var
  Cells, Snapshot: TPortableCellArray;
  ModelIds, ModelVersions, ModelSizes: array[0..MaxCells - 1] of Integer;
  ScratchIds, ScratchVersions, ScratchSizes: array[0..MaxCells - 1] of Integer;
  Count, I, J, Op, Position, NewId, NewSize: Integer;
  Temp: TPortableCell;
begin
  Count := 0;
  for I := 0 to 1199 do
  begin
    Op := Integer(NextRandom(State) mod 8);
    if ((Op = 0) or (Count = 0)) and (Count < MaxCells) then
    begin
      NewId := RandomLongInt(State);
      NewSize := BoundarySize(State, 257);
      SetLength(Cells, Count + 1);
      BuildCell(Cells[Count], NewId, 0, NewSize);
      ModelIds[Count] := NewId;
      ModelVersions[Count] := 0;
      ModelSizes[Count] := NewSize;
      Inc(Count);
    end
    else if (Op = 1) and (Count > 0) then
    begin
      Position := Integer(NextRandom(State) mod UInt64(Count));
      for J := Position to Count - 2 do
        Cells[J] := Cells[J + 1];
      if Position < Count - 1 then
      begin
        Move(ModelIds[Position + 1], ModelIds[Position],
          (Count - Position - 1) * SizeOf(ModelIds[0]));
        Move(ModelVersions[Position + 1], ModelVersions[Position],
          (Count - Position - 1) * SizeOf(ModelVersions[0]));
        Move(ModelSizes[Position + 1], ModelSizes[Position],
          (Count - Position - 1) * SizeOf(ModelSizes[0]));
      end;
      Dec(Count);
      SetLength(Cells, Count);
    end
    else if (Op = 2) and (Count < MaxCells) then
    begin
      Position := Integer(NextRandom(State) mod UInt64(Count + 1));
      NewId := RandomLongInt(State);
      NewSize := BoundarySize(State, 257);
      SetLength(Cells, Count + 1);
      for J := Count downto Position + 1 do
        Cells[J] := Cells[J - 1];
      BuildCell(Cells[Position], NewId, 0, NewSize);
      if Position < Count then
      begin
        Move(ModelIds[Position], ModelIds[Position + 1],
          (Count - Position) * SizeOf(ModelIds[0]));
        Move(ModelVersions[Position], ModelVersions[Position + 1],
          (Count - Position) * SizeOf(ModelVersions[0]));
        Move(ModelSizes[Position], ModelSizes[Position + 1],
          (Count - Position) * SizeOf(ModelSizes[0]));
      end;
      ModelIds[Position] := NewId;
      ModelVersions[Position] := 0;
      ModelSizes[Position] := NewSize;
      Inc(Count);
    end
    else if ((Op = 3) or (Op = 4)) and (Count > 0) then
    begin
      Position := Integer(NextRandom(State) mod UInt64(Count));
      Inc(ModelVersions[Position]);
      if Op = 4 then
        ModelSizes[Position] := BoundarySize(State, 257);
      BuildCell(Cells[Position], ModelIds[Position], ModelVersions[Position],
        ModelSizes[Position]);
    end
    else if (Op = 5) and (Count > 1) then
    begin
      for J := 0 to Count - 1 do
      begin
        ScratchIds[J] := ModelIds[Count - 1 - J];
        ScratchVersions[J] := ModelVersions[Count - 1 - J];
        ScratchSizes[J] := ModelSizes[Count - 1 - J];
      end;
      J := 0;
      while J < Count div 2 do
      begin
        Temp := Cells[J];
        Cells[J] := Cells[Count - 1 - J];
        Cells[Count - 1 - J] := Temp;
        Inc(J);
      end;
      for J := 0 to Count - 1 do
      begin
        ModelIds[J] := ScratchIds[J];
        ModelVersions[J] := ScratchVersions[J];
        ModelSizes[J] := ScratchSizes[J];
      end;
    end
    else if (Op = 6) and (Count > 0) then
    begin
      Snapshot := Copy(Cells, 0, Length(Cells));
      SetLength(Cells, 0);
      CheckCells(Snapshot, ModelIds, ModelVersions, ModelSizes, Count,
        ScenarioResult, Digest);
      SetLength(Cells, Count);
      for J := 0 to Count - 1 do
        BuildCell(Cells[J], ModelIds[J], ModelVersions[J], ModelSizes[J]);
      SetLength(Snapshot, 0);
    end
    else if Op = 7 then
    begin
      NewId := RandomLongInt(State);
      NewSize := BoundarySize(State, 257);
      try
        BuildCell(Temp, NewId, I, NewSize);
        if (I and 7) = 0 then
          raise EAbort.Create('expected-portable-exception');
        CheckCell(Temp, NewId, I, ScenarioResult, Digest);
      except
        on E: EAbort do
          PortableCheck(E.Message = 'expected-portable-exception',
            'managed-exception', ScenarioResult);
      end;
    end;

    PortableCheck(Length(Cells) = Count, 'cell-count-after-operation',
      ScenarioResult);
    if Count > 0 then
    begin
      Position := (I * 17 + Count) mod Count;
      PortableCheck(Length(Cells[Position].Bytes) = ModelSizes[Position],
        'cell-size-after-operation', ScenarioResult);
      CheckCell(Cells[Position], ModelIds[Position], ModelVersions[Position],
        ScenarioResult, Digest);
    end;
    if ((I and 31) = 0) or (I = 1199) then
      CheckCells(Cells, ModelIds, ModelVersions, ModelSizes, Count,
        ScenarioResult, Digest);
  end;
  SetLength(Cells, 0);
end;

procedure CheckStreamContent(Stream: TMemoryStream; const Model: array of Byte;
  ModelSize, ExpectedPosition: Integer; var ScenarioResult: TPortableResult;
  var Digest: UInt64);
var
  Buffer: array[0..255] of Byte;
  SavedPosition: Int64;
  Offset, Count, ReadCount, I: Integer;
begin
  SavedPosition := Stream.Position;
  PortableCheck(SavedPosition = ExpectedPosition, 'stream-verify-position',
    ScenarioResult);
  PortableCheck(Stream.Size = ModelSize, 'stream-verify-size', ScenarioResult);
  Stream.Position := 0;
  Offset := 0;
  while Offset < ModelSize do
  begin
    Count := ModelSize - Offset;
    if Count > Length(Buffer) then
      Count := Length(Buffer);
    ReadCount := Stream.Read(Buffer[0], Count);
    PortableCheck(ReadCount = Count, 'stream-verify-read-count', ScenarioResult);
    for I := 0 to Count - 1 do
    begin
      PortableCheck(Buffer[I] = Model[Offset + I], 'stream-verify-byte',
        ScenarioResult);
      Mix(Digest, UInt64(Buffer[I]) + (UInt64(Offset + I) shl 8));
    end;
    Inc(Offset, Count);
  end;
  Stream.Position := SavedPosition;
end;

procedure RunStreamStateMachine(var State: UInt64;
  var ScenarioResult: TPortableResult; var Digest: UInt64);
var
  Stream, CopyStream: TMemoryStream;
  Model: array[0..MaxBufferSize - 1] of Byte;
  WriteBuffer, ReadBuffer: array[0..511] of Byte;
  ModelSize, ModelPosition, I, J, Op, Count, ActualRead, NewPosition: Integer;
begin
  Stream := TMemoryStream.Create;
  try
    ModelSize := 0;
    ModelPosition := 0;
    for I := 0 to 1499 do
    begin
      Op := Integer(NextRandom(State) mod 6);
      if (Op <= 2) and (ModelPosition < MaxBufferSize) then
      begin
        Count := BoundarySize(State, Length(WriteBuffer));
        if Count > MaxBufferSize - ModelPosition then
          Count := MaxBufferSize - ModelPosition;
        for J := 0 to Count - 1 do
          WriteBuffer[J] := Byte(NextRandom(State));
        if Count > 0 then
          Stream.WriteBuffer(WriteBuffer[0], Count);
        for J := 0 to Count - 1 do
          Model[ModelPosition + J] := WriteBuffer[J];
        Inc(ModelPosition, Count);
        if ModelPosition > ModelSize then
          ModelSize := ModelPosition;
      end
      else if Op = 3 then
      begin
        if ModelSize = 0 then
          NewPosition := 0
        else
          NewPosition := Integer(NextRandom(State) mod UInt64(ModelSize + 1));
        Stream.Position := NewPosition;
        ModelPosition := NewPosition;
      end
      else if (Op = 4) and (ModelSize > 0) then
      begin
        Count := BoundarySize(State, Length(ReadBuffer));
        if Count > ModelSize - ModelPosition then
          Count := ModelSize - ModelPosition;
        if Count < 0 then
          Count := 0;
        if Count > 0 then
          ActualRead := Stream.Read(ReadBuffer[0], Count)
        else
          ActualRead := 0;
        PortableCheck(ActualRead = Count, 'stream-read-count', ScenarioResult);
        for J := 0 to Count - 1 do
          PortableCheck(ReadBuffer[J] = Model[ModelPosition + J],
            'stream-read-byte', ScenarioResult);
        Inc(ModelPosition, Count);
      end
      else if (Op = 5) and (ModelSize > 0) then
      begin
        Count := Integer(NextRandom(State) mod UInt64(ModelSize + 1));
        Stream.Size := Count;
        ModelSize := Count;
        if ModelPosition > ModelSize then
          ModelPosition := ModelSize;
        Stream.Position := ModelPosition;
      end;

      PortableCheck(Stream.Size = ModelSize, 'stream-size', ScenarioResult);
      PortableCheck(Stream.Position = ModelPosition, 'stream-position',
        ScenarioResult);
      if ((I and 63) = 0) or (I = 1499) then
      begin
        CheckStreamContent(Stream, Model, ModelSize, ModelPosition,
          ScenarioResult, Digest);
        CopyStream := TMemoryStream.Create;
        try
          Stream.Position := 0;
          ModelPosition := 0;
          CopyStream.CopyFrom(Stream, 0);
          CheckStreamContent(CopyStream, Model, ModelSize, ModelSize,
            ScenarioResult, Digest);
        finally
          CopyStream.Free;
        end;
        Stream.Position := ModelPosition;
      end;
    end;
    for I := 0 to ModelSize - 1 do
      Mix(Digest, UInt64(Model[I]) or (UInt64(I) shl 8));
    Mix(Digest, ModelSize);
  finally
    Stream.Free;
  end;
end;

procedure RunPortableScenario(Seed: UInt64; WorkerId, Phase: Integer;
  out ScenarioResult: TPortableResult);
var
  State: UInt64;
  Order: array[0..2] of Integer;
  I, J, Item: Integer;
begin
  ScenarioResult.Checks := 0;
  ScenarioResult.Digest := HashOffset;
  State := InitialState(Seed, WorkerId, Phase);
  for I := 0 to High(Order) do
    Order[I] := I;
  for I := High(Order) downto 1 do
  begin
    J := Integer(NextRandom(State) mod UInt64(I + 1));
    Item := Order[I];
    Order[I] := Order[J];
    Order[J] := Item;
  end;
  for I := 0 to High(Order) do
    case Order[I] of
      0: RunHeapStateMachine(State, ScenarioResult, ScenarioResult.Digest);
      1: RunCellStateMachine(State, ScenarioResult, ScenarioResult.Digest);
      2: RunStreamStateMachine(State, ScenarioResult, ScenarioResult.Digest);
    end;
  Mix(ScenarioResult.Digest, State);
  Mix(ScenarioResult.Digest, UInt64(ScenarioResult.Checks));
end;

procedure FoldPortableResult(var Digest: UInt64;
  const ScenarioResult: TPortableResult; WorkerId, Phase: Integer);
begin
  Mix(Digest, UInt64(Phase));
  Mix(Digest, UInt64(WorkerId));
  Mix(Digest, UInt64(ScenarioResult.Checks));
  Mix(Digest, ScenarioResult.Digest);
end;

end.
