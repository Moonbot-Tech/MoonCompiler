program rtl_api_unicode_copy_contracts;

{$mode delphiunicode}
{$optimization noautoinline}

uses SysUtils;

type
  EAllocationRefused = class(Exception);
  TUnicodeAlias = type UnicodeString;
  TUnicodeChain = type TUnicodeAlias;
  TCopyProbe<T> = class
    class procedure Failure(Kind: Integer); static;
    class procedure Content; static;
    class function Slice(const S: T; Index, Count: SizeInt): T; static;
  end;

var
  OriginalMM, FaultMM: TMemoryManager;
  Armed: Boolean;
  Refused: EAllocationRefused;
  FaultCalls: Integer;

procedure Check(Value: Boolean; const Name: UnicodeString);
begin
  If not Value then begin
    Writeln('FAIL ', Name);
    Halt(1);
  end;
end;

function FaultGetMem(Size: PtrUInt): Pointer;
begin
  If Armed then begin
    Armed := False;
    Inc(FaultCalls);
    raise Refused;
  end;
  Result := OriginalMM.GetMem(Size);
end;

function FaultRealloc(var P: Pointer; Size: PtrUInt): Pointer;
begin
  If Armed then begin
    Armed := False;
    Inc(FaultCalls);
    raise Refused;
  end;
  Result := OriginalMM.ReallocMem(P, Size);
end;

class procedure TCopyProbe<T>.Failure(Kind: Integer);
var
  Source, Destination, Alias, Expected: T;
  Caught: Boolean;
begin
  Source := StringOfChar('s', 128);
  case Kind of
    0: Destination := '';
    1, 2: Destination := StringOfChar('d', 32);
    3: Destination := 'constant previous result';
    4: begin
      Destination := StringOfChar('d', 32);
      Source := Destination;
    end;
  end;
  If Kind = 2 then Alias := Destination;
  { Keep an independent expected value for the unique destination. }
  If Kind = 1 then Expected := StringOfChar('d', 32)
  else Expected := Destination;
  Refused := EAllocationRefused.Create('injected allocation failure');
  FaultCalls := 0;
  Caught := False;
  SetMemoryManager(FaultMM);
  Armed := True;
  try
    try
      Destination := Copy(Source, 2, 7);
    except
      on EAllocationRefused do Caught := True;
    end;
  finally
    Armed := False;
    SetMemoryManager(OriginalMM);
  end;
  Check(Caught, 'allocation exception propagated');
  Check(Destination = Expected, 'failed assignment preserves old destination');
  Check((Kind <> 2) or (Alias = Expected), 'shared owner survives failed assignment');
  Check(FaultCalls = 1, 'fault hook triggered once');
end;

class function TCopyProbe<T>.Slice(const S: T; Index, Count: SizeInt): T;
begin
  Result := Copy(S, Index, Count);
end;

class procedure TCopyProbe<T>.Content;
var
  Source, Destination, Alias: T;
  i: Integer;
begin
  Source := '0123456789';
  Destination := Copy(Source, -7, 3);
  Check(Destination = '012', 'negative index clamps to one');
  Destination := Copy(Source, 8, High(SizeInt));
  Check(Destination = '789', 'count clamps to remaining length');
  Destination := Copy(Source, High(SizeInt), 3);
  Check(Destination = '', 'index beyond source returns empty');
  Destination := StringOfChar('d', 32);
  Destination := Copy(Source, 2, 7);
  Check(Destination = '1234567', 'unique existing result replaced');
  Alias := Destination;
  Destination := Copy(Source, 3, 4);
  Check((Destination = '2345') and (Alias = '1234567'), 'shared existing result replaced');
  Destination := Copy(Destination, 2, 2);
  Check((Destination = '34') and (Alias = '1234567'), 'source aliases destination');
  Destination := Copy(Source, 2, 0);
  Check(Destination = '', 'zero count releases destination');
  Destination := Copy(Source, 2, -1);
  Check(Destination = '', 'negative count returns empty');
  Destination := StringOfChar('d', 32);
  Destination := Copy(Source, Length(Destination) div 32 + 1, Length(Destination));
  Check(Destination = '123456789', 'arguments read previous destination');
  for i := 0 to 128 do begin
    Source := StringOfChar(WideChar($400 + i), i);
    Destination := Slice(Source, 1, High(SizeInt));
    Check(Destination = Source, 'typed result content');
    Alias := Destination;
    Destination := Copy(Destination, 2, High(SizeInt));
    Check(Destination = Slice(Source, 2, High(SizeInt)), 'source aliases typed destination');
    Check(Alias = Source, 'retained source owner survives');
    Alias := '';
    Destination := StringOfChar(WideChar($400 + i), i);
    Destination := Copy(Destination, 2, i div 2);
    Check(Destination = Slice(Source, 2, i div 2), 'unique source aliases typed destination');
  end;
end;

function OverloadKind(const S: UnicodeString): Integer; overload;
begin
  Result := 1;
end;

function OverloadKind(const S: TUnicodeAlias): Integer; overload;
begin
  Result := 2;
end;

var
  Kind: Integer;
  A: TUnicodeAlias;
  WideSource, WideDestination: WideString;
begin
  GetMemoryManager(OriginalMM);
  FaultMM := OriginalMM;
  FaultMM.GetMem := @FaultGetMem;
  FaultMM.ReallocMem := @FaultRealloc;
  for Kind := 0 to 4 do begin
    TCopyProbe<UnicodeString>.Failure(Kind);
    TCopyProbe<TUnicodeAlias>.Failure(Kind);
    TCopyProbe<TUnicodeChain>.Failure(Kind);
    {$ifndef MSWINDOWS}
    TCopyProbe<WideString>.Failure(Kind);
    {$endif}
  end;
  TCopyProbe<UnicodeString>.Content;
  TCopyProbe<TUnicodeAlias>.Content;
  TCopyProbe<TUnicodeChain>.Content;
  {$ifndef MSWINDOWS}
  TCopyProbe<WideString>.Content;
  {$endif}
  WideSource := WideString('0123456789');
  WideDestination := Copy(WideSource, 2, 7);
  Check(WideDestination = WideString('1234567'), 'WideString copy ABI');
  WideDestination := Copy(WideDestination, 2, 3);
  Check(WideDestination = WideString('234'), 'WideString self-copy ABI');
  A := 'abcdef';
  Check(OverloadKind(A) = 2, 'strong alias overload');
  Check(OverloadKind(Copy(A, 2, 3)) = 1, 'Copy expression canonical overload');
  Check(OverloadKind(TCopyProbe<TUnicodeAlias>.Slice(A, 2, 3)) = 2, 'typed function result overload');
  Writeln('RTL_API_UNICODE_COPY_CONTRACTS_OK');
end.
