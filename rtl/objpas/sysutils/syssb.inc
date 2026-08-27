{%MainUnit sysutils.pp}
{ TGenericStringBuilder }

constructor TGenericStringBuilder.Create;
begin
  Create(DefaultCapacity,Maxint);
end;

constructor TGenericStringBuilder.Create(const AValue: SBString; aCapacity: Integer);
begin
  Create(aCapacity,Maxint);
  if (system.Length(AValue)>0) then
    Append(AValue);
end;


constructor TGenericStringBuilder.Create(const AValue: SBString; StartIndex, Alength,
  aCapacity: Integer);
begin
  Create(Copy(AValue,StartIndex+1,Alength), aCapacity);
end;

constructor TGenericStringBuilder.Create(aCapacity, aMaxCapacity: Integer);
begin
  FMaxCapacity:=aMaxCapacity;
  Capacity:=aCapacity;
  FLength:=0;
end;

constructor TGenericStringBuilder.Create(aCapacity: Integer);
begin
  Create(aCapacity,MaxInt);
end;

constructor TGenericStringBuilder.Create(const AValue: SBString);
begin
  Create(aValue,DefaultCapacity);
end;

{ Enumerator }

function TGenericStringBuilder.TCharEnumerator.GetCurrent: SBChar;
begin
  Result := FCurrentPosition^;
  Inc(FCurrentPosition);
end;

function TGenericStringBuilder.TCharEnumerator.MoveNext: Boolean;
begin
  Result := FCurrentPosition < FEndPosition;
end;

function TGenericStringBuilder.GetEnumerator: TCharEnumerator;
var
  StartPosition: PSBChar;
begin
  if FLength=0 then
    StartPosition:=nil
  else
    StartPosition:=@FData[0];
  Result.FCurrentPosition := StartPosition;
  Result.FEndPosition := StartPosition + Length;
end;

{ Property getter/setter }

function TGenericStringBuilder.GetLength: Integer;
begin
  Result:=FLength;
end;

function TGenericStringBuilder.GetCapacity: Integer;
begin
  Result:=System.Length(FData);
end;

function TGenericStringBuilder.GetC(Index: Integer): SBChar;
begin
  CheckNegative(Index,'Index');
  CheckRange(Index,1,Length);
  Result:=FData[Index];
end;

procedure TGenericStringBuilder.SetC(Index: Integer; AValue: SBChar);
begin
  CheckNegative(Index,'Index');
  CheckRange(Index,1,Length);
  FData[Index]:=AValue;
end;

procedure TGenericStringBuilder.SetLength(AValue: Integer);

begin
  CheckNegative(AValue,'AValue');
  CheckRange(AValue,0,MaxCapacity);
  if AValue>System.Length(FData) then
    GrowTo(AValue);
  Flength:=AValue;
end;

{ Check functions }



procedure TGenericStringBuilder.CheckRange(Idx, Count, MaxLen: Integer);

begin
  if (Idx<0) or (Idx>MaxLen) or (Count<0) or (Count>MaxLen-Idx) then
    Raise ERangeError.CreateFmt(SListIndexError,[Idx]);
end;


procedure TGenericStringBuilder.CheckNegative(const AValue: Integer;
  const AName: SBString);

begin
  if (AValue<0) then
    Raise ERangeError.CreateFmt(SParamIsNegative,[AName])
end;

function TGenericStringBuilder.AliasedDataOffset(const AValue: TSBCharArray;
  StartIndex, SBCharCount: Integer): Integer;
var
  DataEnd, DataStart, SourceEnd, SourceStart: PtrUInt;
begin
  Result:=-1;
  if (SBCharCount=0) or (System.Length(FData)=0) then
    Exit;
  DataStart:=PtrUInt(@FData[0]);
  DataEnd:=DataStart+PtrUInt(System.Length(FData))*SizeOf(SBChar);
  SourceStart:=PtrUInt(@AValue[StartIndex]);
  SourceEnd:=SourceStart+PtrUInt(SBCharCount)*SizeOf(SBChar);
  if (SourceStart>=DataStart) and (SourceEnd<=DataEnd) then
    Result:=(SourceStart-DataStart) div SizeOf(SBChar);
end;

procedure TGenericStringBuilder.PrepareGap(Index, Added: Integer;
  out OldLength: Integer);
var
  NewLength: Integer;
begin
  OldLength:=FLength;
  if Added=0 then
    Exit;
  if (Added<0) or (Added>FMaxCapacity-OldLength) then
    Raise ERangeError.CreateFmt(SListIndexError,[Int64(OldLength)+Added]);
  NewLength:=OldLength+Added;
  if NewLength>System.Length(FData) then
    GrowTo(NewLength);
  if OldLength>Index then
    Move(FData[Index],FData[Index+Added],
      (OldLength-Index)*SizeOf(SBChar));
end;

{  These do the actual Appending/Inserting }

procedure TGenericStringBuilder.DoAppend(const S: {$IFDEF SBUNICODE}SBString{$ELSE}RawByteString{$ENDIF});

Var
  OldLength,SL : Integer;

begin
  SL:=System.Length(S);
  if SL=0 then
    Exit;
  PrepareGap(FLength,SL,OldLength);
  Move(S[1],FData[OldLength],SL*SizeOf(SBChar));
  FLength:=OldLength+SL;
end;

procedure TGenericStringBuilder.DoAppend(const AValue: TSBCharArray; Idx, aCount: Integer
  );

Var
  AliasedOffset,OldLength : Integer;
  Snapshot: TSBCharArray;

begin
  CheckRange(Idx,aCount,System.Length(AValue));
  if aCount=0 then
    Exit;
  if aCount>FMaxCapacity-FLength then
    Raise ERangeError.CreateFmt(SListIndexError,[Int64(FLength)+aCount]);
  AliasedOffset:=AliasedDataOffset(AValue,Idx,aCount);
  Snapshot:=nil;
  if (AliasedOffset>=0) and (AliasedOffset+aCount>FLength) and
     (aCount>System.Length(FData)-FLength) then
    begin
    System.SetLength(Snapshot,aCount);
    Move(AValue[Idx],Snapshot[0],aCount*SizeOf(SBChar));
    end;
  PrepareGap(FLength,aCount,OldLength);
  if System.Length(Snapshot)>0 then
    Move(Snapshot[0],FData[OldLength],aCount*SizeOf(SBChar))
  else if AliasedOffset>=0 then
    Move(FData[AliasedOffset],FData[OldLength],aCount*SizeOf(SBChar))
  else
    Move(AValue[Idx],FData[OldLength],aCount*SizeOf(SBChar));
  FLength:=OldLength+aCount;
end;

procedure TGenericStringBuilder.DoInsert(Index: Integer; const AValue: SBString);

Var
  LV,OldLength : Integer;

begin
  CheckRange(Index,0,FLength);
  LV:=System.Length(AValue);
  if LV=0 then
    Exit;
  PrepareGap(Index,LV,OldLength);
  Move(AValue[1],FData[Index],LV*SizeOf(SBChar));
  FLength:=OldLength+LV;
end;

procedure TGenericStringBuilder.DoInsert(Index: Integer; const AValue: TSBCharArray;
  StartIndex, SBCharCount: Integer);

Var
  AliasedOffset,OldLength,PrefixLength : Integer;
  Snapshot: TSBCharArray;

begin
  CheckRange(Index,0,FLength);
  CheckNegative(StartIndex,'StartIndex');
  CheckNegative(SBCharCount,'SBCharCount');
  CheckRange(StartIndex,SBCharCount,System.Length(AValue));
  if SBCharCount=0 then
    Exit;
  if SBCharCount>FMaxCapacity-FLength then
    Raise ERangeError.CreateFmt(SListIndexError,
      [Int64(FLength)+SBCharCount]);
  AliasedOffset:=AliasedDataOffset(AValue,StartIndex,SBCharCount);
  Snapshot:=nil;
  if (AliasedOffset>=0) and (AliasedOffset+SBCharCount>FLength) then
    begin
    System.SetLength(Snapshot,SBCharCount);
    Move(AValue[StartIndex],Snapshot[0],SBCharCount*SizeOf(SBChar));
    end;
  PrepareGap(Index,SBCharCount,OldLength);
  if System.Length(Snapshot)>0 then
    Move(Snapshot[0],FData[Index],SBCharCount*SizeOf(SBChar))
  else if AliasedOffset<0 then
    Move(AValue[StartIndex],FData[Index],SBCharCount*SizeOf(SBChar))
  else if AliasedOffset+SBCharCount<=Index then
    Move(FData[AliasedOffset],FData[Index],SBCharCount*SizeOf(SBChar))
  else if AliasedOffset>=Index then
    Move(FData[AliasedOffset+SBCharCount],FData[Index],
      SBCharCount*SizeOf(SBChar))
  else
    begin
    PrefixLength:=Index-AliasedOffset;
    Move(FData[AliasedOffset],FData[Index],PrefixLength*SizeOf(SBChar));
    Move(FData[Index+SBCharCount],FData[Index+PrefixLength],
      (SBCharCount-PrefixLength)*SizeOf(SBChar));
    end;
  FLength:=OldLength+SBCharCount;
end;

{ Public routines for appending }

function TGenericStringBuilder.Append(const AValue: UInt64): TGenericStringBuilder;
begin
  DoAppend(IntToStr(AValue));
  Result:=self;
end;

function TGenericStringBuilder.Append(const AValue: TSBCharArray): TGenericStringBuilder;

var
  I,L: Integer;

begin
  I:=-1;
  L:=System.Length(AValue);
  If L=0 then
    Exit(Self);
  Repeat
    Inc(I);
  Until (I>=L) or (AValue[I]=#0);
  DoAppend(AValue,0,I);
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: Single): TGenericStringBuilder;
begin
  DoAppend(FloatToStr(AValue));
  Result:=self;
end;

function TGenericStringBuilder.Append(const AValue: Word): TGenericStringBuilder;
begin
  Append(IntToStr(AValue));
  Result:=self;
end;

function TGenericStringBuilder.Append(const AValue: Cardinal): TGenericStringBuilder;
begin
  DoAppend(IntToStr(AValue));
  Result:=self;
end;

function TGenericStringBuilder.Append(const AValue: SBChar; RepeatCount: Integer
  ): TGenericStringBuilder;
var
  OldLength: Integer;
begin
  if ClassType<>TGenericStringBuilder then
    begin
    DoAppend(StringOfChar(AValue,RepeatCount));
    Exit(Self);
    end;
  if RepeatCount<=0 then
    Exit(Self);
  PrepareGap(FLength,RepeatCount,OldLength);
{$IFDEF SBUNICODE}
  FillWord(FData[OldLength],RepeatCount,Word(AValue));
{$ELSE}
  FillChar(FData[OldLength],RepeatCount,AValue);
{$ENDIF}
  FLength:=OldLength+RepeatCount;
  Result:=Self;
end;


function TGenericStringBuilder.Append(const AValue: Shortint): TGenericStringBuilder;
begin
  DoAppend(IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: SBChar): TGenericStringBuilder;

Var
  NewLen : Integer;

begin
  { going through DoAppend would build a one-char heap string per call;
    a single character goes into the buffer directly (Delphi does the
    same - its char append never touches the string overload) }
  if FLength=FMaxCapacity then
    Raise ERangeError.CreateFmt(SListIndexError,[Int64(FLength)+1]);
  NewLen:=FLength+1;
  if NewLen>System.Length(FData) then
    GrowTo(NewLen);
  FData[FLength]:=AValue;
  FLength:=NewLen;
  Result:=Self;
end;

{$IFDEF SBUNICODE}
function TGenericStringBuilder.Append(const AValue: AnsiChar): TGenericStringBuilder;
begin
  Result:=Append(WideChar(AValue));
end;
{$ELSE}
function TGenericStringBuilder.Append(const AValue: WideChar): TGenericStringBuilder;
begin
  // We don't know what the target encoding is ?
  DoAppend(AnsiChar(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: UnicodeString): TGenericStringBuilder;
begin
  // We don't know what the target encoding is ?
  DoAppend(AnsiString(AValue));
  Result:=Self;
end;

{$ENDIF}

function TGenericStringBuilder.Append(const AValue: Currency): TGenericStringBuilder;
begin
  DoAppend(CurrToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: Boolean): TGenericStringBuilder;
begin
  DoAppend(BoolToStr(AValue, True));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: Byte): TGenericStringBuilder;
begin
  DoAppend(IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: Double): TGenericStringBuilder;
begin
  DoAppend(FloatToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: Int64): TGenericStringBuilder;
begin
  DoAppend(IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: TObject): TGenericStringBuilder;
begin
  DoAppend(AValue.ToString);
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: Smallint): TGenericStringBuilder;
begin
  DoAppend(IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: LongInt): TGenericStringBuilder;
begin
  DoAppend(IntToStr(AValue));
  Result:=Self;
end;

Function TGenericStringBuilder.Append(const AValue: TSBCharArray; StartIndex, SBCharCount: Integer): TGenericStringBuilder;

begin
  DoAppend(AValue,StartIndex,SBCharCount);
  Result:=Self;
end;

Function TGenericStringBuilder.Append(const AValue: SBString; StartIndex, Count: Integer): TGenericStringBuilder;
var
  OldLength: Integer;
begin
  CheckRange(StartIndex,Count,System.Length(AValue));
  if ClassType<>TGenericStringBuilder then
    begin
    DoAppend(Copy(AValue,StartIndex+1,Count));
    Exit(Self);
    end;
  if Count=0 then
    Exit(Self);
  PrepareGap(FLength,Count,OldLength);
  Move(AValue[StartIndex+1],FData[OldLength],Count*SizeOf(SBChar));
  FLength:=OldLength+Count;
  Result:=Self;
end;

function TGenericStringBuilder.Append(const AValue: PSBChar): TGenericStringBuilder;
begin
  DoAppend(AnsiString(AValue));
  Result:=Self;
end;

{$IFDEF SBUNICODE}
function TGenericStringBuilder.Append(const AValue: SBString): TGenericStringBuilder;

Var
  OldLength,SL : Integer;

begin
  if ClassType<>TGenericStringBuilder then
    begin
    DoAppend(AValue);
    Exit(Self);
    end;
  SL:=System.Length(AValue);
  if SL=0 then
    Exit(Self);
  PrepareGap(FLength,SL,OldLength);
  Move(AValue[1],FData[OldLength],SL*SizeOf(SBChar));
  FLength:=OldLength+SL;
  Result:=Self;
end;
{$ENDIF}

function TGenericStringBuilder.Append(const AValue: RawByteString): TGenericStringBuilder;
begin
  {$IFDEF SBUNICODE}
  DoAppend(SBString(AValue));
  {$ELSE}
  DoAppend(AValue);
  {$ENDIF}
  Result:=Self;
end;

function TGenericStringBuilder.AppendFormat(const Fmt: SBString;
  const Args: array of const): TGenericStringBuilder;
begin
  DoAppend(Format(Fmt,Args));
  Result:=Self;
end;

function TGenericStringBuilder.Append(const Fmt: SBString;
  const Args: array of const): TGenericStringBuilder;
begin
  DoAppend(Format(Fmt,Args));
  Result:=Self;
end;

function TGenericStringBuilder.AppendLine: TGenericStringBuilder;
begin
  DoAppend(sLineBreak);
  Result:=Self;
end;

function TGenericStringBuilder.AppendLine(const AValue: RawByteString): TGenericStringBuilder;
begin
  DoAppend(AValue);
  Result:=AppendLine();
end;

procedure TGenericStringBuilder.Clear;
begin
  Length:=0;
  Capacity:=DefaultCapacity;
end;


procedure TGenericStringBuilder.CopyTo(SourceIndex: Integer;
  Var Destination: TSBCharArray; DestinationIndex: Integer; Count: Integer);

begin
  CheckNegative(Count,'Count');
  CheckNegative(DestinationIndex,'DestinationIndex');
  CheckRange(DestinationIndex,Count,System.Length(Destination));
  if Count>0 then
    begin
    CheckRange(SourceIndex,Count,Length);
    Move(FData[SourceIndex],Destination[DestinationIndex],Count * SizeOf(SBChar));
    end;
end;


function TGenericStringBuilder.EnsureCapacity(aCapacity: Integer): Integer;
begin
  CheckRange(aCapacity,0,MaxCapacity);
  if Capacity<aCapacity then
    Capacity:=aCapacity;
  Result:=Capacity;
end;

function TGenericStringBuilder.Equals(StringBuilder: TGenericStringBuilder): Boolean;
begin
  Result:=(StringBuilder<>nil);
  if Result then
    Result:=(Length=StringBuilder.Length)
             and (MaxCapacity=StringBuilder.MaxCapacity)
             and ((Length=0) or
               CompareMem(@FData[0],@StringBuilder.FData[0],
                 Length*SizeOf(SBChar)));
end;

procedure TGenericStringBuilder.Grow;

var
  NewCapacity: SizeInt;

begin
  if Capacity>MaxCapacity div 2 then
    NewCapacity:=MaxCapacity
  else
    NewCapacity:=Capacity*2;
  Capacity:=NewCapacity;
end;

procedure TGenericStringBuilder.GrowTo(aMinCapacity: Integer);

var
  NewCapacity: SizeInt;

begin
  { same contract the Length setter always had: growing past MaxCapacity
    raises the range error with the requested length }
  if aMinCapacity>FMaxCapacity then
    Raise ERangeError.CreateFmt(SListIndexError,[aMinCapacity]);
  NewCapacity:=System.Length(FData);
  if NewCapacity=0 then
    NewCapacity:=DefaultCapacity;
  while NewCapacity<aMinCapacity do
    if NewCapacity>FMaxCapacity div 2 then
      begin
        NewCapacity:=FMaxCapacity;
        break;
      end
    else
      NewCapacity:=NewCapacity*2;
  Capacity:=NewCapacity;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: TObject
  ): TGenericStringBuilder;
begin
  DoInsert(Index,AValue.ToString());
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Int64
  ): TGenericStringBuilder;
begin
  DoInsert(Index,IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Single
  ): TGenericStringBuilder;
begin
  DoInsert(Index,FloatToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: SBString
  ): TGenericStringBuilder;

begin
  DoInsert(Index,AValue);
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Word
  ): TGenericStringBuilder;
begin
  DoInsert(Index,IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Shortint
  ): TGenericStringBuilder;
begin
  DoInsert(Index, IntToStr(AValue));
  Result:=Self;
end;


function TGenericStringBuilder.Insert(Index: Integer; const AValue: Currency
  ): TGenericStringBuilder;
begin
  DoInsert(Index,CurrToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: SBChar
  ): TGenericStringBuilder;
begin
  DoInsert(Index,AValue);
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Byte
  ): TGenericStringBuilder;
begin
  DoInsert(Index,IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Double
  ): TGenericStringBuilder;
begin
  DoInsert(Index,FloatToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: LongInt
  ): TGenericStringBuilder;
begin
  DoInsert(Index,IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Smallint
  ): TGenericStringBuilder;
begin
  DoInsert(Index,IntToStr(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Boolean
  ): TGenericStringBuilder;
begin
  DoInsert(Index,BoolToStr(AValue,True));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: SBString;
  const aRepeatCount: Integer): TGenericStringBuilder;
var
  Added,Copied,CopyCount,I,OldLength,ValueLength: Integer;
begin
  if ClassType<>TGenericStringBuilder then
    begin
    for I:=0 to aRepeatCount-1 do
      DoInsert(Index,AValue);
    Exit(Self);
    end;
  if aRepeatCount<=0 then
    Exit(Self);
  CheckRange(Index,0,FLength);
  ValueLength:=System.Length(AValue);
  if ValueLength=0 then
    Exit(Self);
  if ValueLength>(FMaxCapacity-FLength) div aRepeatCount then
    Raise ERangeError.CreateFmt(SListIndexError,
      [Int64(FLength)+Int64(ValueLength)*aRepeatCount]);
  Added:=ValueLength*aRepeatCount;
  PrepareGap(Index,Added,OldLength);
  Move(AValue[1],FData[Index],ValueLength*SizeOf(SBChar));
  Copied:=ValueLength;
  while Copied<Added do
    begin
    CopyCount:=Copied;
    if CopyCount>Added-Copied then
      CopyCount:=Added-Copied;
    Move(FData[Index],FData[Index+Copied],CopyCount*SizeOf(SBChar));
    Inc(Copied,CopyCount);
    end;
  FLength:=OldLength+Added;
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: TSBCharArray
  ): TGenericStringBuilder;
begin
  DoInsert(Index,AValue,0,System.Length(AValue));
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: TSBCharArray;
  startIndex: Integer; SBCharCount: Integer): TGenericStringBuilder;
begin
  DoInsert(Index,AValue,StartIndex,SBCharCount);
  Result:=Self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: Cardinal
  ): TGenericStringBuilder;
begin
  DoInsert(Index,IntToStr(AValue));
  Result:=self;
end;

function TGenericStringBuilder.Insert(Index: Integer; const AValue: UInt64
  ): TGenericStringBuilder;
begin
  DoInsert(Index,IntToStr(AValue));
  Result:=self;
end;

procedure TGenericStringBuilder.Shrink;

begin
  if (Capacity div 4)>=Length then
    Capacity:=Capacity div 2;
end;

function TGenericStringBuilder.Remove(StartIndex: Integer; RemLength: Integer
  ): TGenericStringBuilder;

Var
  MoveIndex : Integer;

begin
  if (RemLength=0) then
    exit(Self);
  CheckNegative(RemLength,'RemLength');
  CheckRange(StartIndex,0,Length);
  MoveIndex:=StartIndex+RemLength;
  CheckRange(MoveIndex,0,Length);
  if (Length-Moveindex)>0 then
    Move(FData[MoveIndex],FData[StartIndex],(Length-MoveIndex)*SizeOf(SBChar));
  Length:=Length-RemLength;
  Shrink;
  Result:=Self;
end;

Function TGenericStringBuilder.Replace(const OldValue, NewValue: SBRawString; StartIndex, Count: Integer): TGenericStringBuilder;

var
  Cur : PSBChar;
  CurIndex,MaxIndex : Integer;
  OldLen, NewLen, Delta : Integer;
  BC : SBChar;

begin
  if Count=0 then
    Exit(Self);
  // Some checks.
  CheckNegative(StartIndex,'StartIndex');
  CheckNegative(Count,'Count');
  CheckRange(Startindex,Count,Length);
  // Init
  OldLen:=System.Length(OldValue);
  if OldLen=0 then
    Raise EArgumentException.Create('OldValue must not be empty');
  NewLen:=System.Length(NewValue);
  Delta:=NewLen-OldLen;
  MaxIndex:=StartIndex+Count;
  CurIndex:=StartIndex;
  BC:=OldValue[1];
  Cur:=@FData[StartIndex];
  // Loop
  while (CurIndex<Length-OldLen+1) and (CurIndex<MaxIndex) do
    begin
    if (Cur^=BC) then
      begin
      if 0=StrLComp(@FData[CurIndex],PSBChar(OldValue),OldLen) then
        begin
        // Do actual replace.
        DoReplace(CurIndex,OldValue,NewValue);
        Inc(CurIndex,NewLen-1);
        // DoReplace may have reallocated memory, so changed pointers, reset pointer
        Cur:=@FData[CurIndex];
        // The max index must be increased/decreased with Delta
        //  0123456789012
        // 'zzbczzedeafzz' replace('e','qqqq',6,3) -> zzbczzqqqqdqqqqafzz
        Inc(MaxIndex,Delta);
        end;
      end;
    Inc(CurIndex);
    Inc(Cur);
    end;
  Result:=Self;
end;

Function TGenericStringBuilder.Replace(const OldChar, NewChar: SBChar; StartIndex,
  Count: Integer): TGenericStringBuilder;
var
  I : Integer;
  Cur : PSBChar;

begin
  if Count=0 then
    Exit(Self);
  CheckNegative(StartIndex,'StartIndex');
  CheckNegative(Count,'Count');
  CheckRange(StartIndex,Count,Length);
  Cur:=@FData[StartIndex];
  For I:=1 to Count do
    begin
    if Cur^=OldChar then
      Cur^:=NewChar;
    Inc(Cur);
    end;
  Result:=Self;
end;

Function TGenericStringBuilder.Replace(const OldChar, NewChar: SBChar): TGenericStringBuilder;

begin
  Result:=Replace(OldChar,NewChar,0,Length);
end;

Function TGenericStringBuilder.Replace(const OldValue, NewValue: SBRawString): TGenericStringBuilder;
begin
  Result:=Replace(OldValue,NewValue,0,Length);
end;

procedure TGenericStringBuilder.SetCapacity(AValue: Integer);
var
  NewData: TSBCharArray;
begin
  if (AValue>FMaxCapacity) then
    Raise ERangeError.CreateFmt(SListCapacityError,[AValue]);
  if (AValue<Length) then
    Raise ERangeError.CreateFmt(SListCapacityError,[AValue]);
  if AValue=System.Length(FData) then
    exit;
  { only FLength characters are live: resizing the array copies the whole
    old capacity, so a sparsely filled buffer moves just the live run to
    a fresh block instead.  A mostly full buffer keeps the array resize -
    the reallocation can often extend the block in place }
  if FLength<=System.Length(FData) div 2 then
    begin
    NewData:=nil;
    System.SetLength(NewData,AValue);
    if FLength>0 then
      Move(FData[0],NewData[0],FLength*SizeOf(SBChar));
    FData:=NewData;
    end
  else
    System.SetLength(FData,AValue);
end;


{$IFDEF UNICODERTL}
function TGenericStringBuilder.ToString: RTLString;
{$ELSE}
function TGenericStringBuilder.ToString: SBString;
{$ENDIF}

begin
  Result:=ToString(0,Length);
end;

function TGenericStringBuilder.ToString(aStartIndex: Integer; aLength: Integer
  ): SBString;
begin
  if (aLength=0) then
    Result:=''
  else
    begin
    CheckNegative(aStartIndex,'aStartIndex');
    CheckNegative(aLength,'aLength');
    CheckRange(aStartIndex,aLength,Length);
    System.SetLength(Result,aLength);
    Move(FData[aStartIndex],Result[1],aLength*SizeOf(SBChar));
    end;
end;

{$IFDEF UNICODERTL}
function TGenericStringBuilder.ToString(UpdateCapacity: Boolean): RTLString;
{$ELSE}
function TGenericStringBuilder.ToString(UpdateCapacity: Boolean): SBString;
{$ENDIF}

begin
  if (Length<>Capacity) and UpdateCapacity then
    SetCapacity(Length);
  Result:=ToString();
end;


procedure TGenericStringBuilder.DoReplace(Index: Integer; const Old, New: SBString);

var
  NVLen,OVLen,OLen,Delta,TailStart: Integer;

begin
  NVLen:=System.Length(New);
  OVLen:=System.Length(Old);
  Delta:=NVLen-OVLen;
  if (Delta<>0) then
    begin
    OLen:=Length;
    if (Delta>0) then
      Length:=OLen+Delta;
    TailStart:=Index+OVlen;
    Move(FData[TailStart],FData[Index+NVLen],(OLen-TailStart)*SizeOf(SBChar));
    if (Delta<0) then
      Length:=OLen+Delta;
    end;
  if NVLen>0 then
    Move(New[1],FData[Index],NVLen*SizeOf(SBChar));
end;

