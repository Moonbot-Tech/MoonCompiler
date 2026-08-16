{%MainUnit sysutils.pp}
{
    *********************************************************************
    Copyright (C) 2002-2005 by Florian Klaempfl

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    *********************************************************************
}

function Trim(const S: unicodestring; mode: TTrimMode): unicodestring;
  var
    start, ed, ns: SizeInt;
  begin
    start := 1;
    ns := Length(S);
    ed := ns;
    if mode <> TTrimMode.Right then
      while (start <= ed) and (S[start] <= ' ') do
        inc(start);
    if mode <> TTrimMode.Left then
      while (start <= ed) and (S[ed] <= ' ') do
        dec(ed);
    if (start = 1) and (ed = ns) then
      Result := S
    else
      Result := Copy(S, start, ed - start + 1);
  end;

function Trim(const S: unicodestring): unicodestring;
  begin
    result := Trim(S, TTrimMode.Both);
  end;


{ TrimLeft returns a copy of S with all blank characters on the left stripped off  }
function TrimLeft(const S: unicodestring): unicodestring;
  begin
    Result := Trim(S, TTrimMode.Left);
  end;


{ TrimRight returns a copy of S with all blank characters on the right stripped off  }
function TrimRight(const S: unicodestring): unicodestring;
  begin
    Result := Trim(S, TTrimMode.Right);
  end;


Function InternalChangeCase(Const S : UnicodeString; FirstChar, LastChar: UnicodeChar): UnicodeString;
  {$ifdef CPUX86_64}
  const
    LaneHigh = UInt64($8000800080008000);
    LaneLow = UInt64($7fff7fff7fff7fff);
  var
    Len, Remaining : Integer;
    Src, Dst : PWideChar;
    V, LowBits, GeMask, LeMask, RangeMask, LowRep, HighRep : UInt64;
    C : UnicodeChar;
  begin
    Len:=Length(S);
    SetLength(Result,Len);
    if Len=0 then
      exit;
    Src:=PWideChar(S);
    Dst:=PWideChar(Result);
    Remaining:=Len;
    LowRep:=UInt64(Word(FirstChar))*UInt64($0001000100010001);
    HighRep:=UInt64(Word(LastChar))*UInt64($0001000100010001);
    while Remaining>=4 do
      begin
        V:=PUInt64(Src)^;
        LowBits:=V and LaneLow;
        GeMask:=((LowBits or LaneHigh)-LowRep) and LaneHigh;
        LeMask:=((HighRep or LaneHigh)-LowBits) and LaneHigh;
        RangeMask:=GeMask and LeMask and (not V) and LaneHigh;
        PUInt64(Dst)^:=V xor (RangeMask shr 10);
        Inc(Src,4);
        Inc(Dst,4);
        Dec(Remaining,4);
      end;
    while Remaining<>0 do
      begin
        C:=Src^;
        if (C>=FirstChar) and (C<=LastChar) then
          C:=UnicodeChar(Word(C) xor $20);
        Dst^:=C;
        Inc(Src);
        Inc(Dst);
        Dec(Remaining);
      end;
  end;
  {$else CPUX86_64}
  var
    i : Integer;
    P : PWideChar;
    Unique : Boolean;
  begin
    Result := S;
    if Result='' then
      exit;
    Unique:=false;
    P:=PWideChar(Result);
    for i:=1 to Length(Result) do
      begin
        if (P^>=FirstChar) and (P^<=LastChar) then
          begin
            if not Unique then
              begin
                UniqueString(Result);
                p:=@Result[i];
                Unique:=true;
              end;
            P^:=WideChar(Ord(P^) xor $20);
          end;
        Inc(P);
      end;
  end;
  {$endif CPUX86_64}


{   UpperCase returns a copy of S where all lowercase characters ( from a to z )
    have been converted to uppercase   }
Function UpperCase(Const S : UnicodeString) : UnicodeString;
  begin
    Result:=InternalChangeCase(S,'a','z');
  end;


{   LowerCase returns a copy of S where all uppercase characters ( from A to Z )
    have been converted to lowercase  }
Function Lowercase(Const S : UnicodeString) : UnicodeString;
  begin
    Result:=InternalChangeCase(S,'A','Z');
  end;


function UnicodeUpperCase(const s : UnicodeString) : UnicodeString;{$ifdef SYSUTILSINLINE}inline;{$endif}
  begin
    result:=widestringmanager.UpperUnicodeStringProc(s);
  end;


function UnicodeLowerCase(const s : UnicodeString) : UnicodeString;{$ifdef SYSUTILSINLINE}inline;{$endif}
  begin
    result:=widestringmanager.LowerUnicodeStringProc(s);
  end;


function UnicodeCompareStr(const s1, s2 : UnicodeString) : PtrInt;{$ifdef SYSUTILSINLINE}inline;{$endif}
var
  I, CommonLength, Length1, Length2: SizeInt;
  P1, P2: PUnicodeChar;
begin
  P1:=Pointer(S1);
  P2:=Pointer(S2);
  if P1=P2 then
    Exit(0);

  Length1:=Length(S1);
  Length2:=Length(S2);
  CommonLength:=Length1;
  if Length2<CommonLength then
    CommonLength:=Length2;

  I:=0;
  {$ifdef CPU64}
  while I+4<=CommonLength do
    begin
    if PQWord(P1+I)^<>PQWord(P2+I)^ then
      begin
      if P1[I]<>P2[I] then
        Exit(PtrInt(P1[I])-PtrInt(P2[I]));
      if P1[I+1]<>P2[I+1] then
        Exit(PtrInt(P1[I+1])-PtrInt(P2[I+1]));
      if P1[I+2]<>P2[I+2] then
        Exit(PtrInt(P1[I+2])-PtrInt(P2[I+2]));
      Exit(PtrInt(P1[I+3])-PtrInt(P2[I+3]));
      end;
    Inc(I,4);
    end;
  {$endif CPU64}
  while I<CommonLength do
    begin
    if P1[I]<>P2[I] then
      Exit(PtrInt(P1[I])-PtrInt(P2[I]));
    Inc(I);
    end;
  Result:=Length1-Length2;
end;


function UnicodeSameStr(const s1, s2 : UnicodeString) : Boolean;{$ifdef SYSUTILSINLINE}inline;{$endif}
begin
  Result:=S1=S2;
end;


function UnicodeCompareText(const s1, s2 : UnicodeString) : PtrInt;{$ifdef SYSUTILSINLINE}inline;{$endif}
  begin
    result:=widestringmanager.CompareUnicodeStringProc(s1,s2,[coIgnoreCase]);
  end;


function UnicodeSameText(const s1, s2 : UnicodeString) : Boolean;{$ifdef SYSUTILSINLINE}inline;{$endif}
  begin
    result:=widestringmanager.CompareUnicodeStringProc(s1,s2,[coIgnoreCase])=0;
  end;


{ we've no templates, but with includes we can simulate this :) }
{$macro on}
{$define INWIDEFORMAT}
{$define INUNICODESTRING}
{$define TFormatString:=unicodestring}
{$define TFormatChar:=unicodechar}

Function UnicodeFormatGeneral (Const Fmt : UnicodeString; const Args : Array of const; Const FormatSettings: TFormatSettings) : UnicodeString;
{$i sysformt.inc}


{$undef TFormatString}
{$undef TFormatChar}
{$undef INUNICODESTRING}
{$undef INWIDEFORMAT}
{$macro off}

Function TryUnicodeFormatSimple(Const Fmt : UnicodeString;
  const Args : Array of const; Const FormatSettings: TFormatSettings;
  Out Value: UnicodeString): Boolean;
var
  ArgIndex,Capacity,DigitCount,I,L,Precision,ResultLength,Start: Integer;
  Digits: Array[0..19] of UnicodeChar;
  Negative: Boolean;
  Part: UnicodeString;
  UnsignedValue: QWord;

  Procedure EnsureCapacity(Additional: Integer); inline;
  var
    Required: Integer;
  begin
    Required:=ResultLength+Additional;
    if Required<=Capacity then
      exit;
    if Capacity=0 then
      Capacity:=L+32;
    if Capacity<64 then
      Capacity:=64;
    while Capacity<Required do
      Capacity:=Capacity*2;
    SetLength(Value,Capacity);
  end;

  Procedure AppendSlice(SliceStart,Count: Integer); inline;
  begin
    if Count<=0 then
      exit;
    EnsureCapacity(Count);
    Move(Fmt[SliceStart],Value[ResultLength+1],Count*SizeOf(UnicodeChar));
    Inc(ResultLength,Count);
  end;

  Procedure AppendPart; inline;
  var
    PartLength: Integer;
  begin
    PartLength:=Length(Part);
    if PartLength=0 then
      exit;
    EnsureCapacity(PartLength);
    Move(Part[1],Value[ResultLength+1],PartLength*SizeOf(UnicodeChar));
    Inc(ResultLength,PartLength);
  end;

  Procedure AppendUnsigned(Number: QWord; IsNegative: Boolean); inline;
  begin
    DigitCount:=0;
    repeat
      Digits[DigitCount]:=UnicodeChar(Ord('0')+Number mod 10);
      Number:=Number div 10;
      Inc(DigitCount);
    until Number=0;
    EnsureCapacity(DigitCount+Ord(IsNegative));
    if IsNegative then
      begin
      Inc(ResultLength);
      Value[ResultLength]:='-';
      end;
    while DigitCount>0 do
      begin
      Dec(DigitCount);
      Inc(ResultLength);
      Value[ResultLength]:=Digits[DigitCount];
      end;
  end;

begin
  Result:=False;
  L:=Length(Fmt);
  Capacity:=0;
  Value:='';
  ResultLength:=0;
  ArgIndex:=0;
  I:=1;
  Start:=1;
  while I<=L do
    begin
    if Fmt[I]<>'%' then
      begin
      Inc(I);
      continue;
      end;
    AppendSlice(Start,I-Start);
    Inc(I);
    if I>L then
      exit;
    if Fmt[I]='%' then
      begin
      EnsureCapacity(1);
      Inc(ResultLength);
      Value[ResultLength]:='%';
      Inc(I);
      Start:=I;
      continue;
      end;
    if ArgIndex>High(Args) then
      exit;
    Case Fmt[I] of
      'd','D':
        Case Args[ArgIndex].VType of
          vtInteger:
            begin
            Negative:=Args[ArgIndex].VInteger<0;
            if Negative then
              UnsignedValue:=QWord(-(Int64(Args[ArgIndex].VInteger)+1))+1
            else
              UnsignedValue:=Args[ArgIndex].VInteger;
            AppendUnsigned(UnsignedValue,Negative);
            end;
          vtInt64:
            begin
            Negative:=Args[ArgIndex].VInt64^<0;
            if Negative then
              UnsignedValue:=QWord(-(Args[ArgIndex].VInt64^+1))+1
            else
              UnsignedValue:=Args[ArgIndex].VInt64^;
            AppendUnsigned(UnsignedValue,Negative);
            end;
          vtQWord:
            begin
            Negative:=Int64(Args[ArgIndex].VQWord^)<0;
            if Negative then
              UnsignedValue:=QWord(-(Int64(Args[ArgIndex].VQWord^)+1))+1
            else
              UnsignedValue:=Args[ArgIndex].VQWord^;
            AppendUnsigned(UnsignedValue,Negative);
            end;
          else
            exit;
        end;
      'u','U':
        begin
        Case Args[ArgIndex].VType of
          vtInteger:
            UnsignedValue:=Cardinal(Args[ArgIndex].VInteger);
          vtInt64:
            UnsignedValue:=QWord(Args[ArgIndex].VInt64^);
          vtQWord:
            UnsignedValue:=Args[ArgIndex].VQWord^;
          else
            exit;
        end;
        AppendUnsigned(UnsignedValue,False);
        end;
      's','S':
        Case Args[ArgIndex].VType of
          vtUnicodeString:
            begin
            Part:=UnicodeString(Args[ArgIndex].VUnicodeString);
            AppendPart;
            end;
          vtWideChar:
            begin
            EnsureCapacity(1);
            Inc(ResultLength);
            Value[ResultLength]:=UnicodeChar(Args[ArgIndex].VWideChar);
            end;
          else
            exit;
        end;
      'f','F':
        begin
        Precision:=-1;
        Case Args[ArgIndex].VType of
          vtExtended:
            Part:=FloatToStrF(Args[ArgIndex].VExtended^,ffFixed,9999,
              Precision,FormatSettings);
          vtCurrency:
            Part:=FloatToStrF(Args[ArgIndex].VCurrency^,ffFixed,9999,
              Precision,FormatSettings);
          else
            exit;
        end;
        AppendPart;
        end;
      '.':
        begin
        Precision:=0;
        Inc(I);
        Start:=I;
        while (I<=L) and (Fmt[I]>='0') and (Fmt[I]<='9') do
          begin
          if Precision>(High(Integer)-(Ord(Fmt[I])-Ord('0'))) div 10 then
            exit;
          Precision:=Precision*10+Ord(Fmt[I])-Ord('0');
          Inc(I);
          end;
        if (I=Start) or (I>L) or
           ((Fmt[I]<>'f') and (Fmt[I]<>'F')) then
          exit;
        Case Args[ArgIndex].VType of
          vtExtended:
            Part:=FloatToStrF(Args[ArgIndex].VExtended^,ffFixed,9999,
              Precision,FormatSettings);
          vtCurrency:
            Part:=FloatToStrF(Args[ArgIndex].VCurrency^,ffFixed,9999,
              Precision,FormatSettings);
          else
            exit;
        end;
        AppendPart;
        end;
      else
        exit;
    end;
    Inc(ArgIndex);
    Inc(I);
    Start:=I;
    end;
  if Start=1 then
    Value:=Fmt
  else
    begin
    AppendSlice(Start,L-Start+1);
    SetLength(Value,ResultLength);
    end;
  Result:=True;
end;

Function UnicodeFormat (Const Fmt : UnicodeString; const Args : Array of const; Const FormatSettings: TFormatSettings) : UnicodeString;
var
  I,Precision: Integer;
begin
  { Keep the common one-argument forms out of UnicodeFormatGeneral: entering
    that parser would construct its large stack frame and initialize all of
    its managed temporaries before it could take the same decision. }
  If (Length(Fmt)=2) and (High(Args)=0) and (Fmt[1]='%') then
    Case Fmt[2] of
      's','S':
        Case Args[0].VType of
          vtUnicodeString:
            exit(UnicodeString(Args[0].VUnicodeString));
          vtWideChar:
            exit(UnicodeString(WideChar(Args[0].VWideChar)));
        end;
      'd','D':
        Case Args[0].VType of
          vtInteger:
            exit(IntToStr(Args[0].VInteger));
          vtInt64:
            exit(IntToStr(Args[0].VInt64^));
          vtQWord:
            exit(IntToStr(Int64(Args[0].VQWord^)));
        end;
      'u','U':
        Case Args[0].VType of
          vtInteger:
            exit(UIntToStr(Cardinal(Args[0].VInteger)));
          vtInt64:
            exit(UIntToStr(QWord(Args[0].VInt64^)));
          vtQWord:
            exit(UIntToStr(Args[0].VQWord^));
        end;
    end;
  { An exact single fixed-point conversion is another common complete format,
    not a prefix of the general grammar.  Parse it here so FloatToStrF can
    produce the result directly instead of entering the large format parser,
    allocating a second temporary string and copying it into the output. }
  If (High(Args)=0) and (Length(Fmt)>=2) and (Fmt[1]='%') and
     ((Fmt[Length(Fmt)]='f') or (Fmt[Length(Fmt)]='F')) then
    begin
    Precision:=-1;
    if Length(Fmt)=2 then
      I:=Length(Fmt)
    else if (Fmt[2]='.') and (Length(Fmt)>3) then
      begin
      Precision:=0;
      I:=3;
      while (I<Length(Fmt)) and (Fmt[I]>='0') and (Fmt[I]<='9') do
        begin
        if Precision>(High(Integer)-(Ord(Fmt[I])-Ord('0'))) div 10 then
          break;
        Precision:=Precision*10+Ord(Fmt[I])-Ord('0');
        Inc(I);
        end;
      end
    else
      I:=0;
    if I=Length(Fmt) then
      Case Args[0].VType of
        vtExtended:
          exit(FloatToStrF(Args[0].VExtended^,ffFixed,9999,Precision,
            FormatSettings));
        vtCurrency:
          exit(FloatToStrF(Args[0].VCurrency^,ffFixed,9999,Precision,
            FormatSettings));
      end;
    end;
  if TryUnicodeFormatSimple(Fmt,Args,FormatSettings,Result) then
    exit;
  Result:=UnicodeFormatGeneral(Fmt,Args,FormatSettings);
end;

Function UnicodeFormat (Const Fmt : UnicodeString; const Args : Array of const) : UnicodeString;
begin
  Result:=UnicodeFormat(Fmt,Args,DefaultFormatSettings);
end;

Function Format (Const Fmt : UnicodeString; const Args : Array of const; Const FormatSettings: TFormatSettings) : UnicodeString;

begin
  { Format is the Delphi-facing entry point.  Keep its overwhelmingly common
    exact string substitution on this small wrapper instead of paying for the
    numeric dispatch in UnicodeFormat as well. }
  If (Length(Fmt)=2) and (High(Args)=0) and (Fmt[1]='%') and
     ((Fmt[2]='s') or (Fmt[2]='S')) then
    Case Args[0].VType of
      vtUnicodeString:
        exit(UnicodeString(Args[0].VUnicodeString));
      vtWideChar:
        exit(UnicodeString(WideChar(Args[0].VWideChar)));
    end;
  Result:=UnicodeFormat(Fmt,Args,FormatSettings);
end;


Function Format (Const Fmt : UnicodeString; const Args : Array of const) : UnicodeString;
begin
  Result:=UnicodeFormat(Fmt,Args,DefaultFormatSettings);
end;



Function UnicodeFormatBuf (Var Buffer; BufLen : Cardinal;
                     Const Fmt ; fmtLen : Cardinal;
                     Const Args : Array of const; Const FormatSettings: TFormatSettings) : Cardinal;
Var
  S,F : UnicodeString;

begin
  Setlength(F,fmtlen);
  if fmtlen > 0 then
    Move(fmt,F[1],fmtlen*sizeof(Unicodechar));
  S:=UnicodeFormat(F,Args,FormatSettings);
  If Cardinal(Length(S))<Buflen then
    Result:=Length(S)
  else
    Result:=Buflen;
  Move(S[1],Buffer,Result*SizeOf(UnicodeChar));
end;

Function UnicodeFormatBuf (Var Buffer; BufLen : Cardinal;
                     Const Fmt; fmtLen : Cardinal;
                     Const Args : Array of const) : Cardinal;

begin
  Result:=UnicodeFormatBuf(Buffer,BufLEn,Fmt,FmtLen,Args,DefaultFormatSettings);
end;


Procedure UnicodeFmtStr(Var Res: UnicodeString; Const Fmt : UnicodeString; Const args: Array of const; Const FormatSettings: TFormatSettings);
begin
  Res:=UnicodeFormat(Fmt,Args,FormatSettings);
end;


Procedure UnicodeFmtStr(Var Res: UnicodeString; Const Fmt : UnicodeString; Const args: Array of const);
begin
  UnicodeFmtStr(Res,Fmt,Args,DefaultFormatSettings);
end;


function StrMove(dest,source : PWideChar;l : SizeInt) : PWideChar; overload;
 begin
   move(source^,dest^,l*2);
   Result:=dest;
 end;


function StrPLCopy(Dest: PWideChar; const Source: UnicodeString; MaxLen: SizeUInt): PWideChar; overload;
var Len: SizeUInt;
begin
  Len := length(Source);
  if Len > MaxLen then
    Len := MaxLen;
  Move(Source[1], Dest^, Len*sizeof(WideChar));
  Dest[Len] := #0;
  StrPLCopy := Dest;
end;


function StrPCopy(Dest: PWideChar; const Source: UnicodeString): PWideChar; overload;
begin
  StrPCopy := StrPLCopy(Dest, Source, length(Source));
end;


function StrScan(P: PWideChar; C: WideChar): PWideChar;
Var
   count: SizeInt;
Begin
 count := 0;
 { As in Borland Pascal, if looking for NULL return null }
 if C = #0 then
 begin
   StrScan := @(P[StrLen(P)]);
   exit;
 end;
 { Find first matching character of Ch in Str }
 while P[count] <> #0 do
 begin
   if C = P[count] then
    begin
        StrScan := @(P[count]);
        exit;
    end;
   Inc(count);
 end;
 { nothing found. }
 StrScan := nil;
end;


function StrPas(Str: PWideChar): UnicodeString;overload;
begin
  Result:=Str;
end;


function strecopy(dest,source : pwidechar) : pwidechar;
  var
    counter: sizeint;
  begin
    counter := indexword(source^,-1,0);
    { counter+1 will move zero terminator }
    move(source^,dest^,(counter+1)*2);
    result:=dest+counter;
  end;


function strend(p : pwidechar) : pwidechar;
  begin
    result:=p+indexword(p^,-1,0);
  end;


function strcat(dest,source : pwidechar) : pwidechar;
  begin
    strcopy(strend(dest),source);
    strcat:=dest;
  end;


function strcomp(str1,str2 : pwidechar) : SizeInt;
  var
    counter: sizeint;
    c1, c2: widechar;
  begin
    counter:=0;
    repeat
      c1:=str1[counter];
      c2:=str2[counter];
      inc(counter);
    until (c1<>c2) or
          (c1=#0) or
          (c2=#0);
    strcomp:=ord(c1)-ord(c2);
  end;


function strlcomp(str1,str2 : pwidechar;l : SizeInt) : SizeInt;
  var
    counter: sizeint;
    c1, c2: widechar;
  begin
    if l = 0 then
      begin
        strlcomp := 0;
        exit;
      end;
    counter:=0;
    repeat
      c1:=str1[counter];
      c2:=str2[counter];
      inc(counter);
   until (c1<>c2) or (counter>=l) or
         (c1=#0) or (c2=#0);
    strlcomp:=ord(c1)-ord(c2);
  end;


{ the str* functions are not supposed to support internationalisation;
  system.upcase(widechar) does support it (although this is
  Delphi-incompatible) }
function simplewideupcase(w: widechar): widechar;
  begin
    if w in ['a'..'z'] then
      result:=widechar(ord(w)-32)
    else
      result:=w;
  end;


function stricomp(str1,str2 : pwidechar) : SizeInt;
  var
   counter: sizeint;
   c1, c2: widechar;
  begin
    counter := 0;
    c1:=simplewideupcase(str1[counter]);
    c2:=simplewideupcase(str2[counter]);
    while c1=c2 do
      begin
        if (c1=#0) or (c2=#0) then break;
        inc(counter);
        c1:=simplewideupcase(str1[counter]);
        c2:=simplewideupcase(str2[counter]);
      end;
    stricomp:=ord(c1)-ord(c2);
  end;


function strlcat(dest,source : pwidechar;l : SizeInt) : pwidechar;
  var
    destend : pwidechar;
  begin
    destend:=strend(dest);
    dec(l,destend-dest);
    if l>0 then
      strlcopy(destend,source,l);
    strlcat:=dest;
  end;


function strrscan(p : pwidechar;c : widechar) : pwidechar;
  var
   count: sizeint;
   index: sizeint;
  begin
    count:=strlen(p);
    { As in Borland Pascal , if looking for NULL return null }
    if c=#0 then
      begin
        strrscan:=@(p[count]);
        exit;
      end;
    dec(count);
    for index:=count downto 0 do
      begin
        if c=p[index] then
          begin
            strrscan:=@(p[index]);
            exit;
          end;
      end;
    { nothing found. }
    strrscan:=nil;
  end;


function strlower(p : pwidechar) : pwidechar;
  var
   counter: SizeInt;
   c: widechar;
  begin
    counter:=0;
    repeat
      c:=p[counter];
      if c in [#65..#90] then
        p[counter]:=widechar(ord(c)+32);
      inc(counter);
    until c=#0;
    strlower:=p;
  end;


function strupper(p : pwidechar) : pwidechar;
  var
   counter: SizeInt;
   c: widechar;
  begin
    counter:=0;
    repeat
      c:=p[counter];
      if c in [#97..#122] then
        p[counter]:=widechar(ord(c)-32);
      inc(counter);
    until c=#0;
    strupper:=p;
  end;


function strlicomp(str1,str2 : pwidechar;l : SizeInt) : SizeInt;
  var
   counter: sizeint;
   c1, c2: AnsiChar;
  begin
    counter := 0;
    if l=0 then
      begin
        strlicomp := 0;
        exit;
      end;
    repeat
      c1:=simplewideupcase(str1[counter]);
      c2:=simplewideupcase(str2[counter]);
      if (c1=#0) or (c2=#0) then break;
      inc(counter);
    until (c1<>c2) or (counter>=l);
    strlicomp:=ord(c1)-ord(c2);
  end;


function strpos(str1,str2 : pwidechar) : pwidechar;
  var
    p : pwidechar;
    lstr2 : SizeInt;
  begin
    strpos:=nil;
    if (str1=nil) or (str2=nil) then
      exit;
    p:=strscan(str1,str2^);
    if p=nil then
       exit;
    lstr2:=strlen(str2);
    while p<>nil do
      begin
        if strlcomp(p,str2,lstr2)=0 then
          begin
             strpos:=p;
             exit;
          end;
        inc(p);
        p:=strscan(p,str2^);
      end;
  end;


function strnew(p : pwidechar) : pwidechar; overload;
  var
    len: sizeint;
  begin
    len:=strlen(p)+1;
    result:=WideStrAlloc(Len);
    if result<>nil then
      strmove(result,p,len);
  end;


function WideStrAlloc(Size: cardinal): PWideChar;
  begin
    getmem(result,size*2+sizeof(cardinal));
    PCardinal(result)^:=size*2+sizeof(cardinal);
    result:=PWideChar(PByte(result)+sizeof(cardinal));
  end;

function StrBufSize(str: pwidechar): cardinal;
  begin
    if assigned(str) then
      result:=(PCardinal(PByte(str)-sizeof(cardinal))^)-sizeof(cardinal)
    else
      result := 0;
  end;

procedure StrDispose(str: pwidechar);
begin
  if assigned(str) then
   begin
     str:=PWideChar(PByte(str)-sizeof(cardinal));
     freemem(str,PCardinal(str)^);
   end;
end;



function BytesOf(const Val: UnicodeString): TBytes;
begin
  Result:=TEncoding.Default.GetBytes(Val);
end;


function BytesOf(const Val: WideChar): TBytes; overload;
begin
  Result:=TEncoding.Default.GetBytes(Val);
end;

function StringOf(const Bytes: TBytes): UnicodeString;
begin
  Result:=TEncoding.Default.GetString(Bytes);
end;


function WideBytesOf(const Value: UnicodeString): TBytes;
var
  Len:Integer;
begin
  Len:=Length(Value)*SizeOf(UnicodeChar);
  SetLength(Result,Len);
  if Len>0 then
    Move(Value[1],Result[0],Len);
end;

function WideStringOf(const Value: TBytes): UnicodeString;
var
  Len:Integer;
begin
  Len:=Length(Value) div SizeOf(UnicodeChar);
  SetLength(Result,Len);
  if Len>0 then
    Move(Value[0],Result[1],Len*SizeOf(UnicodeChar));
end;

function ByteLength(const S: UnicodeString): Integer;
begin
  Result:=Length(S)*SizeOf(UnicodeChar);
end;

{$macro on}
{$define INUNICODESTRINGREPLACE}
{$define SRString:=UnicodeString}
{$define SRUpperCase:=UnicodeUppercase}
{$define SRPCHAR:=PUnicodeChar}
{$define SRCHAR:=UnicodeChar}

Function UnicodeStringReplace(const S, OldPattern, NewPattern: Unicodestring;  Flags: TReplaceFlags): Unicodestring;

Var
  C : Integer;

begin
  Result:=UnicodeStringReplace(S,OldPattern,NewPattern,Flags,C);
end;

Function StringReplace(const S : UnicodeString; OldPattern, NewPattern: WideChar;  Flags: TReplaceFlags): Unicodestring;

Var
  C : Integer;

begin
  Result:=UnicodeStringReplace(S,OldPattern,NewPattern,Flags,C);
end;

function UnicodeStringReplace(const S, OldPattern, NewPattern: UnicodeString;  Flags: TReplaceFlags; Out aCount : Integer): UnicodeString;
{$i syssr.inc}

{$undef INUNICODESTRINGREPLACE}
{$undef SRString}
{$undef SRUpperCase}
{$undef SRPCHAR}
{$undef SRCHAR}

function StringReplace(const S, OldPattern, NewPattern: UnicodeString;  Flags: TReplaceFlags): UnicodeString;

begin
  Result:=UnicodeStringReplace(S,OldPattern,NewPattern,Flags);
end;

function StringReplace(const S, OldPattern, NewPattern: UnicodeString;  Flags: TReplaceFlags; Out aCount : Integer): UnicodeString;

begin
  Result:=UnicodeStringReplace(S,OldPattern,NewPattern,Flags,aCount);
end;
