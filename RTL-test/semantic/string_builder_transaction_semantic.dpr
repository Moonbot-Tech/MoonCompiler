program string_builder_transaction_semantic;

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

type
  TUnicodeBuilderProbe = class(TStringBuilder)
  public
    procedure AppendSelf(StartIndex, CharCount: Integer);
    procedure InsertSelf(Index, StartIndex, CharCount: Integer);
    procedure LoadExact(const Value: UnicodeString; Capacity: Integer = -1);
    procedure StoreSpare(Index: Integer; Value: WideChar);
  end;

  TAnsiBuilderProbe = class(TAnsiStringBuilder)
  public
    procedure AppendSelf(StartIndex, CharCount: Integer);
    procedure InsertSelf(Index, StartIndex, CharCount: Integer);
    procedure LoadExact(const Value: AnsiString);
  end;

  TTrackingBuilder = class(TStringBuilder)
  public
    AppendCalls: Integer;
    InsertCalls: Integer;
  protected
    procedure DoAppend(const S: UnicodeString); override;
    procedure DoInsert(Index: Integer; const AValue: UnicodeString); override;
  end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    begin
      WriteLn('FAIL ',MessageText);
      Halt(1);
    end;
end;

procedure TUnicodeBuilderProbe.AppendSelf(StartIndex, CharCount: Integer);
begin
  DoAppend(FData,StartIndex,CharCount);
end;

procedure TUnicodeBuilderProbe.InsertSelf(Index, StartIndex,
  CharCount: Integer);
begin
  DoInsert(Index,FData,StartIndex,CharCount);
end;

procedure TUnicodeBuilderProbe.LoadExact(const Value: UnicodeString;
  Capacity: Integer);
begin
  if Capacity<0 then
    Capacity:=System.Length(Value);
  System.SetLength(FData,Capacity);
  FLength:=System.Length(Value);
  if FLength>0 then
    Move(Value[1],FData[0],FLength*SizeOf(WideChar));
end;

procedure TUnicodeBuilderProbe.StoreSpare(Index: Integer; Value: WideChar);
begin
  FData[Index]:=Value;
end;

procedure TAnsiBuilderProbe.AppendSelf(StartIndex, CharCount: Integer);
begin
  DoAppend(FData,StartIndex,CharCount);
end;

procedure TAnsiBuilderProbe.InsertSelf(Index, StartIndex, CharCount: Integer);
begin
  DoInsert(Index,FData,StartIndex,CharCount);
end;

procedure TAnsiBuilderProbe.LoadExact(const Value: AnsiString);
begin
  System.SetLength(FData,System.Length(Value));
  FLength:=System.Length(Value);
  if FLength>0 then
    Move(Value[1],FData[0],FLength*SizeOf(AnsiChar));
end;

procedure TTrackingBuilder.DoAppend(const S: UnicodeString);
begin
  Inc(AppendCalls);
  inherited DoAppend(S);
end;

procedure TTrackingBuilder.DoInsert(Index: Integer;
  const AValue: UnicodeString);
begin
  Inc(InsertCalls);
  inherited DoInsert(Index,AValue);
end;

procedure CheckUnicodeAlias;
var
  Builder: TUnicodeBuilderProbe;
begin
  Builder:=TUnicodeBuilderProbe.Create;
  try
    Builder.LoadExact('abcdef');
    Builder.InsertSelf(4,0,2);
    Check(Builder.ToString='abcdabef','Unicode alias before insertion');

    Builder.LoadExact('abcdef');
    Builder.InsertSelf(1,3,2);
    Check(Builder.ToString='adebcdef','Unicode alias after insertion');

    Builder.LoadExact('abcdef');
    Builder.InsertSelf(3,2,3);
    Check(Builder.ToString='abccdedef','Unicode alias crossing insertion');

    Builder.LoadExact('abcdef');
    Builder.AppendSelf(0,3);
    Check(Builder.ToString='abcdefabc','Unicode alias append after growth');

    Builder.LoadExact('abcdef',8);
    Builder.StoreSpare(6,'X');
    Builder.StoreSpare(7,'Y');
    Builder.InsertSelf(3,6,2);
    Check(Builder.ToString='abcXYdef','Unicode spare-capacity alias');
  finally
    Builder.Free;
  end;
end;

procedure CheckAnsiAlias;
var
  Builder: TAnsiBuilderProbe;
begin
  Builder:=TAnsiBuilderProbe.Create;
  try
    Builder.LoadExact(AnsiString('abcdef'));
    Builder.InsertSelf(3,2,3);
    Check(Builder.ToString=AnsiString('abccdedef'),
      'Ansi alias crossing insertion');
    Builder.LoadExact(AnsiString('abcdef'));
    Builder.AppendSelf(0,3);
    Check(Builder.ToString=AnsiString('abcdefabc'),
      'Ansi alias append after growth');
  finally
    Builder.Free;
  end;
end;

procedure CheckBoundaries;
var
  Builder,EmptyBuilder,OtherEmptyBuilder: TStringBuilder;
  C: Char;
  Raised: Boolean;
begin
  Builder:=TStringBuilder.Create('abc');
  EmptyBuilder:=TStringBuilder.Create(0);
  OtherEmptyBuilder:=TStringBuilder.Create(0);
  try
    Raised:=False;
    try
      C:=Builder[Builder.Length];
      if C=#0 then
        ;
    except
      on ERangeError do
        Raised:=True;
    end;
    Check(Raised,'Chars getter accepted Length');

    Raised:=False;
    try
      Builder[Builder.Length]:='x';
    except
      on ERangeError do
        Raised:=True;
    end;
    Check(Raised,'Chars setter accepted Length');
    Check(Builder.ToString='abc','failed Chars access changed value');

    Builder.Insert(Builder.Length,UnicodeString('d'));
    Check(Builder.ToString='abcd','insert at Length');
    Builder.Insert(Builder.Length,UnicodeString(''));
    Check(Builder.ToString='abcd','empty insert at Length');

    Raised:=False;
    try
      Builder.Insert(High(Integer),UnicodeString(''));
    except
      on ERangeError do
        Raised:=True;
    end;
    Check(Raised,'empty insert ignored invalid index');
    Check(Builder.ToString='abcd','failed insert changed value');

    Raised:=False;
    try
      Builder.Replace('x','y',Builder.Length,1);
    except
      on ERangeError do
        Raised:=True;
    end;
    Check(Raised,'char Replace accepted range past end');
    Builder.Replace('x','y',High(Integer),0);
    Check(Builder.ToString='abcd','zero char Replace changed value');

    Raised:=False;
    try
      Builder.Replace('','x');
    except
      on EArgumentException do
        Raised:=True;
    end;
    Check(Raised,'empty Replace source was not rejected safely');
    Check(Builder.ToString='abcd','failed Replace changed value');

    Builder.Replace('b','');
    Check(Builder.ToString='acd','empty Replace destination');
    Check(EmptyBuilder.Equals(OtherEmptyBuilder),
      'empty builders are not equal');
    for C in EmptyBuilder do
      Check(False,'empty enumerator yielded a character');
  finally
    OtherEmptyBuilder.Free;
    EmptyBuilder.Free;
    Builder.Free;
  end;
end;

procedure CheckRepeatAndVirtualContract;
var
  Builder: TStringBuilder;
  Raised: Boolean;
  Tracking: TTrackingBuilder;
begin
  Builder:=TStringBuilder.Create('ab');
  try
    Builder.Append('x',0);
    Builder.Append('x',-1);
    Builder.Insert(-1,UnicodeString('x'),0);
    Builder.Insert(-1,UnicodeString('x'),-1);
    Check(Builder.ToString='ab','nonpositive repeat was not a no-op');
    Builder.Append('x',4);
    Check(Builder.ToString='abxxxx','char repeat');
    Builder.Insert(2,UnicodeString('yz'),3);
    Check(Builder.ToString='abyzyzyzxxxx','string repeat');
  finally
    Builder.Free;
  end;

  Builder:=TStringBuilder.Create(4,8);
  try
    Builder.Append(UnicodeString('ab'));
    Raised:=False;
    try
      Builder.Append(UnicodeString('1234567'));
    except
      on ERangeError do
        Raised:=True;
    end;
    Check(Raised,'string Append accepted MaxCapacity overflow');
    Check(Builder.ToString='ab','failed string Append changed value');
    Raised:=False;
    try
      Builder.Insert(1,UnicodeString('xyz'),4);
    except
      on ERangeError do
        Raised:=True;
    end;
    Check(Raised,'repeat Insert accepted MaxCapacity overflow');
    Check(Builder.ToString='ab','failed repeat Insert changed value');
    Raised:=False;
    try
      Builder.Append('x',7);
    except
      on ERangeError do
        Raised:=True;
    end;
    Check(Raised,'char repeat accepted MaxCapacity overflow');
    Check(Builder.ToString='ab','failed char repeat changed value');
  finally
    Builder.Free;
  end;

  Tracking:=TTrackingBuilder.Create;
  try
    Tracking.Append(UnicodeString('ab'));
    Check(Tracking.AppendCalls=1,'string Append bypassed descendant');
    Tracking.Append('x',0);
    Check(Tracking.AppendCalls=2,'zero char repeat bypassed descendant');
    Tracking.Insert(0,UnicodeString('y'),2);
    Check(Tracking.InsertCalls=2,'repeat Insert changed descendant calls');
    Tracking.Insert(High(Integer),UnicodeString('z'),0);
    Check(Tracking.InsertCalls=2,'zero repeat called descendant');
    Tracking.Append(Int64(-1));
    Tracking.Append(UInt64(2));
    Check(Tracking.AppendCalls=4,'integer Append bypassed descendant');
  finally
    Tracking.Free;
  end;
end;

procedure CheckIntegerSinks;
var
  AnsiBuilder: TAnsiStringBuilder;
  Builder: TStringBuilder;
begin
  Builder:=TStringBuilder.Create;
  try
    Builder.Append(Low(Int64));
    Builder.Append(',');
    Builder.Append(High(Int64));
    Builder.Append(',');
    Builder.Append(High(UInt64));
    Builder.Append(',');
    Builder.Append(Cardinal(4294967295));
    Check(Builder.ToString=
      '-9223372036854775808,9223372036854775807,18446744073709551615,4294967295',
      'Unicode integer sink');
  finally
    Builder.Free;
  end;

  AnsiBuilder:=TAnsiStringBuilder.Create;
  try
    AnsiBuilder.Append(Low(Int64));
    AnsiBuilder.Append(AnsiChar(','));
    AnsiBuilder.Append(High(UInt64));
    Check(AnsiBuilder.ToString=AnsiString(
      '-9223372036854775808,18446744073709551615'),
      'Ansi integer sink');
  finally
    AnsiBuilder.Free;
  end;
end;

begin
  CheckUnicodeAlias;
  CheckAnsiAlias;
  CheckBoundaries;
  CheckRepeatAndVirtualContract;
  CheckIntegerSinks;
  WriteLn('STRING_BUILDER_TRANSACTION_OK');
end.
