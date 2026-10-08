{%MainUnit sysutils.pp}
{
    *********************************************************************
    Copyright (C) 2012 Paul Ishenin,
    member of the Free Pascal Development Team

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    *********************************************************************
}

{ TEncoding }

class function TEncoding.GetStandard(Se: TStandardEncoding; Ctr: TCreateEncodingProc): TEncoding;
begin
  Result := FStandardEncodings[Se];
  if Assigned(Result) then
  begin
{$ifdef FPC_HAS_FEATURE_THREADING}
    ReadDependencyBarrier; // Read Result contents (by caller) after Result pointer.
{$endif}
    Exit;
  end;

  Result := Ctr();
{$ifdef FPC_HAS_FEATURE_THREADING}
  WriteBarrier; // Write FStandardEncodings[Se] after Result contents.
  if InterlockedCompareExchange(Pointer(FStandardEncodings[Se]), Pointer(Result), nil) <> nil then
  begin
    Result.Free;
    Result := FStandardEncodings[Se];
  end;
{$else}
  FStandardEncodings[Se] := Result;
{$endif}
end;

class function TEncoding.CreateANSI: TEncoding;
var
  Cp: TSystemCodePage;
begin
  Cp := DefaultSystemCodePage;
  if Assigned(widestringmanager.GetStandardCodePageProc) then
    Cp := widestringmanager.GetStandardCodePageProc(scpAnsi);
  Result := TMBCSEncoding.Create(Cp);
end;

class function TEncoding.GetANSI: TEncoding;
begin
  Result := GetStandard(seAnsi, @CreateANSI);
end;

procedure CheckEncodingSourceSpan(Index, Count, SpanLength: Integer;
  CharacterIndex: Boolean); inline;
begin
  if Index<0 then
    begin
    if CharacterIndex then
      raise EEncodingError.CreateFmt(SCharacterIndexOutOfBounds,[Index])
    else
      raise EEncodingError.CreateFmt(SByteIndexOutOfBounds,[Index]);
    end;
  if Count<0 then
    raise EEncodingError.CreateFmt(SInvalidCount,[Count]);
  if Index>SpanLength then
    raise EEncodingError.CreateFmt(SInvalidCount,[Count]);
  if Count>SpanLength-Index then
    raise EEncodingError.CreateFmt(SInvalidCount,[Count]);
end;

function TEncoding.GetAnsiBytes(const S: ansistring): TBytes;
begin
  if S='' then
    Result := nil
  else
    Result := GetAnsiBytes(S, 1, Length(S));
end;

function TEncoding.GetAnsiBytes(const S: ansistring; CharIndex, CharCount: Integer
  ): TBytes;
begin
  if CharIndex<1 then
    raise EEncodingError.CreateFmt(SCharacterIndexOutOfBounds,[CharIndex]);
  CheckEncodingSourceSpan(CharIndex-1,CharCount,Length(S),True);
  if CharCount=0 then
    exit(nil);
  Result := GetAnsiBytes(Pointer(@S[CharIndex]),CharCount);
end;

function TEncoding.GetAnsiString(const Bytes: TBytes): ansistring;
begin
  if Length(Bytes)=0 then
    Result := ''
  else
    Result := GetAnsiString(Bytes, 0, Length(Bytes));
end;

function TEncoding.GetAnsiString(const Bytes: TBytes; ByteIndex,
  ByteCount: Integer): ansistring;
begin
  if (Bytes=nil) and (ByteCount<>0) then
    raise EEncodingError.Create(SInvalidSourceArray);
  CheckEncodingSourceSpan(ByteIndex,ByteCount,Length(Bytes),False);
  if ByteCount=0 then
    Result := ''
  else
    Result := GetAnsiString(Pointer(@Bytes[ByteIndex]),ByteCount);
  SetCodePage(RawByteString(Result), DefaultSystemCodePage, False);
end;

class function TEncoding.CreateASCII: TEncoding;
begin
  Result := TMBCSEncoding.Create(CP_ASCII);
end;

class function TEncoding.GetASCII: TEncoding;
begin
  Result := GetStandard(seAscii, @CreateASCII);
end;

class function TEncoding.CreateBigEndianUnicode: TEncoding;
begin
  Result := TBigEndianUnicodeEncoding.Create;
end;

class function TEncoding.GetBigEndianUnicode: TEncoding;
begin
  Result := GetStandard(seBigEndianUnicode, @CreateBigEndianUnicode);
end;

class function TEncoding.GetDefault: TEncoding;
begin
  Result := GetSystemEncoding;
end;

class function TEncoding.GetSystemEncoding: TEncoding;
var
  Cp: TSystemCodePage;
  Head: TEncoding;
begin
  repeat
    Cp := DefaultSystemCodePage;
    Head := FSystemEncodingsList; // Must not be re-read until InterlockedCompareExchange to guarantee that search was performed against this head.
{$ifdef FPC_HAS_FEATURE_THREADING}
    ReadDependencyBarrier; // Read Head contents after Head pointer.
{$endif}
    Result := Head;
    while Assigned(Result) do
      if Result.CodePage = Cp then
        Exit
      else
        Result := Result.FNext;

    // not found - create new encoding at first position
    Result := TMBCSEncoding.Create(Cp);
    Result.FNext := Head;
{$ifdef FPC_HAS_FEATURE_THREADING}
    WriteBarrier; // Write FSystemEncodingsList after Result contents.
    if InterlockedCompareExchange(Pointer(FSystemEncodingsList), Pointer(Result), Pointer(Head)) = Pointer(Head) then
      break
    else
      Result.Free;
{$else}
    FSystemEncodingsList := Result;
    break;
{$endif}
  until false;
end;

class function TEncoding.CreateUnicode: TEncoding;
begin
  Result := TUnicodeEncoding.Create;
end;

class function TEncoding.GetUnicode: TEncoding;
begin
  Result := GetStandard(seUnicode, @CreateUnicode);
end;

class function TEncoding.CreateUTF7: TEncoding;
begin
  Result := TUTF7Encoding.Create;
end;

class function TEncoding.GetUTF7: TEncoding;
begin
  Result := GetStandard(seUTF7, @CreateUTF7);
end;

class function TEncoding.CreateUTF8: TEncoding;
begin
  Result := TUTF8Encoding.Create;
end;

class function TEncoding.GetUTF8: TEncoding;
begin
  Result := GetStandard(seUTF8, @CreateUTF8);
end;

class destructor TEncoding.Destroy;
var
  E: TStandardEncoding;
  Se: TEncoding;
begin
  // Synchronization shouldn't be required for class destructors.
  for E := Low(FStandardEncodings) to High(FStandardEncodings) do
    FreeAndNil(FStandardEncodings[E]);
  repeat
    Se := FSystemEncodingsList;
    if not Assigned(Se) then
      break;
    FSystemEncodingsList := Se.FNext;
    Se.Free;
  until false;
end;

function TEncoding.Clone: TEncoding;
begin
  Result := nil;
end;

class function TEncoding.Convert(Source, Destination: TEncoding;
  const Bytes: TBytes): TBytes;
begin
  Result := Destination.GetBytes(Source.GetChars(Bytes));
end;

class function TEncoding.Convert(Source, Destination: TEncoding;
  const Bytes: TBytes; StartIndex, Count: Integer): TBytes;
begin
  Result := Destination.GetBytes(Source.GetChars(Bytes, StartIndex, Count));
end;

class function TEncoding.IsStandardEncoding(AEncoding: TEncoding): Boolean;
var
  Encoding: TEncoding;
begin
  if Assigned(AEncoding) then
  begin
    for Encoding in FStandardEncodings do
      if Encoding = AEncoding then
        Exit(True);
    Encoding := FSystemEncodingsList;
    while Assigned(Encoding) do
      if Encoding = AEncoding then
        Exit(True)
      else
        Encoding := Encoding.FNext;
  end;
  Result := False;
end;

class function TEncoding.GetBufferEncoding(const Buffer: TBytes; var AEncoding: TEncoding): Integer;
begin
  Result := GetBufferEncoding(Buffer, AEncoding, Default);
end;

class function TEncoding.GetBufferEncoding(const Buffer: TBytes;
  var AEncoding: TEncoding; ADefaultEncoding: TEncoding): Integer;

  function CheckEncoding(AEncoding: TEncoding; out ByteCount: Integer): Boolean;
  var
    Preamble: TBytes;
  begin
    Preamble := AEncoding.GetPreamble;
    ByteCount := Length(Preamble);
    Result := (Length(Buffer) >= ByteCount) and (ByteCount > 0);
    if Result then
      Result := CompareMem(@Preamble[0], @Buffer[0], ByteCount);
  end;

begin
  if Assigned(AEncoding) then
  begin
    if not CheckEncoding(AEncoding, Result) then
      Result := 0;
  end
  else
  if CheckEncoding(Unicode, Result) then
    AEncoding := Unicode
  else
  if CheckEncoding(BigEndianUnicode, Result) then
    AEncoding := BigEndianUnicode
  else
  if CheckEncoding(UTF8, Result) then
    AEncoding := UTF8
  else
  begin
    AEncoding := ADefaultEncoding;
    Result := 0;
  end;
end;

procedure CheckEncodingDestinationIndex(Index, SpanLength: Integer); inline;
begin
  if (Index<0) or (Index>SpanLength) then
    raise EEncodingError.CreateFmt(SInvalidDestinationIndex,[Index]);
end;

function TEncoding.GetByteCount(const Chars: TUnicodeCharArray): Integer;
begin
  if Length(Chars)=0 then
    Result := 0
  else
    Result := GetByteCount(Chars, 0, Length(Chars));
end;

function TEncoding.GetByteCount(const Chars: TUnicodeCharArray; CharIndex,
  CharCount: Integer): Integer;
begin
  CheckEncodingSourceSpan(CharIndex,CharCount,Length(Chars),True);
  if CharCount=0 then
    exit(0);
  Result := GetByteCount(@Chars[CharIndex], CharCount);
end;

function TEncoding.GetByteCount(const S: UnicodeString): Integer;
begin
  if S='' then
    Result := 0
  else
    Result := GetByteCount(PUnicodeChar(S), Length(S));
end;

function TEncoding.GetByteCount(const S: UnicodeString; CharIndex, CharCount: Integer): Integer;
begin
  if CharIndex<1 then
    raise EEncodingError.CreateFmt(SCharacterIndexOutOfBounds, [CharIndex]);
  CheckEncodingSourceSpan(CharIndex-1,CharCount,Length(S),True);
  if CharCount=0 then
    exit(0);
  Result := GetByteCount(@S[CharIndex], CharCount);
end;

function TEncoding.GetBytes(const Chars: TUnicodeCharArray): TBytes;
begin
  SetLength(Result, GetByteCount(Chars));
  if Length(Result)>0 then
    GetBytes(@Chars[0], Length(Chars), @Result[0], Length(Result));
end;

function TEncoding.GetBytes(const Chars: TUnicodeCharArray; CharIndex,
  CharCount: Integer): TBytes;
begin
  SetLength(Result,GetByteCount(Chars,CharIndex,CharCount));
  if (CharCount>0) and (Length(Result)>0) then
    GetBytes(@Chars[CharIndex],CharCount,@Result[0],Length(Result));
end;

function TEncoding.GetBytes(const Chars: TUnicodeCharArray; CharIndex,
  CharCount: Integer; const Bytes: TBytes; ByteIndex: Integer): Integer;
var
  ByteLen,Required: Integer;
begin
  ByteLen := Length(Bytes);
  if (Chars=nil) and (CharCount<>0) then
    raise EEncodingError.Create(SInvalidSourceArray);
  if (Bytes=nil) and (CharCount<>0) then
    raise EEncodingError.Create(SInvalidDestinationArray);
  CheckEncodingSourceSpan(CharIndex,CharCount,Length(Chars),True);
  CheckEncodingDestinationIndex(ByteIndex,ByteLen);
  if CharCount=0 then
    exit(0);
  Required:=GetByteCount(@Chars[CharIndex],CharCount);
  if Required>ByteLen-ByteIndex then
    raise EEncodingError.Create(SInvalidDestinationArray);
  Result:=GetBytes(@Chars[CharIndex],CharCount,@Bytes[ByteIndex],
    ByteLen-ByteIndex);
end;

function TEncoding.GetBytes(const S: UnicodeString): TBytes;
begin
  SetLength(Result, GetByteCount(S));
  if Length(Result)>0 then
    GetBytes(@S[1], Length(S), @Result[0], Length(Result));
end;

function TEncoding.GetBytes(const S: UnicodeString; CharIndex, CharCount: Integer;
  const Bytes: TBytes; ByteIndex: Integer): Integer;
var
  ByteLen,Required: Integer;
begin
  ByteLen := Length(Bytes);
  { Keep Delphi's published diagnostic contract, including its historical
    source-array wording for a nil destination in the string overload. }
  if (Bytes=nil) and (CharCount<>0) then
    raise EEncodingError.Create(SInvalidSourceArray);
  if CharIndex<1 then
    raise EEncodingError.CreateFmt(SCharacterIndexOutOfBounds, [CharIndex]);
  CheckEncodingSourceSpan(CharIndex-1,CharCount,Length(S),True);
  CheckEncodingDestinationIndex(ByteIndex,ByteLen);
  if CharCount=0 then
    exit(0);
  Required:=GetByteCount(@S[CharIndex],CharCount);
  if Required>ByteLen-ByteIndex then
    raise EEncodingError.Create(SInvalidDestinationArray);
  Result:=GetBytes(@S[CharIndex],CharCount,@Bytes[ByteIndex],
    ByteLen-ByteIndex);
end;

function TEncoding.GetCharCount(const Bytes: TBytes): Integer;
begin
  if Length(Bytes)=0 then
    Result := 0
  else
    Result := GetCharCount(@Bytes[0], Length(Bytes));
end;

function TEncoding.GetCharCount(const Bytes: TBytes; ByteIndex,
  ByteCount: Integer): Integer;
begin
  if (Bytes=nil) and (ByteCount<>0) then
    raise EEncodingError.Create(SInvalidSourceArray);
  CheckEncodingSourceSpan(ByteIndex,ByteCount,Length(Bytes),False);
  if ByteCount=0 then
    exit(0);
  Result := GetCharCount(@Bytes[ByteIndex], ByteCount);
end;

function TEncoding.GetChars(const Bytes: TBytes): TUnicodeCharArray;
begin
  SetLength(Result, GetCharCount(Bytes));
  if Length(Result)>0 then
    GetChars(@Bytes[0], Length(Bytes), @Result[0], Length(Result));
end;

function TEncoding.GetChars(const Bytes: TBytes; ByteIndex, ByteCount: Integer): TUnicodeCharArray;
begin
  if (Bytes=nil) and (ByteCount<>0) then
    raise EEncodingError.Create(SInvalidSourceArray);
  CheckEncodingSourceSpan(ByteIndex,ByteCount,Length(Bytes),False);
  if ByteCount=0 then
    begin
    Result:=nil;
    exit;
    end;
  SetLength(Result, GetCharCount(Bytes, ByteIndex, ByteCount));
  if Length(Result)>0 then
    GetChars(@Bytes[ByteIndex],ByteCount,@Result[0],Length(Result));
end;

function TEncoding.GetChars(const Bytes: TBytes; ByteIndex, ByteCount: Integer;
  const Chars: TUnicodeCharArray; CharIndex: Integer): Integer;
var
  CharLen,Required: Integer;
begin
  if (Bytes=nil) and (ByteCount<>0) then
    raise EEncodingError.Create(SInvalidSourceArray);
  CheckEncodingSourceSpan(ByteIndex,ByteCount,Length(Bytes),False);
  CharLen := Length(Chars);
  CheckEncodingDestinationIndex(CharIndex,CharLen);
  if ByteCount=0 then
    exit(0);
  Required:=GetCharCount(@Bytes[ByteIndex],ByteCount);
  if Required>CharLen-CharIndex then
    raise EEncodingError.Create(SInvalidDestinationArray);
  { Required, not the whole rest of the array: the decoded text is all this
    call owns, and the elements behind it belong to the caller. }
  Result:=GetChars(@Bytes[ByteIndex],ByteCount,@Chars[CharIndex],Required);
end;

class function TEncoding.GetEncoding(CodePage: Integer): TEncoding;
begin
  case CodePage of
    CP_UTF16: Result := TUnicodeEncoding.Create;
    CP_UTF16BE: Result := TBigEndianUnicodeEncoding.Create;
    CP_UTF7: Result := TUTF7Encoding.Create;
    CP_UTF8: Result := TUTF8Encoding.Create;
  else
    Result := TMBCSEncoding.Create(CodePage);
  end;
end;

class function TEncoding.GetEncoding(const EncodingName: UnicodeString): TEncoding;
var
  ACodePage: TSystemCodePage;
begin
  ACodePage := CodePageNameToCodePage(AnsiString(EncodingName));
  if ACodePage = $FFFF then
    raise EEncodingError.CreateFmt(SNotValidCodePageName, [EncodingName]);
  Result := GetEncoding(ACodePage);
end;

{ The text is decoded straight into the result string.  Going through a
  TUnicodeCharArray first would allocate the characters twice and copy them
  once more for nothing. }

function TEncoding.GetString(const Bytes: TBytes): UnicodeString;
var
  Len: Integer;
begin
  Len:=Length(Bytes);
  if Len=0 then
    exit('');
  SetLength(Result,GetCharCount(@Bytes[0],Len));
  if Length(Result)=0 then
    exit;
  Len:=GetChars(@Bytes[0],Len,PUnicodeChar(Result),Length(Result));
  if Len<>Length(Result) then
    SetLength(Result,Len);
end;

function TEncoding.GetString(const Bytes: TBytes; ByteIndex, ByteCount: Integer): UnicodeString;
var
  Len: Integer;
begin
  if (Bytes=nil) and (ByteCount<>0) then
    raise EEncodingError.Create(SInvalidSourceArray);
  CheckEncodingSourceSpan(ByteIndex,ByteCount,Length(Bytes),False);
  if ByteCount=0 then
    exit('');
  SetLength(Result,GetCharCount(@Bytes[ByteIndex],ByteCount));
  if Length(Result)=0 then
    exit;
  Len:=GetChars(@Bytes[ByteIndex],ByteCount,PUnicodeChar(Result),Length(Result));
  if Len<>Length(Result) then
    SetLength(Result,Len);
end;

{ TMBCSEncoding }

procedure TMBCSEncoding.ConvertToBytes(Chars: PUnicodeChar; CharCount: Integer; out Value: RawByteString);
var
  I: Integer;
begin
  if FWCharToMBFlags<>0 then
    begin
    {$IFDEF MSWINDOWS}
    Value:='';
    if CharCount=0 then
      Exit;
    I:=WideCharToMultiByte(CodePage,FWCharToMBFlags,Chars,CharCount,nil,0,nil,nil);
    if I=0 then
      raise EEncodingError.Create('Invalid characters or conversion flags');
    SetLength(Value,I);
    if WideCharToMultiByte(CodePage,FWCharToMBFlags,Chars,CharCount,PAnsiChar(Value),I,nil,nil)=0 then
      raise EEncodingError.Create('Character conversion failed');
    Exit;
    {$ELSE}
    if (CodePage<>CP_UTF8) or (FWCharToMBFlags<>$80) then
      raise EEncodingError.Create('These conversion flags are unsupported on this platform');
    I:=0;
    while I<CharCount do
      begin
      if (Ord(Chars[I])>=$D800) and (Ord(Chars[I])<=$DBFF) then
        begin
        Inc(I);
        if (I=CharCount) or (Ord(Chars[I])<$DC00) or (Ord(Chars[I])>$DFFF) then
          raise EEncodingError.Create('Incomplete UTF-16 surrogate pair');
        end
      else if (Ord(Chars[I])>=$DC00) and (Ord(Chars[I])<=$DFFF) then
        raise EEncodingError.Create('Unpaired UTF-16 low surrogate');
      Inc(I);
      end;
    {$ENDIF}
    end;
  widestringmanager.Unicode2AnsiMoveProc(Chars,Value,CodePage,CharCount);
end;

procedure TMBCSEncoding.ConvertToChars(Bytes: PByte; ByteCount: Integer; out Value: UnicodeString);
var
  I: Integer;
  {$IFNDEF MSWINDOWS}
  J, Count: Integer;
  CodePoint, Minimum: Cardinal;
  {$ENDIF}
begin
  if FMBToWCharFlags<>0 then
    begin
    {$IFDEF MSWINDOWS}
    Value:='';
    if ByteCount=0 then
      Exit;
    I:=MultiByteToWideChar(CodePage,FMBToWCharFlags,PAnsiChar(Bytes),ByteCount,nil,0);
    if I=0 then
      raise EEncodingError.Create('Invalid bytes or conversion flags');
    SetLength(Value,I);
    if MultiByteToWideChar(CodePage,FMBToWCharFlags,PAnsiChar(Bytes),ByteCount,PWideChar(Value),I)=0 then
      raise EEncodingError.Create('Byte conversion failed');
    Exit;
    {$ELSE}
    if (CodePage<>CP_UTF8) or (FMBToWCharFlags<>8) then
      raise EEncodingError.Create('These conversion flags are unsupported on this platform');
    I:=0;
    while I<ByteCount do
      begin
      CodePoint:=Bytes[I];
      if CodePoint<$80 then
        begin
        Inc(I);
        Continue;
        end;
      case CodePoint of
        $C2..$DF: begin Count:=2; Minimum:=$80; CodePoint:=CodePoint and $1F; end;
        $E0..$EF: begin Count:=3; Minimum:=$800; CodePoint:=CodePoint and $0F; end;
        $F0..$F4: begin Count:=4; Minimum:=$10000; CodePoint:=CodePoint and $07; end;
        else raise EEncodingError.Create('Invalid UTF-8 lead byte');
      end;
      if Count>ByteCount-I then
        raise EEncodingError.Create('Incomplete UTF-8 character');
      for J:=1 to Count-1 do
        begin
        if (Bytes[I+J] and $C0)<>$80 then
          raise EEncodingError.Create('Invalid UTF-8 continuation byte');
        CodePoint:=(CodePoint shl 6) or (Bytes[I+J] and $3F);
        end;
      if (CodePoint<Minimum) or (CodePoint>$10FFFF) or
         ((CodePoint>=$D800) and (CodePoint<=$DFFF)) then
        raise EEncodingError.Create('Invalid UTF-8 code point');
      Inc(I,Count);
      end;
    {$ENDIF}
    end;
  widestringmanager.Ansi2UnicodeMoveProc(PAnsiChar(Bytes),CodePage,Value,ByteCount);
end;

function TMBCSEncoding.GetByteCount(Chars: PUnicodeChar; CharCount: Integer): Integer;
var
  S: RawByteString;
begin
  ConvertToBytes(Chars,CharCount,S);
  Result := Length(S);
end;

function TMBCSEncoding.GetBytes(Chars: PUnicodeChar; CharCount: Integer; Bytes: PByte;
  ByteCount: Integer): Integer;
var
  S: RawByteString;
begin
  ConvertToBytes(Chars,CharCount,S);
  Result := Length(S);
  if ByteCount < Result then
    Result := ByteCount;
  if Result > 0 then
    Move(S[1], Bytes[0], Result);
end;

function TMBCSEncoding.GetCharCount(Bytes: PByte; ByteCount: Integer): Integer;
var
  U: UnicodeString;
begin
  ConvertToChars(Bytes,ByteCount,U);
  Result := Length(U);
end;

function TMBCSEncoding.GetChars(Bytes: PByte; ByteCount: Integer; Chars: PUnicodeChar;
  CharCount: Integer): Integer;
var
  U: UnicodeString;
begin
  ConvertToChars(Bytes,ByteCount,U);
  Result := Length(U);
  if CharCount < Result then
    Result := CharCount;
  if Result > 0 then
    Move(U[1], Chars[0], Result * SizeOf(UnicodeChar));
end;

function TMBCSEncoding.GetCodePage: Cardinal;
begin
  Result := FCodePage;
end;

function TMBCSEncoding.GetEncodingName: UnicodeString;
begin
  Result := UnicodeString(CodePageToCodePageName(CodePage));
end;

constructor TMBCSEncoding.Create;
begin
  Create(DefaultSystemCodePage, 0, 0);
end;

constructor TMBCSEncoding.Create(ACodePage: Integer);
begin
  Create(ACodePage, 0, 0);
end;

constructor TMBCSEncoding.Create(ACodePage, MBToWCharFlags,
  WCharToMBFlags: Integer);
var
  Capabilities: TCodePageCapabilities;
begin
  FCodePage := ACodePage;
  FMBToWCharFlags := MBToWCharFlags;
  FWCharToMBFlags := WCharToMBFlags;
  if Assigned(widestringmanager.GetCodePageCapabilitiesProc) then
    begin
      widestringmanager.GetCodePageCapabilitiesProc(ACodePage,Capabilities);
      FMaxCharSize:=Capabilities.MaxCharSize;
      FIsSingleByte:=Capabilities.IsSingleByte;
    end
  else
    begin
      FMaxCharSize:=1;
      FIsSingleByte:=True;
    end;
  if FMaxCharSize<1 then
    FMaxCharSize:=1;
end;

function TMBCSEncoding.Clone: TEncoding;
begin
  Result := TMBCSEncoding.Create(FCodePage, FMBToWCharFlags, FWCharToMBFlags);
end;

function TMBCSEncoding.GetAnsiBytes(Chars: PAnsiChar; CharCount: Integer): TBytes;
var
  S: RawByteString;
begin
  SetString(S, Chars, CharCount);
  SetCodePage(S, DefaultSystemCodePage, False);
  SetCodePage(S, GetCodePage, True);
  SetLength(Result, Length(S));
  if Length(S)>0 then
    Move(S[1], Result[0], Length(S));
end;

function TMBCSEncoding.GetAnsiString(Bytes: PByte; ByteCount: Integer): ansistring;
begin
  SetString(Result, Pointer(Bytes), ByteCount);
  SetCodePage(RawByteString(Result), GetCodePage, False);
  SetCodePage(RawByteString(Result), DefaultSystemCodePage, True);
end;

function TMBCSEncoding.GetMaxByteCount(CharCount: Integer): Integer;
begin
  if (CharCount>0) and (FMaxCharSize>MaxInt div CharCount) then
    Result:=MaxInt
  else
    Result:=CharCount*FMaxCharSize;
end;

function TMBCSEncoding.GetMaxCharCount(ByteCount: Integer): Integer;
begin
  Result := ByteCount;
end;

function TMBCSEncoding.GetPreamble: TBytes;
begin
  case CodePage of
    CP_UTF8:
    begin
      SetLength(Result, 3);
      Result[0] := $EF;
      Result[1] := $BB;
      Result[2] := $BF;
    end;
    CP_UTF16:
    begin
      SetLength(Result, 2);
      Result[0] := $FF;
      Result[1] := $FE;
    end;
    CP_UTF16BE:
    begin
      SetLength(Result, 2);
      Result[0] := $FE;
      Result[1] := $FF;
    end;
  else
    Result := nil;
  end;
end;

{ TUTF7Encoding }

constructor TUTF7Encoding.Create;
begin
  inherited Create(CP_UTF7);
  FIsSingleByte := False;
end;

function TUTF7Encoding.Clone: TEncoding;
begin
  Result := TUTF7Encoding.Create;
end;

function TUTF7Encoding.GetMaxByteCount(CharCount: Integer): Integer;
begin
  Result := CharCount * 3 + 2;
end;

function TUTF7Encoding.GetMaxCharCount(ByteCount: Integer): Integer;
begin
  Result := ByteCount;
end;

{ TUTF8Encoding }

function TUTF8Encoding.GetByteCount(Chars: PUnicodeChar;
  CharCount: Integer): Integer;
begin
  Result:=UnicodeToUtf8Buffer(nil,0,Chars,CharCount);
end;

function TUTF8Encoding.GetBytes(Chars: PUnicodeChar; CharCount: Integer;
  Bytes: PByte; ByteCount: Integer): Integer;
begin
  Result:=UnicodeToUtf8Buffer(PAnsiChar(Bytes),ByteCount,Chars,CharCount);
end;

{ The other way round the class used to inherit TMBCSEncoding, which hands the
  whole buffer to the code page manager: an OS call (MultiByteToWideChar) and a
  temporary UnicodeString on Windows, and a byte-for-byte widening - that is,
  the wrong text - wherever no manager is installed.  The RTL decoder replaces
  the same invalid sequences with U+FFFD as the OS call does, needs no
  temporary and answers the same on every target.

  UTF-8 is self-synchronizing at every byte below $80 and each such byte is one
  character, so a leading run of them decodes without the per-character
  decision tree - one byte in, one character out - and the rest of the buffer
  still decodes on its own.  The lane takes eight bytes per step, the tail
  walks. }

function Utf8PlainAsciiBytes(Bytes: PByte; Count: Integer): Integer; inline;
const
  HighBits = QWord($8080808080808080);
var
  I: Integer;
begin
  I:=0;
  while (I+8<=Count) and ((PQWord(@Bytes[I])^ and HighBits)=0) do
    Inc(I,8);
  while (I<Count) and (Bytes[I]<$80) do
    Inc(I);
  Result:=I;
end;

procedure Utf8WidenAscii(Bytes: PByte; Chars: PUnicodeChar; Count: Integer);
var
  I: Integer;
{$ifdef ENDIAN_LITTLE}
  B: Cardinal;
{$endif}
begin
  I:=0;
{$ifdef ENDIAN_LITTLE}
  while I+4<=Count do
    begin
      B:=PCardinal(@Bytes[I])^;
      PQWord(@Chars[I])^:=QWord(B and $ff) or (QWord((B shr 8) and $ff) shl 16) or
        (QWord((B shr 16) and $ff) shl 32) or (QWord(B shr 24) shl 48);
      Inc(I,4);
    end;
{$endif ENDIAN_LITTLE}
  while I<Count do
    begin
      Chars[I]:=UnicodeChar(Bytes[I]);
      Inc(I);
    end;
end;

function Utf8CharCountWithAsciiLane(Bytes: PByte; ByteCount: Integer): Integer;
var
  Plain: Integer;
begin
  Plain:=Utf8PlainAsciiBytes(Bytes,ByteCount);
  if Plain=ByteCount then
    exit(ByteCount);
  { Utf8ToUnicode counts when Dest is nil; its result leaves room for the
    terminator it would have written. }
  Result:=Plain+Integer(Utf8ToUnicode(nil,0,PAnsiChar(@Bytes[Plain]),ByteCount-Plain))-1;
end;

function Utf8DecodeWithAsciiLane(Bytes: PByte; ByteCount: Integer;
  Chars: PUnicodeChar; CharCount: Integer): Integer;
var
  Plain: Integer;
begin
  Plain:=Utf8PlainAsciiBytes(Bytes,ByteCount);
  if Plain>CharCount then
    Plain:=CharCount;
  Utf8WidenAscii(Bytes,Chars,Plain);
  if (Plain=ByteCount) or (Plain=CharCount) then
    exit(Plain);
  Result:=Plain+Integer(Utf8ToUnicode(@Chars[Plain],CharCount-Plain,
    PAnsiChar(@Bytes[Plain]),ByteCount-Plain))-1;
end;

function TUTF8Encoding.GetCharCount(Bytes: PByte; ByteCount: Integer): Integer;
begin
  if (ByteCount>0) and (Bytes<>nil) then
    Result:=Utf8CharCountWithAsciiLane(Bytes,ByteCount)
  else
    Result:=0;
end;

function TUTF8Encoding.GetChars(Bytes: PByte; ByteCount: Integer;
  Chars: PUnicodeChar; CharCount: Integer): Integer;
begin
  if (ByteCount>0) and (CharCount>0) and (Bytes<>nil) and (Chars<>nil) then
    Result:=Utf8DecodeWithAsciiLane(Bytes,ByteCount,Chars,CharCount)
  else
    Result:=0;
end;

constructor TUTF8Encoding.Create;
begin
  inherited Create(CP_UTF8);
  FIsSingleByte := False;
end;

function TUTF8Encoding.Clone: TEncoding;
begin
  Result := TUTF8Encoding.Create;
end;

function TUTF8Encoding.GetMaxByteCount(CharCount: Integer): Integer;
begin
  Result := CharCount * 3;
end;

function TUTF8Encoding.GetMaxCharCount(ByteCount: Integer): Integer;
begin
  Result := ByteCount;
end;

function TUTF8Encoding.GetPreamble: TBytes;
begin
  SetLength(Result, 3);
  Result[0] := $EF;
  Result[1] := $BB;
  Result[2] := $BF;
end;

{ TUnicodeEncoding }

function TUnicodeEncoding.GetByteCount(Chars: PUnicodeChar; CharCount: Integer): Integer;
begin
  Result := CharCount * SizeOf(UnicodeChar);
end;

function TUnicodeEncoding.GetBytes(Chars: PUnicodeChar; CharCount: Integer;
  Bytes: PByte; ByteCount: Integer): Integer;
begin
  Result := CharCount * SizeOf(UnicodeChar);
  if ByteCount < Result then
    Result := ByteCount;
  if Result > 0 then
    Move(Chars[0], Bytes[0], Result);
end;

function TUnicodeEncoding.GetCharCount(Bytes: PByte; ByteCount: Integer): Integer;
begin
  Result := ByteCount div SizeOf(UnicodeChar);
end;

function TUnicodeEncoding.GetChars(Bytes: PByte; ByteCount: Integer;
  Chars: PUnicodeChar; CharCount: Integer): Integer;
begin
  Result := ByteCount div 2;
  if CharCount < Result then
    Result := CharCount;
  Move(Bytes[0], Chars[0], Result * SizeOf(UnicodeChar));
end;

function TUnicodeEncoding.GetCodePage: Cardinal;
begin
  Result := CP_UTF16;
end;

function TUnicodeEncoding.GetEncodingName: UnicodeString;
begin
  Result := UnicodeString(CodePageToCodePageName(CodePage));
end;

constructor TUnicodeEncoding.Create;
begin
  inherited Create;
  FIsSingleByte := False;
  FMaxCharSize := SizeOf(UnicodeChar);
end;

function TUnicodeEncoding.Clone: TEncoding;
begin
  Result := TUnicodeEncoding.Create;
end;

function TUnicodeEncoding.GetAnsiBytes(Chars: PAnsiChar; CharCount: Integer
  ): TBytes;
var
  U: UnicodeString;
begin
  widestringmanager.Ansi2UnicodeMoveProc(Chars, DefaultSystemCodePage, U, CharCount);
  SetLength(Result, Length(U)*SizeOf(UnicodeChar));
  if Length(Result)>0 then
    Move(U[1], Result[0], Length(Result));
end;

function TUnicodeEncoding.GetAnsiString(Bytes: PByte; ByteCount: Integer
  ): ansistring;
begin
  widestringmanager.Unicode2AnsiMoveProc(PUnicodeChar(Bytes), RawByteString(Result), DefaultSystemCodePage, ByteCount div SizeOf(UnicodeChar));
end;

function TUnicodeEncoding.GetMaxByteCount(CharCount: Integer): Integer;
begin
  Result := CharCount * SizeOf(UnicodeChar);
end;

function TUnicodeEncoding.GetMaxCharCount(ByteCount: Integer): Integer;
begin
  Result := ByteCount div SizeOf(UnicodeChar);
end;

function TUnicodeEncoding.GetPreamble: TBytes;
begin
  SetLength(Result, 2);
  Result[0] := $FF;
  Result[1] := $FE;
end;

{ TBigEndianUnicodeEncoding }

function TBigEndianUnicodeEncoding.GetBytes(Chars: PUnicodeChar; CharCount: Integer;
  Bytes: PByte; ByteCount: Integer): Integer;
var
  LastByte: PByte;
begin
  Result := CharCount * SizeOf(UnicodeChar);
  if ByteCount < Result then
    Result := ByteCount;
  LastByte := @Bytes[Result];
  while Bytes < LastByte do
  begin
    Bytes^ := Hi(Word(Chars^));
    inc(Bytes);
    if Bytes < LastByte then
      Bytes^ := Lo(Word(Chars^));
    inc(Bytes);
    inc(Chars);
  end;
end;

function TBigEndianUnicodeEncoding.GetChars(Bytes: PByte; ByteCount: Integer;
  Chars: PUnicodeChar; CharCount: Integer): Integer;
var
  LastChar: PUnicodeChar;
begin
  Result := ByteCount div SizeOf(UnicodeChar);
  if CharCount < Result then
    Result := CharCount;
  LastChar := @Chars[Result];
  while Chars < LastChar do
  begin
    Chars^ := UnicodeChar(Bytes[1] + Bytes[0] shl 8);
    inc(Bytes, SizeOf(UnicodeChar));
    inc(Chars);
  end;
end;

function TBigEndianUnicodeEncoding.GetCodePage: Cardinal;
begin
  Result := CP_UTF16BE;
end;

function TBigEndianUnicodeEncoding.GetEncodingName: UnicodeString;
begin
  Result := UnicodeString(CodePageToCodePageName(CodePage));
end;

function TBigEndianUnicodeEncoding.Clone: TEncoding;
begin
  Result := TBigEndianUnicodeEncoding.Create;
end;

function TBigEndianUnicodeEncoding.GetAnsiBytes(Chars: PAnsiChar; CharCount: Integer
  ): TBytes;
begin
  Result := TEncoding.Unicode.GetAnsiBytes(Chars, CharCount);
  Swap(Result);
end;

function TBigEndianUnicodeEncoding.GetAnsiString(Bytes: PByte;
  ByteCount: Integer): ansistring;
var
  B: TBytes;
begin
  if ByteCount=0 then
    Exit('');

  SetLength(B, ByteCount);
  Move(Bytes^, B[0], ByteCount);
  Swap(B);

  Result := TEncoding.Unicode.GetAnsiString(PByte(@B[0]), ByteCount);
end;

function TBigEndianUnicodeEncoding.GetPreamble: TBytes;
begin
  SetLength(Result, 2);
  Result[0] := $FE;
  Result[1] := $FF;
end;

procedure TBigEndianUnicodeEncoding.Swap(var B: TBytes);
var
  LastB, I: Integer;
  C: Byte;
begin
  LastB := Length(B)-1;
  I := 0;
  while I < LastB do
    begin
      C := B[I];
      B[I] := B[I+1];
      B[I+1] := C;
      Inc(I, 2);
    end;
end;
