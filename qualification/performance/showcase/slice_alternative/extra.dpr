program slice_cache_extra;
{$mode delphiunicode}
{$codepage utf8}
uses {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Generics.Defaults, Generics.MemoryExpanders, AstraSlice.Collections, SliceFactory;
type
  TReplaceable = class(TOpenAddressingLP<UTF8String, Integer, TDefaultHashFactory, TLinearProbing>)
    procedure ReplaceComparer(const C: IEqualityComparer<UTF8String>);
  end;
  TFold = class(TEqualityComparer<UTF8String>)
    function Equals(const A, B: UTF8String): Boolean; override;
    function GetHashCode(const A: UTF8String): Integer; override;
  end;
  TFactory = class(TGenericsHashFactory)
    class function GetHashCode(P: Pointer; N: SizeInt; Init: UInt32 = 0): UInt32; override;
  end;
  TFactoryMap = TOpenAddressingLinearLP<UTF8String, Integer, TFactory>;
var Calls: Integer; ReenterMap: TFactoryMap; Armed: Boolean;

procedure TReplaceable.ReplaceComparer(const C: IEqualityComparer<UTF8String>);
begin
  Clear;
  FEqualityComparer := C;
end;
function TFold.Equals(const A, B: UTF8String): Boolean;
begin
  Result := UpperCase(UnicodeString(A)) = UpperCase(UnicodeString(B));
end;
function TFold.GetHashCode(const A: UTF8String): Integer;
begin
  Result := 7;
end;
class function TFactory.GetHashCode(P: Pointer; N: SizeInt; Init: UInt32): UInt32;
begin
  Inc(Calls);
  If Armed then begin
    Armed := False;
    ReenterMap.Capacity := ReenterMap.Capacity * 2;
  end;
  Result := inherited GetHashCode(P, N, Init) xor $12345678;
end;

var Foreign: TForeignMap; Local: TDictionary<UTF8String, Integer>;
    D: TReplaceable; F: TFactoryMap; R: TDictionary<RawByteString, Integer>;
    K: UTF8String; Raw: RawByteString; V, Expected, Before: Integer; A, B: Boolean;
begin
  Foreign := MakeForeign;
  K := 'cross-unit';
  If not Foreign.TryGetValueUtf8(PAnsiChar(K), Length(K), V) or (V <> 73) then Halt(1);
  Local := TDictionary<UTF8String, Integer>.Create;
  Local.Add(K, 74);
  If not Local.TryGetValueUtf8(PAnsiChar(K), Length(K), V) or (V <> 74) then Halt(2);
  Writeln('instance_size=', Local.InstanceSize);
  Local.Free;
  Foreign.Free;
  D := TReplaceable.Create;
  D.ReplaceComparer(TFold.Create);
  D.Add('MARKET', 9);
  K := 'market';
  If not D.TryGetValueUtf8(PAnsiChar(K), Length(K), V) or (V <> 9) then Halt(3);
  D.Free;
  F := TFactoryMap.Create;
  F.Add(K, 18);
  Before := Calls;
  If not F.TryGetValueUtf8(PAnsiChar(K), Length(K), V) or (V <> 18) or (Calls <= Before) then Halt(4);
  ReenterMap := F;
  Before := F.Capacity;
  Armed := True;
  If not F.TryGetValueUtf8(PAnsiChar(K), Length(K), V) or (V <> 18) or (F.Capacity <= Before) then Halt(6);
  ReenterMap := nil;
  F.Free;
  R := TDictionary<RawByteString, Integer>.Create;
  K := UTF8String('café');
  Raw := K;
  SetCodePage(Raw, 1252, False);
  R.Add(Raw, 5);
  Raw := K;
  A := R.TryGetValue(Raw, Expected);
  B := R.TryGetValueUtf8(PAnsiChar(K), Length(K), V);
  If (A <> B) or (V <> Expected) then Halt(5);
  R.Free;
  Writeln('SLICE_CACHE_EXTRA_PASS');
end.
