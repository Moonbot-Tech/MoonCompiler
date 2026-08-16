program generic_list_search_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Generics.Defaults,
  Generics.Collections;

type
  TSmallEnum = (seZero, seOne, seTwo);
  TThreeByteSet = set of 0..23;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('GENERIC_LIST_SEARCH_FAIL: '+AMessage);
end;

function AbsoluteCompare(const Left, Right: Integer): Integer;
var
  L, R: Integer;
begin
  L:=Abs(Left);
  R:=Abs(Right);
  if L<R then
    Result:=-1
  else if L>R then
    Result:=1
  else
    Result:=0;
end;

procedure CheckIntegerSearch;
var
  List: TList<Integer>;
begin
  List:=TList<Integer>.Create;
  try
    List.AddRange([Low(Integer),7,42,7,High(Integer)]);
    Check(List.IndexOf(Low(Integer))=0,'Integer low');
    Check(List.IndexOf(7)=1,'Integer first duplicate');
    Check(List.LastIndexOf(7)=3,'Integer last duplicate');
    Check(List.IndexOf(13)=-1,'Integer missing');
    Check(List.Remove(7)=1,'Integer remove index');
    Check((List.Count=4) and (List[1]=42) and (List.LastIndexOf(7)=2),
      'Integer remove contents');
  finally
    List.Free;
  end;
end;

procedure CheckOrdinalWidths;
var
  Bytes: TList<Byte>;
  Words: TList<Word>;
  Signed64: TList<Int64>;
  Unsigned64: TList<UInt64>;
  Enums: TList<TSmallEnum>;
  Bools: TList<Boolean>;
  Chars: TList<WideChar>;
  Sets: TList<TThreeByteSet>;
  SetValue: TThreeByteSet;
begin
  Bytes:=TList<Byte>.Create;
  Words:=TList<Word>.Create;
  Signed64:=TList<Int64>.Create;
  Unsigned64:=TList<UInt64>.Create;
  Enums:=TList<TSmallEnum>.Create;
  Bools:=TList<Boolean>.Create;
  Chars:=TList<WideChar>.Create;
  Sets:=TList<TThreeByteSet>.Create;
  try
    Bytes.AddRange([0,255]);
    Words.AddRange([0,65535]);
    Signed64.AddRange([Low(Int64),0,High(Int64)]);
    Unsigned64.AddRange([0,High(UInt64)]);
    Enums.AddRange([seZero,seTwo]);
    Bools.AddRange([False,True]);
    Chars.AddRange([WideChar(0),WideChar($0100),WideChar($ffff)]);
    Sets.Add([1,7,23]);
    Sets.Add([0,8,22]);
    Check(Bytes.IndexOf(255)=1,'Byte');
    Check(Words.IndexOf(65535)=1,'Word');
    Check(Signed64.IndexOf(High(Int64))=2,'Int64');
    Check(Unsigned64.IndexOf(High(UInt64))=1,'UInt64');
    Check(Enums.IndexOf(seTwo)=1,'enum');
    Check(Bools.IndexOf(True)=1,'Boolean');
    Check(Chars.IndexOf(WideChar($0100))=1,'WideChar');
    SetValue:=[0,8,22];
    Check(Sets.IndexOf(SetValue)=1,'non-power-of-two set fallback');
  finally
    Sets.Free;
    Chars.Free;
    Bools.Free;
    Enums.Free;
    Unsigned64.Free;
    Signed64.Free;
    Words.Free;
    Bytes.Free;
  end;
end;

procedure CheckComparerBoundaries;
var
  Custom: IComparer<Integer>;
  Integers: TList<Integer>;
  Strings: TList<UnicodeString>;
  Floats: TList<Double>;
  PositiveZero, NegativeZero: Double;
begin
  Custom:=TComparer<Integer>.Construct(@AbsoluteCompare);
  Integers:=TList<Integer>.Create(Custom);
  Strings:=TList<UnicodeString>.Create;
  Floats:=TList<Double>.Create;
  try
    Integers.AddRange([-4,-7]);
    Check(Integers.IndexOf(4)=0,'custom comparer is preserved');
    Check(Integers.LastIndexOf(7)=1,'custom reverse search');

    Strings.AddRange(['moon','Moon',UnicodeChar($042F)]);
    Check(Strings.IndexOf(UnicodeString('moon'))=0,'Unicode content equality');
    Check(Strings.IndexOf(UnicodeString('MOON'))=-1,'Unicode case sensitivity');
    Check(Strings.IndexOf(UnicodeString(UnicodeChar($042F)))=2,
      'Unicode non-ASCII equality');

    PositiveZero:=0.0;
    NegativeZero:=-PositiveZero;
    Floats.Add(PositiveZero);
    Check(Floats.IndexOf(NegativeZero)=0,'floating signed-zero comparer');
  finally
    Floats.Free;
    Strings.Free;
    Integers.Free;
    Custom:=nil;
  end;
end;

begin
  try
    CheckIntegerSearch;
    CheckOrdinalWidths;
    CheckComparerBoundaries;
    WriteLn('GENERIC_LIST_SEARCH_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
