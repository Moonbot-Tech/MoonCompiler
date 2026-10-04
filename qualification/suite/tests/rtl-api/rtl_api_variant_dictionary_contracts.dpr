program rtl_api_variant_dictionary_contracts;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

uses
  {$ifdef unix}cwstring,{$endif}
  SysUtils,
  Variants,
  Generics.Defaults,
  Generics.Collections;

procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    begin
      WriteLn('FAIL ',AName);
      Halt(1);
    end;
end;

procedure CheckEquivalent(const Name: string; const Left,Right: Variant);
var
  Comparer: IEqualityComparer<Variant>;
begin
  Comparer:=TEqualityComparer<Variant>.Default;
  Check(Comparer.Equals(Left,Right),Name+'-equals');
  Check(Comparer.GetHashCode(Left)=Comparer.GetHashCode(Right),Name+'-hash');
end;

procedure CheckDistinct(const Name: string; const Left,Right: Variant);
var
  Comparer: IEqualityComparer<Variant>;
begin
  Comparer:=TEqualityComparer<Variant>.Default;
  Check(not Comparer.Equals(Left,Right),Name+'-distinct');
end;

procedure CheckDictionary;
var
  Dictionary: TDictionary<Variant,Integer>;
  First,Second: Variant;
  Index,Value: Integer;
begin
  First:=Copy('alpha-1',1,5);
  Second:=Copy('xalpha',2,5);
  Check(Pointer(UnicodeString(First))<>Pointer(UnicodeString(Second)),
    'independent-string-storage');
  CheckEquivalent('independent-strings',First,Second);
  CheckEquivalent('integer-int64',Integer(1),Int64(1));
  CheckEquivalent('integer-double',Integer(1),Double(1));
  CheckEquivalent('integer-single',Integer(1),Single(1));
  CheckEquivalent('integer-currency',Integer(1),Currency(1));
  CheckDistinct('integer-unicode',Integer(1),UnicodeString('1'));
  CheckDistinct('integer-leading-zero',Integer(1),UnicodeString('01'));
  CheckDistinct('boolean-minus-one',Boolean(True),Integer(-1));
  CheckDistinct('boolean-zero',Boolean(False),Integer(0));
  CheckDistinct('string-leading-zero',UnicodeString('1'),UnicodeString('01'));
  CheckEquivalent('empty-unicode',UnicodeString(''),UnicodeString(''));

  Dictionary:=TDictionary<Variant,Integer>.Create;
  try
    Dictionary.Add(First,73);
    Check(Dictionary.TryGetValue(Second,Value),'dictionary-lookup');
    Check(Value=73,'dictionary-value');
    Dictionary.Remove(Second);
    Check(Dictionary.Count=0,'dictionary-remove-count');

    Dictionary.Add(Boolean(True),11);
    Dictionary.Add(Integer(-1),12);
    Dictionary.Add(UnicodeString('1'),13);
    Dictionary.Add(Integer(1),14);
    Check(Dictionary.Count=4,'dictionary-domain-count');
    Check(Dictionary[Boolean(True)]=11,'dictionary-boolean-value');
    Check(Dictionary[Int64(-1)]=12,'dictionary-negative-integer-value');
    Check(Dictionary[WideString('1')]=13,'dictionary-string-value');
    Check(Dictionary[Double(1)]=14,'dictionary-number-value');
    Dictionary.Clear;

    for Index:=0 to 511 do
      Dictionary.Add(Integer(Index),Index*3);
    for Index:=0 to 511 do
      begin
        Check(Dictionary.TryGetValue(Int64(Index),Value),'dictionary-rehash-lookup');
        Check(Value=Index*3,'dictionary-rehash-value');
      end;
  finally
    Dictionary.Free;
  end;
end;

procedure CheckScalarPairs;
var
  Left,Right: Variant;
  LeftBits,RightBits: QWord;
  LeftDouble,RightDouble: Double;
begin
  CheckEquivalent('boolean',Boolean(True),Boolean(True));
  CheckEquivalent('currency',Currency(123.4567),Currency(123.4567));
  CheckEquivalent('binary-currency-double',Currency(1.25),Double(1.25));
  CheckDistinct('decimal-currency-double',Currency(0.1),Double(0.1));
  CheckEquivalent('uint64',UInt64(High(Int64))+1,UInt64(High(Int64))+1);
  CheckEquivalent('uint64-exact-double',UInt64(1) shl 63,Double(UInt64(1) shl 63));
  CheckDistinct('uint64-rounded-double',High(UInt64),Double(High(UInt64)));
  LeftBits:=$0000000000000000;
  RightBits:=$8000000000000000;
  Move(LeftBits,LeftDouble,SizeOf(LeftBits));
  Move(RightBits,RightDouble,SizeOf(RightBits));
  Left:=LeftDouble;
  Right:=RightDouble;
  CheckEquivalent('signed-zero',Left,Right);
  LeftBits:=$7ff8000000000001;
  RightBits:=$7ff8000000000010;
  Move(LeftBits,LeftDouble,SizeOf(LeftBits));
  Move(RightBits,RightDouble,SizeOf(RightBits));
  Left:=LeftDouble;
  Right:=RightDouble;
  CheckEquivalent('nan-payloads',Left,Right);
  Left:=VarAsType(45678.25,varDate);
  Right:=VarAsType(45678.25,varDate);
  CheckEquivalent('date',Left,Right);
  Left:=AnsiString('charlie');
  Right:=Copy(AnsiString('xcharlie'),2,7);
  CheckEquivalent('ansi-string',Left,Right);
  CheckEquivalent('ansi-unicode-string',Left,UnicodeString('charlie'));
  Left:=WideString('delta');
  Right:=Copy(WideString('xdelta'),2,5);
  CheckEquivalent('wide-string',Left,Right);
end;

procedure CheckCanonicalTextDomain;
var
  FirstBytes,SecondBytes: RawByteString;
  First,Second,UnicodeValue: Variant;
  Comparer: IEqualityComparer<Variant>;
  Dictionary: TDictionary<Variant,Integer>;
  Value: Integer;
begin
  SetLength(FirstBytes,2);
  FirstBytes[1]:=AnsiChar($81);
  FirstBytes[2]:=AnsiChar($e0);
  SetLength(SecondBytes,2);
  SecondBytes[1]:=AnsiChar($87);
  SecondBytes[2]:=AnsiChar($90);
  SetCodePage(FirstBytes,932,False);
  SetCodePage(SecondBytes,932,False);
  First:=FirstBytes;
  Second:=SecondBytes;
  UnicodeValue:=UnicodeString(FirstBytes);
  Check(UnicodeString(First)=UnicodeString(Second),'canonical-text-control');

  Comparer:=TEqualityComparer<Variant>.Default;
  Check(Comparer.Equals(First,UnicodeValue),'canonical-text-first-unicode');
  Check(Comparer.Equals(UnicodeValue,Second),'canonical-text-unicode-second');
  Check(Comparer.Equals(First,Second),'canonical-text-transitive');
  Check(Comparer.GetHashCode(First)=Comparer.GetHashCode(Second),
    'canonical-text-hash');

  Dictionary:=TDictionary<Variant,Integer>.Create;
  try
    Dictionary.Add(First,11);
    Check(Dictionary.TryGetValue(Second,Value),'canonical-text-lookup');
    Check(Value=11,'canonical-text-value');
    Dictionary.AddOrSetValue(Second,22);
    Check(Dictionary.Count=1,'canonical-text-count');
    Check(Dictionary[UnicodeValue]=22,'canonical-text-update');
  finally
    Dictionary.Free;
  end;
end;

procedure CheckByRefPairs;
var
  StoredInteger: Integer;
  StoredString: UnicodeString;
  StoredVariant: Variant;
  IntegerRef,StringRef,VariantRef: Variant;
  Dictionary: TDictionary<Variant,Integer>;
begin
  StoredInteger:=42;
  StoredString:='by-reference';
  StoredVariant:=Double(42);
  TVarData(IntegerRef).vType:=varInteger or varByRef;
  TVarData(IntegerRef).vPointer:=@StoredInteger;
  TVarData(StringRef).vType:=varUString or varByRef;
  TVarData(StringRef).vPointer:=@StoredString;
  TVarData(VariantRef).vType:=varVariant or varByRef;
  TVarData(VariantRef).vPointer:=@TVarData(StoredVariant);
  CheckEquivalent('byref-integer',IntegerRef,Integer(42));
  CheckEquivalent('byref-unicode',StringRef,UnicodeString('by-reference'));
  CheckEquivalent('byref-variant',VariantRef,Int64(42));

  Dictionary:=TDictionary<Variant,Integer>.Create;
  try
    Dictionary.Add(Integer(42),7);
    Check(Dictionary[IntegerRef]=7,'byref-integer-lookup');
    Check(Dictionary[VariantRef]=7,'byref-variant-lookup');
    Dictionary.Add(UnicodeString('by-reference'),8);
    Check(Dictionary[StringRef]=8,'byref-unicode-lookup');
  finally
    Dictionary.Free;
  end;
end;

procedure CheckEquivalenceLaws;
var
  Values: array[0..17] of Variant;
  Comparer: IEqualityComparer<Variant>;
  I,J,K: Integer;
  Bits: QWord;
  Number: Double;
begin
  Values[0]:=Boolean(False);
  Values[1]:=Integer(0);
  Values[2]:=Double(0);
  Values[3]:=Boolean(True);
  Values[4]:=Integer(-1);
  Values[5]:=Integer(1);
  Values[6]:=Int64(1);
  Values[7]:=UInt64(1);
  Values[8]:=Single(1);
  Values[9]:=Double(1);
  Values[10]:=Currency(1);
  Values[11]:=UnicodeString('1');
  Values[12]:=UnicodeString('01');
  Values[13]:=Currency(0.1);
  Values[14]:=Double(0.1);
  Values[15]:=VarAsType(1.0,varDate);
  Bits:=$7ff8000000000001;
  Move(Bits,Number,SizeOf(Number));
  Values[16]:=Number;
  Bits:=$7ff8000000000042;
  Move(Bits,Number,SizeOf(Number));
  Values[17]:=Number;
  Comparer:=TEqualityComparer<Variant>.Default;
  for I:=0 to High(Values) do
    begin
      Check(Comparer.Equals(Values[I],Values[I]),'reflexive-'+IntToStr(I));
      for J:=0 to High(Values) do
        begin
          Check(Comparer.Equals(Values[I],Values[J])=
            Comparer.Equals(Values[J],Values[I]),
            'symmetric-'+IntToStr(I)+'-'+IntToStr(J));
          if Comparer.Equals(Values[I],Values[J]) then
            begin
              Check(Comparer.GetHashCode(Values[I])=Comparer.GetHashCode(Values[J]),
                'equal-hash-'+IntToStr(I)+'-'+IntToStr(J));
              for K:=0 to High(Values) do
                if Comparer.Equals(Values[J],Values[K]) then
                  Check(Comparer.Equals(Values[I],Values[K]),
                    'transitive-'+IntToStr(I)+'-'+IntToStr(J)+'-'+IntToStr(K));
            end;
        end;
    end;
end;

{$ifdef FPC}
procedure CheckExtendedComparer;
var
  Comparer: IExtendedEqualityComparer<Variant>;
  First,Second: Variant;
  LeftHashes,RightHashes: array[0..5] of UInt32;
  Index: Integer;
begin
  First:=Copy('bravo-1',1,5);
  Second:=Copy('xbravo',2,5);
  Comparer:=TExtendedEqualityComparer<Variant>.Default;
  FillChar(LeftHashes,SizeOf(LeftHashes),0);
  FillChar(RightHashes,SizeOf(RightHashes),0);
  LeftHashes[0]:=2;
  RightHashes[0]:=2;
  Comparer.GetHashList(First,@LeftHashes[0]);
  Comparer.GetHashList(Second,@RightHashes[0]);
  for Index:=0 to High(LeftHashes) do
    Check(LeftHashes[Index]=RightHashes[Index],
      'extended-hash-'+IntToStr(Index));
end;
{$endif}

begin
  CheckDictionary;
  CheckScalarPairs;
  CheckCanonicalTextDomain;
  CheckByRefPairs;
  CheckEquivalenceLaws;
  {$ifdef FPC}
  CheckExtendedComparer;
  {$endif}
  WriteLn('RTL_API_VARIANT_DICTIONARY_CONTRACTS_OK');
end.
