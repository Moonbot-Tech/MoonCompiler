program orderbook_moon;

{$mode delphiunicode}
{$H+}
{$R-}
{$Q-}

uses
  cthreads, SysUtils, Classes, Math,
  mormot.core.base, JsonHelpers;

type
  TLevel = record
    Price, Quantity: Double;
  end;
  TLevels = TArray<TLevel>;
  TBook = record
    LastUpdateId: Int64;
    Bids, Asks: TLevels;
  end;
  TFill = record
    Quantity, Spent, AveragePrice, LastPrice, Slippage, Unspent: Double;
  end;
  TInput = record
    Json: RawUtf8;
    Budgets: array[0..2] of Double;
  end;
  TTimespec = record
    Seconds, Nanoseconds: Int64;
  end;

function clock_gettime(Id: LongInt; var Time: TTimespec): LongInt; cdecl; external 'c';

function ClockNs(Id: Integer): Int64;
var
  Time: TTimespec;
begin
  If clock_gettime(Id, Time) <> 0 then raise Exception.Create('clock_gettime failed');
  Result := Time.Seconds * 1000000000 + Time.Nanoseconds;
end;

function ReadBytes(const FileName: string): RawUtf8;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  SetLength(Result, Stream.Size);
  If Length(Result) > 0 then Stream.ReadBuffer(Result[1], Length(Result));
  Stream.Free;
end;

function PeakRss: Int64;
var
  Lines: TStringList;
  Value: string;
begin
  Result := 0;
  Lines := TStringList.Create;
  Lines.LoadFromFile('/proc/self/status');
  for var Line in Lines do
    If Pos('VmHWM:', Line) = 1 then begin
      Value := Trim(Copy(Line, 7, MaxInt));
      Result := StrToInt64(Trim(Copy(Value, 1, Pos('kB', Value) - 1))) * 1024;
    end;
  Lines.Free;
end;

function ReadLevels(const ArrayValue: TJsonValue): TLevels;
var
  Level: TLevel;
  Index: Integer;
begin
  If ArrayValue.Kind <> jkArray then raise Exception.Create('Expected level array');
  SetLength(Result, ArrayValue.Count);
  Index := 0;
  for var Row in ArrayValue.Items do begin
    If (Row.Kind <> jkArray) or (Row.Count <> 2) then raise Exception.Create('Expected price/quantity pair');
    If (Row.Item[0].Kind <> jkString) or (Row.Item[1].Kind <> jkString) or
       not Row.TryLoadSlotNum(0, Level.Price) or not Row.TryLoadSlotNum(1, Level.Quantity) then
      raise Exception.Create('Invalid decimal string');
    If IsNan(Level.Price) or IsInfinite(Level.Price) or (Level.Price <= 0) or
       IsNan(Level.Quantity) or IsInfinite(Level.Quantity) or (Level.Quantity < 0) then
      raise Exception.Create('Invalid price or quantity');
    Result[Index] := Level;
    Inc(Index);
  end;
end;

function ParseBook(const Json: RawUtf8): TBook;
var
  Document: TJsonDocument;
begin
  Document := TJsonDocument.Create;
  If not Document.Parse(Json) then raise Exception.Create('Invalid JSON');
  If (Document.Root.Get('lastUpdateId').Kind <> jkInt64) or
     not Document.Root.Get('lastUpdateId').TryI64(Result.LastUpdateId) then
    raise Exception.Create('Missing update id');
  Result.Bids := ReadLevels(Document.Root.Get('bids'));
  Result.Asks := ReadLevels(Document.Root.Get('asks'));
  Document.Free;
end;

// The snapshot is already in exchange order. No sorting, locks or I/O here.
function Buy(const Asks: TLevels; Budget: Double): TFill;
var
  Remaining, Cost, Taken: Double;
begin
  Result := Default(TFill);
  Remaining := Budget;
  for var Level in Asks do begin
    If Remaining <= 0 then Break;
    If Level.Quantity = 0 then Continue;
    Cost := Level.Price * Level.Quantity;
    If Cost <= Remaining then Taken := Level.Quantity
    else begin
      Cost := Remaining;
      Taken := Remaining / Level.Price;
    end;
    Result.Quantity := Result.Quantity + Taken;
    Result.Spent := Result.Spent + Cost;
    Result.LastPrice := Level.Price;
    Remaining := Remaining - Cost;
  end;
  Result.Unspent := Remaining;
  If Result.Quantity > 0 then begin
    Result.AveragePrice := Result.Spent / Result.Quantity;
    Result.Slippage := Result.AveragePrice / Asks[0].Price - 1;
  end;
end;

function Number(Value: Double): string;
begin
  Result := FloatToStrF(Value, ffGeneral, 17, 0);
end;

procedure Dump(const FileName: string; const Inputs: TArray<TInput>);
var
  Output: TextFile;
  Book: TBook;
  Fill: TFill;
begin
  AssignFile(Output, FileName);
  Rewrite(Output);
  for var Index := 0 to High(Inputs) do begin
    Book := ParseBook(Inputs[Index].Json);
    Writeln(Output, 'book', #9, Index, #9, Book.LastUpdateId);
    for var Level in Book.Bids do
      Writeln(Output, 'bid', #9, Number(Level.Price), #9, Number(Level.Quantity));
    for var Level in Book.Asks do
      Writeln(Output, 'ask', #9, Number(Level.Price), #9, Number(Level.Quantity));
    for var Budget in Inputs[Index].Budgets do begin
      Fill := Buy(Book.Asks, Budget);
      Writeln(Output, 'fill', #9, Number(Fill.Quantity), #9, Number(Fill.Spent), #9,
        Number(Fill.AveragePrice), #9, Number(Fill.LastPrice), #9, Number(Fill.Slippage), #9, Number(Fill.Unspent));
    end;
  end;
  CloseFile(Output);
end;

procedure Run;
var
  Manifest, Fields: TStringList;
  Inputs: TArray<TInput>;
  Book: TBook;
  Fill: TFill;
  Passes: Integer;
  WallStart, CpuStart, Wall, Cpu, Levels, IdSum: Int64;
  Checksum, LevelSum: Double;
begin
  DefaultFormatSettings.DecimalSeparator := '.';
  If ParamCount < 2 then raise Exception.Create('Usage: orderbook_moon DATA PASSES [DUMP]');
  Passes := StrToInt(ParamStr(2));
  If Passes <= 0 then raise Exception.Create('PASSES must be positive');
  Manifest := TStringList.Create;
  Fields := TStringList.Create;
  Fields.Delimiter := #9;
  Fields.StrictDelimiter := True;
  Manifest.LoadFromFile(ParamStr(1) + '/manifest.tsv');
  SetLength(Inputs, Manifest.Count);
  for var Index := 0 to Manifest.Count - 1 do begin
    Fields.DelimitedText := Manifest[Index];
    If Fields.Count <> 4 then raise Exception.Create('Invalid manifest');
    Inputs[Index].Json := ReadBytes(ParamStr(1) + '/' + Fields[0]);
    for var Budget := 0 to 2 do Inputs[Index].Budgets[Budget] := StrToFloat(Fields[Budget + 1]);
  end;
  Fields.Free;
  Manifest.Free;
  Checksum := 0;
  LevelSum := 0;
  Levels := 0;
  IdSum := 0;
  CpuStart := ClockNs(2);
  WallStart := ClockNs(1);
  for var Pass := 1 to Passes do
    for var Index := 0 to High(Inputs) do begin
      Book := ParseBook(Inputs[Index].Json);
      Inc(IdSum, Book.LastUpdateId);
      Inc(Levels, Length(Book.Bids) + Length(Book.Asks));
      // Consume both complete arrays, including the unexecuted side of the book.
      for var Level in Book.Bids do LevelSum := LevelSum + Level.Price + Level.Quantity;
      for var Level in Book.Asks do LevelSum := LevelSum + Level.Price + Level.Quantity;
      for var Budget in Inputs[Index].Budgets do begin
        Fill := Buy(Book.Asks, Budget);
        Checksum := Checksum + Fill.Quantity + Fill.Spent + Fill.AveragePrice +
          Fill.LastPrice + Fill.Slippage + Fill.Unspent;
      end;
      Book.Bids := nil;
      Book.Asks := nil;
    end;
  Wall := ClockNs(1) - WallStart;
  Cpu := ClockNs(2) - CpuStart;
  Writeln('{"language":"Moon","cpu_ns":', Cpu, ',"wall_ns":', Wall,
    ',"snapshots":', Int64(Length(Inputs)) * Passes, ',"levels":', Levels,
    ',"id_sum":', IdSum, ',"level_sum":', Number(LevelSum), ',"checksum":', Number(Checksum),
    ',"peak_rss":', PeakRss, '}');
  If ParamCount = 3 then Dump(ParamStr(3), Inputs);
end;

begin
  Run;
end.
