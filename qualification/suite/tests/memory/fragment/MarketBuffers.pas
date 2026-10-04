unit MarketBuffers;

// REST-only additional stress. No WS subscriptions, deltas, canonical/UI book copies.
interface

uses mormot.core.base, mormot.core.data, mormot.core.variants, FragmentJsonHelpers,
  System.SysUtils, System.Classes, System.Variants, BenchCompression;

type
  TOrderGlass = record
    Quantity, Rate: Double;
  end;
  TOrdersGlass = array of TOrderGlass;

procedure InitBooks(Seed: Cardinal; Markets: Integer; const DataDir: string);
procedure PulseBooks;
procedure ClearBooks;
function BookBytes: UInt64;
function BookChecksum: UInt64;

implementation

type
  TBook = record
    BuyOld, SellOld: TOrdersGlass;
  end;
  TFixture = record
    Levels: Integer;
    Compressed: RawUtf8;
  end;
  PFixture = ^TFixture;

var
  Books: TArray<TBook>;
  Fixtures: TArray<TFixture>;
  Distribution: TArray<Integer>;
  BuyM, SellM, BuyL, SellL: TOrdersGlass;
  LastObj: Variant;
  LastResponse: RawUtf8;
  Rng: Cardinal;
  Turn: Integer;

{$I ParseBookInt.inc}

procedure InitBooks(Seed: Cardinal; Markets: Integer; const DataDir: string);
var
  N: Integer;
begin
  SetLength(Books, Markets);
  Rng := Seed;
  // Load the same fixtures even for Markets=0, keeping preparation memory comparable.
  var S := TFileStream.Create(DataDir + '\rest-fixtures.bin', fmOpenRead);
  try
    S.ReadBuffer(N, 4);
    SetLength(Distribution, N);
    S.ReadBuffer(N, 4);
    SetLength(Fixtures, N);
    S.ReadBuffer(Distribution[0], Length(Distribution) * 4);
    for var I := 0 to High(Fixtures) do begin
      S.ReadBuffer(Fixtures[I].Levels, 4);
      S.ReadBuffer(N, 4);
      SetLength(Fixtures[I].Compressed, N);
      S.ReadBuffer(Fixtures[I].Compressed[1], N);
    end;
  finally
    S.Free;
  end;
end;

procedure PulseBooks;
const
  FastCS: TDocVariantOptions = [dvoReturnNullForUnknownProperty, dvoValueCopiedByReference,
    dvoNameCaseSensitive, dvoAllowDoubleValue];
var
  Root, Bids, Asks: PDocVariantData;
  BuyT, SellT: TOrdersGlass;
  UpdateID: Int64;
begin
  If Length(Books) = 0 then exit;
  Rng := Cardinal((UInt64(Rng) * 1664525 + 1013904223) and $FFFFFFFF);
  var Fixture: PFixture := @Fixtures[Distribution[(Rng shr 8) mod Cardinal(Length(Distribution))]];
  // BDeepDataWorker.DoUpdateMarket calls ClearIntOrderBook before EVERY market.
  BuyL := nil;
  SellL := nil;
  LastResponse := ZInflate(Pointer(Fixture.Compressed), Length(Fixture.Compressed), 31);
  // GetObjFromJSON clears the previous Parser.LastObj; the new DOM survives this call.
  VarClear(LastObj);
  If not _Json(LastResponse, LastObj, FastCS) then raise Exception.Create('REST JSON failed');
  Root := _Safe(LastObj);
  If not Root.TryLoadI64('lastUpdateId', UpdateID) or not Root.GetAsArray('bids', Bids) or
    not Root.GetAsArray('asks', Asks) then raise Exception.Create('REST depth fields missing');
  ParseBookInt(Bids, BuyM);
  ParseBookInt(Asks, SellM);
  If (Length(BuyM) <> Fixture.Levels) or (Length(SellM) <> Fixture.Levels) then
    raise Exception.Create('REST book size mismatch');
  // getorderbook(false,true), partial branch: L is empty after ClearIntOrderBook.
  SetLength(BuyT, Length(BuyM));
  SetLength(SellT, Length(SellM));
  Move(BuyM[0], BuyT[0], Length(BuyM) * SizeOf(TOrderGlass));
  Move(SellM[0], SellT[0], Length(SellM) * SizeOf(TOrderGlass));
  SetLength(BuyL, Length(BuyM));
  SetLength(SellL, Length(SellM));
  Move(BuyT[0], BuyL[0], Length(BuyM) * SizeOf(TOrderGlass));
  Move(SellT[0], SellL[0], Length(SellM) * SizeOf(TOrderGlass));
  BuyT := nil;
  SellT := nil;
  // UseMainGlass=false calls HandleGlass(L,L); only the Old copies are kept by the market.
  With Books[Turn mod Length(Books)] do begin
    SetLength(BuyOld, Length(BuyL));
    SetLength(SellOld, Length(SellL));
    for var I := 0 to High(BuyL) do BuyOld[I] := BuyL[I];
    for var I := 0 to High(SellL) do SellOld[I] := SellL[I];
  end;
  Inc(Turn);
end;

function BookBytes: UInt64;
begin
  Result := UInt64(Length(BuyM) + Length(SellM) + Length(BuyL) + Length(SellL)) * SizeOf(TOrderGlass);
  for var B in Books do Inc(Result, UInt64(Length(B.BuyOld) + Length(B.SellOld)) * SizeOf(TOrderGlass));
end;

function BookChecksum: UInt64;
begin
  Result := 0;
  for var B in Books do begin
    for var Level in B.BuyOld do Result := ((Result shl 7) or (Result shr 57)) xor UInt64(Round(Level.Rate * 100));
    for var Level in B.SellOld do Result := ((Result shl 7) or (Result shr 57)) xor UInt64(Round(Level.Rate * 100));
  end;
end;

procedure ClearBooks;
begin
  Books := nil;
  BuyM := nil;
  SellM := nil;
  BuyL := nil;
  SellL := nil;
  LastResponse := '';
  VarClear(LastObj);
end;

end.
