{%MainUnit sysutils.pp}
{
    *********************************************************************
    Copyright (C) 1997, 1998 Gertjan Schouten

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************

    System Utilities For Free Pascal
}

{

This include file is used in 3 different places for the following functions:

  Function Format (Const Fmt : AnsiString; const Args : Array of const; const FormatSettings: TFormatSettings) : AnsiString;
  Function UnicodeFormat (Const Fmt : UnicodeString; const Args : Array of const; Const FormatSettings: TFormatSettings) : UnicodeString;
  Function WideFormat (Const Fmt : WideString; const Args : Array of const; Const FormatSettings: TFormatSettings) : WideString;

The header is different, but the function remains the same.
It uses the following defines:

  INWIDESTRING
  INUNICODESTRING
 (INANSISTRING is implicit)

and relies on 2 macros:

  TFormatString : one of unicodestring, widestring,ansistring
  TFormatChar : one of unicodechar, widechar or ansichar

}

Var ChPos,OldPos,ArgPos,DoArg,Len,ArgType : SizeInt;
    Hs,ToAdd : TFormatString;
    Index,ResultLength,ResultCapacity : SizeInt;
    Width,Prec : Longint;
    Left,DirectAppend : Boolean;
    Fchar : TFormatChar;
    vq : qword;

  Procedure EnsureResultCapacity(Additional : SizeInt); inline;

  Var Required,NewCapacity : SizeInt;

  begin
    If Additional<=0 then
      exit;
    Required:=ResultLength+Additional;
    If Required<=ResultCapacity then
      exit;
    NewCapacity:=ResultCapacity;
    If NewCapacity<64 then
      NewCapacity:=64;
    While NewCapacity<Required do
      If NewCapacity>High(SizeInt) div 2 then
        begin
        NewCapacity:=Required;
        break;
        end
      else
        NewCapacity:=NewCapacity*2;
    SetLength(Result,NewCapacity);
    ResultCapacity:=NewCapacity;
  end;

  Procedure AppendText(Const Value : TFormatString); inline;

  Var ValueLength : SizeInt;

  begin
    ValueLength:=Length(Value);
    If ValueLength=0 then
      exit;
    EnsureResultCapacity(ValueLength);
    Move(Value[1],Result[ResultLength+1],ValueLength*SizeOf(TFormatChar));
    Inc(ResultLength,ValueLength);
  end;

  Procedure AppendFormatSlice(Start,Count : SizeInt); inline;

  begin
    If Count<=0 then
      exit;
    EnsureResultCapacity(Count);
    Move(Fmt[Start],Result[ResultLength+1],Count*SizeOf(TFormatChar));
    Inc(ResultLength,Count);
  end;

  Procedure AppendSpaces(Count : SizeInt); inline;

  begin
    If Count<=0 then
      exit;
    EnsureResultCapacity(Count);
    While Count>0 do
      begin
      Inc(ResultLength);
      Result[ResultLength]:=' ';
      Dec(Count);
      end;
  end;

  Procedure AppendDecimal(Value : QWord; Negative : Boolean); inline;

  Var
    ContentLength,DigitCount,I,SpaceCount,ZeroCount : SizeInt;
    Digits : Array[0..19] of TFormatChar;

  begin
    DigitCount:=0;
    repeat
      Digits[DigitCount]:=TFormatChar(Ord('0')+Value mod 10);
      Value:=Value div 10;
      Inc(DigitCount);
    until Value=0;
    ZeroCount:=Prec-DigitCount;
    If ZeroCount<0 then
      ZeroCount:=0;
    ContentLength:=DigitCount+ZeroCount+Ord(Negative);
    SpaceCount:=Width-ContentLength;
    If SpaceCount<0 then
      SpaceCount:=0;
    EnsureResultCapacity(ContentLength+SpaceCount);
    If not Left then
      AppendSpaces(SpaceCount);
    If Negative then
      begin
      Inc(ResultLength);
      Result[ResultLength]:='-';
      end;
    While ZeroCount>0 do
      begin
      Inc(ResultLength);
      Result[ResultLength]:='0';
      Dec(ZeroCount);
      end;
    I:=DigitCount;
    While I>0 do
      begin
      Dec(I);
      Inc(ResultLength);
      Result[ResultLength]:=Digits[I];
      end;
    If Left then
      AppendSpaces(SpaceCount);
  end;

  Procedure AppendDecimal32(Value : Cardinal; Negative : Boolean); inline;

  Var
    ContentLength,DigitCount,SpaceCount,ZeroCount,WriteIndex : SizeInt;
    Quotient,Remainder : Cardinal;

  begin
    If Value>=10000 then
      If Value>=1000000 then
        If Value>=100000000 then
          DigitCount:=9+Ord(Value>=1000000000)
        else
          DigitCount:=7+Ord(Value>=10000000)
      else
        DigitCount:=5+Ord(Value>=100000)
    else If Value>=100 then
      DigitCount:=3+Ord(Value>=1000)
    else
      DigitCount:=1+Ord(Value>=10);
    ZeroCount:=Prec-DigitCount;
    If ZeroCount<0 then
      ZeroCount:=0;
    ContentLength:=DigitCount+ZeroCount+Ord(Negative);
    SpaceCount:=Width-ContentLength;
    If SpaceCount<0 then
      SpaceCount:=0;
    EnsureResultCapacity(ContentLength+SpaceCount);
    If not Left then
      AppendSpaces(SpaceCount);
    If Negative then
      begin
      Inc(ResultLength);
      Result[ResultLength]:='-';
      end;
    While ZeroCount>0 do
      begin
      Inc(ResultLength);
      Result[ResultLength]:='0';
      Dec(ZeroCount);
      end;
    Inc(ResultLength,DigitCount);
    WriteIndex:=ResultLength;
    While Value>=100 do
      begin
      Quotient:=Value div 100;
      Remainder:=Value-Quotient*100;
      Result[WriteIndex]:=TFormatChar(Ord('0')+Remainder mod 10);
      Result[WriteIndex-1]:=TFormatChar(Ord('0')+Remainder div 10);
      Dec(WriteIndex,2);
      Value:=Quotient;
      end;
    If Value>=10 then
      begin
      Result[WriteIndex]:=TFormatChar(Ord('0')+Value mod 10);
      Result[WriteIndex-1]:=TFormatChar(Ord('0')+Value div 10);
      end
    else
      Result[WriteIndex]:=TFormatChar(Ord('0')+Value);
    If Left then
      AppendSpaces(SpaceCount);
  end;

  Procedure AppendPaddedText(Const Value : TFormatString); inline;

  Var EffectiveLength,SpaceCount : SizeInt;

  begin
    EffectiveLength:=Length(Value);
    If (Prec>=0) and (EffectiveLength>Prec) then
      EffectiveLength:=Prec;
    SpaceCount:=Width-EffectiveLength;
    If SpaceCount<0 then
      SpaceCount:=0;
    EnsureResultCapacity(EffectiveLength+SpaceCount);
    If not Left then
      AppendSpaces(SpaceCount);
    If EffectiveLength>0 then
      begin
      Move(Value[1],Result[ResultLength+1],EffectiveLength*SizeOf(TFormatChar));
      Inc(ResultLength,EffectiveLength);
      end;
    If Left then
      AppendSpaces(SpaceCount);
  end;

  {
    ReadFormat reads the format string. It returns the type character in
    uppercase, and sets index, Width, Prec to their correct values,
    or -1 if not set. It sets Left to true if left alignment was requested.
    In case of an error, DoFormatError is called.
  }

  Function ReadFormat : TFormatChar; inline;

  Var Value : longint;

    Procedure ReadInteger; inline;

    var
      ArgN: SizeInt;
      Digit,ParsedValue: Longint;
    begin
      If Value<>-1 then exit; // Was already read.
      OldPos:=ChPos;
      ParsedValue:=0;
      While (ChPos<=Len) and
            (Fmt[ChPos]<='9') and (Fmt[ChPos]>='0') do
        begin
        Digit:=Ord(Fmt[ChPos])-Ord('0');
        If ParsedValue>(High(Longint)-Digit) div 10 then
          DoFormatError(feInvalidFormat,ansistring(Fmt));
        ParsedValue:=ParsedValue*10+Digit;
        inc(ChPos);
        end;
      If ChPos>len then
        DoFormatError(feInvalidFormat,ansistring(Fmt));
      If Fmt[ChPos]='*' then
        begin

        if Index=-1 then
          ArgN:=Argpos
        else
        begin
          ArgN:=Index;
          Inc(Index);
        end;

        If (ChPos>OldPos) or (ArgN>High(Args)) then
          DoFormatError(feInvalidFormat,ansistring(Fmt));

        ArgPos:=ArgN+1;

        case Args[ArgN].Vtype of
          vtInteger: Value := Args[ArgN].VInteger;
          vtInt64: Value := Args[ArgN].VInt64^;
          vtQWord: Value := Args[ArgN].VQWord^;
        else
          DoFormatError(feInvalidFormat,ansistring(Fmt));
        end;
        Inc(ChPos);
        end
      else
        begin
        If (OldPos<ChPos) Then
          Value:=ParsedValue
        else
          Value:=-1;
        end;
    end;

    Procedure ReadIndex; inline;

    begin
      If Fmt[ChPos]<>':' then
        ReadInteger
      else
        value:=0; // Delphi undocumented behaviour, assume 0, #11099
      If Fmt[ChPos]=':' then
        begin
        If Value=-1 then DoFormatError(feMissingArgument,ansistring(Fmt));
        Index:=Value;
        Value:=-1;
        Inc(ChPos);
        end;
{$ifdef fmtdebug}
      Log ('Read index');
{$endif}
    end;

    Procedure ReadLeft; inline;

    begin
      If Fmt[ChPos]='-' then
        begin
        left:=True;
        Inc(ChPos);
        end
      else
        Left:=False;
{$ifdef fmtdebug}
      Log ('Read Left');
{$endif}
    end;

    Procedure ReadWidth; inline;

    begin
      ReadInteger;
      If Value<>-1 then
        begin
        Width:=Value;
        Value:=-1;
        end;
{$ifdef fmtdebug}
      Log ('Read width');
{$endif}
    end;

    Procedure ReadPrec; inline;

    begin
      If Fmt[ChPos]='.' then
        begin
        inc(ChPos);
          ReadInteger;
        If Value=-1 then
         Value:=0;
        prec:=Value;
        end;
{$ifdef fmtdebug}
      Log ('Read precision');
{$endif}
    end;

{$ifdef INWIDEFORMAT}
  var
    FormatChar : TFormatChar;
{$endif INWIDEFORMAT}

  begin
{$ifdef fmtdebug}
    Log ('Start format');
{$endif}
    Index:=-1;
    Width:=-1;
    Prec:=-1;
    Value:=-1;
    inc(ChPos);
    If Fmt[ChPos]='%' then
      begin
        Result:='%';
        exit;
      end;
    ReadIndex;
    ReadLeft;
    ReadWidth;
    ReadPrec;
{$ifdef INWIDEFORMAT}
    FormatChar:=UpCase(UnicodeChar(Fmt[ChPos]));
    if word(FormatChar)>255 then
      ReadFormat:=#255
    else
      ReadFormat:=FormatChar;
{$else INWIDEFORMAT}
    ReadFormat:=Upcase(Fmt[ChPos]);
{$endif INWIDEFORMAT}
{$ifdef fmtdebug}
    Log ('End format');
{$endif}
end;


{$ifdef fmtdebug}
Procedure DumpFormat (C : TFormatChar);
begin
  Write ('Fmt : ',fmt:10);
  Write (' Index : ',Index:3);
  Write (' Left  : ',left:5);
  Write (' Width : ',Width:3);
  Write (' Prec  : ',prec:3);
  Writeln (' Type  : ',C);
end;
{$endif}


function ReadArgType : SizeInt; inline;
begin
  if Index=-1 then
    DoArg:=Argpos
  else
    DoArg:=Index;
  ArgPos:=DoArg+1;
  If (DoArg<0) or (Doarg>High(Args)) then
      DoFormatError(feInvalidArgindex,ansistring(Fmt));
  Result:=Args[DoArg].Vtype;
end;

begin
  Len:=Length(Fmt);
{$if defined(INWIDEFORMAT) and not defined(INUNICODESTRING)}
  { The three unqualified one-argument forms need neither the format parser nor
    a temporary output buffer.  Unicode strings are copy-on-write, so sharing
    the source value here has the same observable semantics as copying it. }
  If (Len=2) and (High(Args)=0) and (Fmt[1]='%') then
    Case UpCase(Fmt[2]) of
      'S':
        Case Args[0].VType of
          vtUnicodeString:
            exit(UnicodeString(Args[0].VUnicodeString));
          vtWideChar:
            exit(UnicodeString(WideChar(Args[0].VWideChar)));
        end;
      'D':
        Case Args[0].VType of
          vtInteger:
            exit(IntToStr(Args[0].VInteger));
          vtInt64:
            exit(IntToStr(Args[0].VInt64^));
          vtQWord:
            exit(IntToStr(Int64(Args[0].VQWord^)));
        end;
      'U':
        Case Args[0].VType of
          vtInteger:
            exit(UIntToStr(Cardinal(Args[0].VInteger)));
          vtInt64:
            exit(UIntToStr(QWord(Args[0].VInt64^)));
          vtQWord:
            exit(UIntToStr(Args[0].VQWord^));
        end;
    end;
{$endif INWIDEFORMAT and not INUNICODESTRING}
  ResultLength:=0;
  ResultCapacity:=Len+32;
  SetLength(Result,ResultCapacity);
  ChPos:=1;
  OldPos:=1;
  ArgPos:=0;
  While ChPos<=len do
    begin
    While (ChPos<=Len) and (Fmt[ChPos]<>'%') do
      inc(ChPos);
    If ChPos>OldPos Then
      AppendFormatSlice(OldPos,ChPos-Oldpos);
    If ChPos<Len then
      begin
      FChar:=ReadFormat;
      DirectAppend:=False;
{$ifdef fmtdebug}
      DumpFormat(FCHar);
{$endif}
      Case FChar of
        'B' : begin
              ArgType:=ReadArgType;
              Case ArgType of
                vtInteger:
                  ToAdd:=BoolToStr((Args[Doarg].VInteger<>0),True);
                vtInt64:
                  ToAdd:=BoolToStr((Args[Doarg].VInt64^<>0),True);
                vtBoolean:
                  ToAdd:=BoolToStr(Args[Doarg].VBoolean,True);
                else
                  DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              Index:=Length(ToAdd);
              // Top off
              If (Prec<>-1) and (Index>Prec) then
                begin
                Index:=Prec;
                SetLength(ToAdd,Index);
                end;
              end;
        'D' : begin
              ArgType:=ReadArgType;
              Case ArgType of
              vtInteger:
                begin
                Width:=Abs(Width);
                If Args[Doarg].VInteger<0 then
                  AppendDecimal32(Cardinal(-(Int64(Args[Doarg].VInteger)+1))+1,True)
                else
                  AppendDecimal32(Args[Doarg].VInteger,False);
                end;
              vtInt64:
                begin
                Width:=Abs(Width);
                If Args[DoArg].VInt64^<0 then
                  AppendDecimal(QWord(-(Args[DoArg].VInt64^+1))+1,True)
                else
                  AppendDecimal(Args[DoArg].VInt64^,False);
                end;
              vtQWord:
                begin
                Width:=Abs(Width);
                If Int64(Args[DoArg].VQWord^)<0 then
                  AppendDecimal(QWord(-(Int64(Args[DoArg].VQWord^)+1))+1,True)
                else
                  AppendDecimal(Args[DoArg].VQWord^,False);
                end;
              else
                DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              DirectAppend:=True;
              end;
        'U' : begin
              ArgType:=ReadArgType;
              Case ArgType of
              vtInteger:
                begin
                Width:=Abs(Width);
                AppendDecimal32(Cardinal(Args[Doarg].VInteger),False);
                end;
              vtInt64:
                begin
                Width:=Abs(Width);
                AppendDecimal(QWord(Args[DoArg].VInt64^),False);
                end;
              vtQWord:
                begin
                Width:=Abs(Width);
                AppendDecimal(Args[DoArg].VQWord^,False);
                end;
              else
                DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              DirectAppend:=True;
              end;
{$ifndef FPUNONE}
        'E' : begin
              ArgType:=ReadArgType;
              Case ArgType of
                vtCurrency:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VCurrency^,ffexponent,Prec,3,FormatSettings));
                vtExtended:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VExtended^,ffexponent,Prec,3,FormatSettings));
                else
                  DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              end;
        'F' : begin
              ArgType:=ReadArgType;
              Case ArgType of
                vtCurrency:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VCurrency^,ffFixed,9999,Prec,FormatSettings));
                vtExtended:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VExtended^,ffFixed,9999,Prec,FormatSettings));
                else
                  DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              end;
        'G' : begin
              ArgType:=ReadArgType;
              Case ArgType of
                vtCurrency:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VCurrency^,ffGeneral,Prec,3,FormatSettings));
                vtExtended:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VExtended^,ffGeneral,Prec,3,FormatSettings));
                else
                  DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              end;
        'N' : begin
              ArgType:=ReadArgType;
              Case ArgType of
                vtCurrency:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VCurrency^,ffNumber,9999,Prec,FormatSettings));
                vtExtended:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VExtended^,ffNumber,9999,Prec,FormatSettings));
                else
                  DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              end;
        'M' : begin
              ArgType:=ReadArgType;
              Case ArgType of
                vtExtended:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VExtended^,ffCurrency,9999,Prec,FormatSettings));
                vtCurrency:
                  ToAdd:=TFormatString(FloatToStrF(Args[doarg].VCurrency^,ffCurrency,9999,Prec,FormatSettings));
                else
                  DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
              end;
{$else}
        'E','F','G','N','M':
              RunError(207);
{$endif}
        'S' : begin
                ArgType:=ReadArgType;
                Case ArgType of
                  vtString:
                    hs:=TFormatString(Args[doarg].VString^);
                  vtChar:
{$ifdef INWIDEFORMAT}
                    { Delphi formats a vtChar payload by its ordinal value.
                      An implicit AnsiChar-to-UnicodeString assignment would
                      instead decode it through the system code page. }
                    hs:=TFormatString(WideChar(Ord(Args[doarg].VChar)));
{$else INWIDEFORMAT}
                    hs:=TFormatString(Args[doarg].VChar);
{$endif INWIDEFORMAT}
                  vtPChar:
                    hs:=TFormatString(Args[doarg].VPChar);
                  vtPWideChar:
                    hs:=TFormatString(WideString(Args[doarg].VPWideChar));
                  vtWideChar:
                    hs:=TFormatString(WideString(Args[doarg].VWideChar));
                  vtWidestring:
                    hs:=TFormatString(WideString(Args[doarg].VWideString));
                  vtAnsiString:
                    hs:=TFormatString(ansistring(Args[doarg].VAnsiString));
                  vtUnicodeString:
{$ifdef INWIDEFORMAT}
                    begin
                    AppendPaddedText(UnicodeString(Args[doarg].VUnicodeString));
                    DirectAppend:=True;
                    end;
{$else INWIDEFORMAT}
                    hs:=TFormatString(UnicodeString(Args[doarg].VUnicodeString));
{$endif INWIDEFORMAT}
                  vtVariant:
                    hs:=Args[doarg].VVariant^;
                  else
                    DoFormatError(feInvalidArgindex,ansistring(Fmt));
                end;
                If not DirectAppend then
                  AppendPaddedText(hs);
                DirectAppend:=True;
              end;
        'O' :
              begin
              ArgType:=ReadArgType;
              if ArgType=vtClass then
                begin
                if (Args[DoArg].VClass=Nil) then
                  ToAdd:='<Nil>'
                else
                  ToAdd:=TFormatString(Args[DoArg].VClass.ClassName);
                end
              else if ArgType=vtObject then
                begin
                if (Args[DoArg].VObject=Nil) then
                  ToAdd:='<Nil>'
                else
                  ToAdd:=TFormatString(Args[DoArg].VObject.ToString);
                end
              else
                DoFormatError(feInvalidArgindex,ansistring(Fmt));
              end;
        'P' : begin
              ArgType:=ReadArgType;
              if ArgType=vtObject then
                ToAdd:=TFormatString(HexStr(ptruint(Args[DoArg].VObject),sizeof(Ptruint)*2))
              else if ArgType=vtClass then
                ToAdd:=TFormatString(HexStr(ptruint(Args[DoArg].VClass),sizeof(Ptruint)*2))
              else if ArgType=vtPointer then
                ToAdd:=TFormatString(HexStr(ptruint(Args[DoArg].VPointer),sizeof(Ptruint)*2))
              else
                DoFormatError(feInvalidArgindex,ansistring(Fmt));
              // Insert ':'. Is this needed in 32 bit ? No it isn't.
              // Insert(':',ToAdd,5);
              end;
        'X' : begin
              ArgType:=ReadArgType;
              if ArgType=vtInteger then
                 begin
                   vq:=Cardinal(Args[Doarg].VInteger);
                   index:=16;
                 end
              else
                 if ArgType=vtQWord then
                   begin
                     vq:=Qword(Args[DoArg].VQWord^);
                     index:=31;
                   end
                 else
                 begin
                   If ArgType<>vtInt64 then
                     DoFormatError(feInvalidArgindex,ansistring(Fmt));
                   vq:=Qword(Args[DoArg].VInt64^);
                   index:=31;
                 end;
              If Prec>index then
                ToAdd:=TFormatString(HexStr(int64(vq),index))
              else
                begin
                // determine minimum needed number of hex digits.
                Index:=1;
                While (qWord(1) shl (Index*4)<=vq) and (index<16) do
                  inc(Index);
                If Index>Prec then
                  Prec:=Index;
                ToAdd:=TFormatString(HexStr(int64(vq),Prec));
                end;
              end;
        '%': ToAdd:='%';
      end;
      // Padding ?
      If DirectAppend then
        { Numeric value was written directly into Result. }
      else If (Width=-1) or (Length(ToAdd)>=Width) then
        // No width specified or the string to add has required width or greater
        AppendText(ToAdd)
      else
        begin
        // String to add is less than requested width.
        Index:=Width-Length(ToAdd);
        if Left then
          // Add left aligned
          begin
          AppendText(ToAdd);
          AppendSpaces(Index);
          end
        else
          // Add right aligned
          begin
          AppendSpaces(Index);
          AppendText(ToAdd);
          end;
        end;
      end;
    inc(ChPos);
    Oldpos:=ChPos;
    end;
  SetLength(Result,ResultLength);
end;
