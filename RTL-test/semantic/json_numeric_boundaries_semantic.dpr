program json_numeric_boundaries_semantic;
{$APPTYPE CONSOLE}
{$mode delphiunicode}
uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, Rtti, System.JSON, System.JSON.Readers, System.JSON.Serializers, System.JSON.Types;

procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;

function Bits(Value: Double): UInt64;
begin
  Move(Value,Result,SizeOf(Result));
end;

procedure CheckReader(const Input: string; ObjectReader: Boolean; Operation: Integer;
  Expected: UInt64; Invalid: Boolean = False);
var
  Node: TJSONValue;
  Reader: TJsonReader;
  Raised: Boolean;
  Value: UInt64;
begin
  Node:=nil;
  if ObjectReader then begin
    Node:=TJSONObject.ParseJSONValue('['+Input+']');
    Reader:=TJsonObjectReader.Create(Node);
  end else
    Reader:=TJsonTextReader.Create(TStringReader.Create('['+Input+']'));
  try
    Check(Reader.Read,'start array');
    Raised:=False;
    Value:=0;
    try
      case Operation of
        0: Value:=Bits(Reader.ReadAsDouble);
        1: Value:=UInt64(Reader.ReadAsInt64);
        2: Value:=LongWord(Reader.ReadAsInteger);
        3: Value:=Reader.ReadAsUInt64;
        4: Check(Reader.ReadAsString=Input,'integer string preserves width and sign');
      end;
    except on E: EJsonReaderException do Raised:=True; end;
    Check(Raised=Invalid,'conversion rejection: '+Input);
    if Invalid then Exit;
    if Operation<>4 then Check(Value=Expected,'conversion value: '+Input);
    Check(Reader.Path='[0]','one conversion advances exactly once');
    if Input='null' then
      Check(Reader.TokenType=TJsonToken.Null,'null remains null')
    else if Operation=0 then
      Check((Reader.TokenType=TJsonToken.Float) and (Bits(Reader.Value.AsExtended)=Expected),'floating token value')
    else if Operation in [1,2,3] then
      Check(Reader.TokenType=TJsonToken.Integer,'integer token value');
    Check(Reader.Read and (Reader.TokenType=TJsonToken.EndArray),'end array');
  finally
    Reader.Free;
    Node.Free;
  end;
end;

procedure CheckNavigation(ObjectReader: Boolean);
var
  Node: TJSONValue;
  Reader: TJsonReader;
begin
  Node:=nil;
  if ObjectReader then begin
    Node:=TJSONObject.ParseJSONValue('[5000000000,1.5,"42",null]');
    Reader:=TJsonObjectReader.Create(Node);
  end else
    Reader:=TJsonTextReader.Create(TStringReader.Create('[5000000000,1.5,"42",null]'));
  try
    Check(Reader.Read,'navigation start');
    Check((Reader.ReadAsInt64=5000000000) and (Reader.Path='[0]'),'wide integer index');
    Check((Reader.ReadAsDouble=1.5) and (Reader.Path='[1]'),'double index');
    Check((Reader.ReadAsInt64=42) and (Reader.Path='[2]') and
      (Reader.TokenType=TJsonToken.Integer) and (Reader.Value.AsInt64=42),'string conversion state');
    Check((Reader.ReadAsInt64=0) and (Reader.Path='[3]') and
      (Reader.TokenType=TJsonToken.Null),'null index');
    Check(Reader.Read and (Reader.TokenType=TJsonToken.EndArray),'navigation end');
  finally
    Reader.Free;
    Node.Free;
  end;
end;

procedure CheckDOM(const Input: string);
var
  Node: TJSONValue;
begin
  Node:=TJSONObject.ParseJSONValue(Input);
  try
    Check(Assigned(Node) and (Node.Value=Input),'DOM unsigned lexeme');
    Check(Node.ToJSON=Input,'DOM unsigned output');
  finally Node.Free; end;
end;

procedure CheckSerializer;
var
  S: TJsonSerializer;
  Which: Integer;
  Raised: Boolean;
begin
  S:=TJsonSerializer.Create;
  try
    Check(S.Deserialize<Int64>('"5000000000"')=5000000000,'serializer numeric string');
    Check(S.Deserialize<Int64>('-9223372036854775808')=Low(Int64),'serializer signed minimum');
    Check(S.Deserialize<UInt64>('18446744073709551615')=High(UInt64),'serializer unsigned maximum');
    Check(S.Deserialize<UInt64>('"18446744073709551615"')=High(UInt64),'serializer unsigned string');
    Check(S.Deserialize<LongWord>('4294967295')=High(LongWord),'serializer UInt32 maximum');
    Check(S.Deserialize<Byte>('255')=255,'serializer byte maximum');
    Check(S.Deserialize<ShortInt>('-128')=-128,'serializer int8 minimum');
    Check(Bits(S.Deserialize<Double>('18446744073709551615'))=$43F0000000000000,'serializer wide double');
    Check(S.Deserialize<Double>('"1.5"')=1.5,'serializer floating string');
    Check(S.Deserialize<Currency>('1.5')=1.5,'serializer currency type');
    Check(S.Deserialize<Single>('1.5')=1.5,'serializer single type');
    for Which:=0 to 7 do begin
      Raised:=False;
      try
        case Which of
          0: S.Deserialize<Int64>('9223372036854775808');
          1: S.Deserialize<Int64>('1.5');
          2: S.Deserialize<Integer>('2147483648');
          3: S.Deserialize<ShortInt>('128');
          4: S.Deserialize<Byte>('256');
          5: S.Deserialize<UInt64>('-1');
          6: S.Deserialize<Int64>('"garbage"');
          7: S.Deserialize<UInt64>('"-1"');
        end;
      except on E: EJsonSerializationException do Raised:=True; end;
      Check(Raised,'serializer rejects invalid conversion '+IntToStr(Which));
    end;
  finally S.Free; end;
end;

var
  ObjectReader: Boolean;
  V: TValue;
begin
  V:=TValue.From<UInt64>(High(UInt64));
  Check((Bits(V.AsExtended)=$43F0000000000000) and (Bits(V.AsDouble)=$43F0000000000000) and
    (V.AsSingle>0),'unsigned RTTI floating conversions');
  V:=TValue.From<Int64>(-42);
  Check((V.AsExtended=-42) and (V.AsDouble=-42) and (V.AsSingle=-42),'signed RTTI control');
  CheckDOM('9223372036854775808');
  CheckDOM('18446744073709551615');
  CheckDOM('1e0');
  CheckDOM('18446744073709551616');
  for ObjectReader:=False to True do begin
    CheckReader('5000000000',ObjectReader,0,$41F2A05F20000000);
    CheckReader('18446744073709551615',ObjectReader,0,$43F0000000000000);
    CheckReader('18446744073709551616',ObjectReader,0,$43F0000000000000);
    CheckReader('9223372036854775807',ObjectReader,1,High(Int64));
    CheckReader('9223372036854775808',ObjectReader,1,0,True);
    CheckReader('1.5',ObjectReader,1,0,True);
    CheckReader('1e0',ObjectReader,2,0,True);
    CheckReader('"2147483648"',ObjectReader,2,0,True);
    CheckReader('"42"',ObjectReader,1,42);
    CheckReader('"1.5"',ObjectReader,0,$3FF8000000000000);
    CheckReader('null',ObjectReader,1,0);
    CheckReader('null',ObjectReader,0,0);
    CheckReader('-1',ObjectReader,3,0,True);
    CheckReader('"-1"',ObjectReader,3,0,True);
    CheckReader('1.5',ObjectReader,3,0,True);
    CheckReader('18446744073709551615',ObjectReader,3,High(UInt64));
    CheckReader('"18446744073709551615"',ObjectReader,3,High(UInt64));
    CheckReader('5000000000',ObjectReader,4,0);
    CheckReader('18446744073709551615',ObjectReader,4,0);
    CheckNavigation(ObjectReader);
  end;
  // The text reader retains Delphi's explicit 32-bit narrowing of integer tokens.
  CheckReader('2147483648',False,2,$80000000);
  CheckSerializer;
  WriteLn('JSON_NUMERIC_BOUNDARIES_PASS');
end.
