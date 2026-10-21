program cwstring_utf8_contracts;

{$mode objfpc}{$H+}{$codepage utf8}

uses
  cthreads, cwstring, SysUtils, Classes, BaseUnix, Unix, initc;

function iconv_open(ToCode,FromCode:PAnsiChar):Pointer;cdecl;external 'c';
function iconv(CD:Pointer;var Source:PAnsiChar;var Count:PtrUInt;
  var Dest:PAnsiChar;var Capacity:PtrUInt):PtrUInt;cdecl;external 'c';
function iconv_close(CD:Pointer):LongInt;cdecl;external 'c';
function dlsym(Handle:Pointer;Name:PAnsiChar):Pointer;cdecl;external 'c';

type
  TOpenCount=function:Cardinal;cdecl;

var
  Manager:TUnicodeStringManager;
  DecodeRef,EncodeRef:Pointer;
  Checks:QWord;
  OpenCount:TOpenCount;
  BeforeThreads:Cardinal;

procedure Check(Condition:Boolean;const Name:AnsiString);
begin
  if not Condition then
    begin
      WriteLn('FAIL ',Name,' check=',Checks);
      Halt(1);
    end;
  Inc(Checks);
end;

{ The native oracle applies the pre-optimization manager policy: EILSEQ
  replaces one input element; EINVAL replaces the whole incomplete tail once. }
function ReferenceDecode(Source:PAnsiChar;Count:SizeInt):UnicodeString;
var
  Dest,ResetPointer:PAnsiChar;
  Remaining,Capacity,Zero:PtrUInt;
  ErrorCode:LongInt;
begin
  Result:='';
  SetLength(Result,Count+1);
  Dest:=PAnsiChar(Result);
  Remaining:=Count;
  Capacity:=(Count+1)*2;
  while iconv(DecodeRef,Source,Remaining,Dest,Capacity)=High(PtrUInt) do
    begin
      ErrorCode:=fpgetCerrno;
      Check((ErrorCode=ESysEINVAL) or (ErrorCode=ESysEILSEQ),'native decode error');
      PWideChar(Dest)^:='?';
      Inc(Dest,2);
      Dec(Capacity,2);
      Inc(Source);
      Dec(Remaining);
      ResetPointer:=nil;
      Zero:=0;
      iconv(DecodeRef,ResetPointer,Zero,ResetPointer,Zero);
      if ErrorCode=ESysEINVAL then Break;
    end;
  SetLength(Result,Count+1-Capacity div 2);
end;

function ReferenceEncode(Input:PWideChar;Count:SizeInt):RawByteString;
var
  Source,Dest,ResetPointer:PAnsiChar;
  Remaining,Capacity,Zero:PtrUInt;
  ErrorCode:LongInt;
begin
  Result:='';
  SetLength(Result,Count*3+1);
  Source:=PAnsiChar(Input);
  Dest:=PAnsiChar(Result);
  Remaining:=Count*2;
  Capacity:=Count*3+1;
  while iconv(EncodeRef,Source,Remaining,Dest,Capacity)=High(PtrUInt) do
    begin
      ErrorCode:=fpgetCerrno;
      Check((ErrorCode=ESysEINVAL) or (ErrorCode=ESysEILSEQ),'native encode error');
      Dest^:='?';
      Inc(Dest);
      Dec(Capacity);
      Inc(Source,2);
      Dec(Remaining,2);
      ResetPointer:=nil;
      Zero:=0;
      iconv(EncodeRef,ResetPointer,Zero,ResetPointer,Zero);
      if ErrorCode=ESysEINVAL then Break;
    end;
  SetLength(Result,Count*3+1-Capacity);
  SetCodePage(Result,CP_UTF8,false);
end;

procedure TestBytes(Source:PAnsiChar;Count:SizeInt);
var
  Expected,Actual,Alias:UnicodeString;
  Bytes:RawByteString;
  Wide:WideString;
begin
  Expected:=ReferenceDecode(Source,Count);
  Actual:='prior owned content';
  Alias:=Actual;
  Manager.Ansi2UnicodeMoveProc(Source,CP_UTF8,Actual,Count);
  Check(Actual=Expected,'decode exact bytes');
  Check(Alias='prior owned content','decode COW');
  if Actual<>'' then Check(PWideChar(Actual)[Length(Actual)]=#0,'decode terminator');
  SetString(Bytes,Source,Count);
  SetCodePage(Bytes,CP_UTF8,false);
  Actual:=UnicodeString(Bytes);
  Wide:=WideString(Bytes);
  Check(Actual=Expected,'UnicodeString cast');
  Check(UnicodeString(Wide)=Expected,'WideString cast');
end;

procedure TestWords(Source:PWideChar;Count:SizeInt);
var
  Expected,Actual,Alias:RawByteString;
  Wide:UnicodeString;
begin
  Expected:=ReferenceEncode(Source,Count);
  Actual:='prior owned content';
  Alias:=Actual;
  Manager.Unicode2AnsiMoveProc(Source,Actual,CP_UTF8,Count);
  Check(Actual=Expected,'encode exact bytes');
  Check(Alias='prior owned content','encode COW');
  if Actual<>'' then
    begin
      Check(StringCodePage(Actual)=CP_UTF8,'UTF8 code page');
      Check(PAnsiChar(Actual)[Length(Actual)]=#0,'encode terminator');
    end;
  SetString(Wide,Source,Count);
  Actual:=RawByteString(UTF8String(Wide));
  Check(Actual=Expected,'UTF8String cast');
end;

{ Independent scalar goldens, not a round trip through the same codec. }
procedure Scalars;
var
  CodePoint,Count:Cardinal;
  Wide,Decoded:UnicodeString;
  Bytes:UTF8String;
  Encoded:RawByteString;
begin
  for CodePoint:=0 to $10ffff do
    begin
      if (CodePoint>=$d800) and (CodePoint<=$dfff) then Continue;
      if CodePoint<=$ffff then
        begin
          SetLength(Wide,1);
          Wide[1]:=WideChar(CodePoint);
        end
      else
        begin
          SetLength(Wide,2);
          Wide[1]:=WideChar($d800+((CodePoint-$10000) shr 10));
          Wide[2]:=WideChar($dc00+((CodePoint-$10000) and $3ff));
        end;
      if CodePoint<$80 then Count:=1
      else if CodePoint<$800 then Count:=2
      else if CodePoint<$10000 then Count:=3
      else Count:=4;
      SetLength(Bytes,Count);
      case Count of
        1:Bytes[1]:=AnsiChar(CodePoint);
        2:begin
            Bytes[1]:=AnsiChar($c0 or (CodePoint shr 6));
            Bytes[2]:=AnsiChar($80 or (CodePoint and $3f));
          end;
        3:begin
            Bytes[1]:=AnsiChar($e0 or (CodePoint shr 12));
            Bytes[2]:=AnsiChar($80 or ((CodePoint shr 6) and $3f));
            Bytes[3]:=AnsiChar($80 or (CodePoint and $3f));
          end;
        4:begin
            Bytes[1]:=AnsiChar($f0 or (CodePoint shr 18));
            Bytes[2]:=AnsiChar($80 or ((CodePoint shr 12) and $3f));
            Bytes[3]:=AnsiChar($80 or ((CodePoint shr 6) and $3f));
            Bytes[4]:=AnsiChar($80 or (CodePoint and $3f));
          end;
      end;
      Manager.Unicode2AnsiMoveProc(PWideChar(Wide),Encoded,CP_UTF8,Length(Wide));
      Check(Encoded=RawByteString(Bytes),'scalar encode');
      Manager.Ansi2UnicodeMoveProc(PAnsiChar(Bytes),CP_UTF8,Decoded,Length(Bytes));
      Check(Decoded=Wide,'scalar decode');
    end;
end;

function NextRandom(var State:Cardinal):Cardinal;
begin
  State:=State xor (State shl 13);
  State:=State xor (State shr 17);
  State:=State xor (State shl 5);
  Result:=State;
end;

procedure Boundaries;
const
  Edge:array[0..13] of Byte=(0,$41,$7f,$80,$8f,$90,$9f,$a0,$bf,$c0,$c2,$ed,$f4,$ff);
var
  Bytes:array[0..127] of AnsiChar;
  Wide:array[0..63] of WideChar;
  I,J,K,L,Count:Integer;
  State:Cardinal;
  Memory,Source:Pointer;
begin
  TestBytes(nil,0);
  TestWords(nil,0);
  for I:=0 to 255 do
    begin
      Bytes[0]:=AnsiChar(I);
      TestBytes(@Bytes,1);
      for J:=0 to 255 do
        begin
          Bytes[1]:=AnsiChar(J);
          TestBytes(@Bytes,2);
        end;
    end;
  for I:=$c0 to $ff do
    for J in Edge do
      for K in Edge do
        for L:=0 to 7 do
          begin
            Bytes[0]:=AnsiChar(I);
            Bytes[1]:=AnsiChar(J);
            Bytes[2]:=AnsiChar(K);
            for Count:=3 to 7 do Bytes[Count]:=AnsiChar($80);
            TestBytes(@Bytes,L);
            Bytes[L]:='A';
            TestBytes(@Bytes,L+1);
          end;
  for I:=0 to 65535 do
    begin
      Wide[0]:=WideChar(I);
      TestWords(@Wide,1);
    end;
  for I:=$d7ff to $e000 do
    begin
      Wide[0]:=WideChar(I);
      Wide[1]:=WideChar($dc00);
      TestWords(@Wide,2);
      Wide[1]:='A';
      TestWords(@Wide,2);
    end;
  Memory:=fpMMap(nil,8192,PROT_READ or PROT_WRITE,MAP_PRIVATE or MAP_ANONYMOUS,-1,0);
  Check(Memory<>Pointer(-1),'mmap');
  try
    Check(fpMProtect(PByte(Memory)+4096,4096,PROT_NONE)=0,'mprotect');
    State:=421;
    for I:=0 to 5000 do
      begin
        Count:=1+NextRandom(State) mod 128;
        Source:=PByte(Memory)+4096-Count;
        for J:=0 to Count-1 do PByte(Source)[J]:=Byte(NextRandom(State) shr 24);
        TestBytes(Source,Count);
        Count:=Count div 2;
        Source:=PByte(Memory)+4096-2*Count;
        TestWords(Source,Count);
      end;
  finally
    Check(fpMunmap(Memory,8192)=0,'munmap');
  end;
end;

procedure CodePages;
const
  Pages:array[0..4] of Integer=(1251,CP_UTF8,1252,CP_UTF8,1251);
var
  CP,I:Integer;
  Bytes:RawByteString;
  Wide:UnicodeString;
begin
  for CP in Pages do
    begin
      DefaultSystemCodePage:=CP;
      Bytes:=#$c0;
      SetCodePage(Bytes,CP,false);
      Wide:=UnicodeString(Bytes);
      if CP=1251 then Check(Wide=UnicodeString(#$410),'CP1251')
      else if CP=1252 then Check(Wide=UnicodeString(#$c0),'CP1252')
      else Check(Wide='?','default UTF8 invalid');
      for I:=1 to 8 do
        begin
          Manager.ThreadFiniProc;
          Manager.ThreadInitProc;
          TestBytes(PAnsiChar('A'),1);
        end;
    end;
  DefaultSystemCodePage:=CP_UTF8;
end;

type
  TConversionThread=class(TThread)
    Failed:Boolean;
    procedure Execute;override;
  end;

procedure TConversionThread.Execute;
const
  Text:UTF8String='ASCII '#0' Цена 🚀 € 漢字';
var
  I:Integer;
  Wide:UnicodeString;
  Bytes:UTF8String;
begin
  for I:=1 to 1000 do
    begin
      Wide:=UnicodeString(Text);
      Bytes:=UTF8String(Wide);
      if (Wide<>UTF8Decode(Text)) or (Bytes<>Text) then Failed:=true;
    end;
end;

procedure Threads;
var
  Workers:array[0..15] of TConversionThread;
  I:Integer;
begin
  for I:=Low(Workers) to High(Workers) do Workers[I]:=TConversionThread.Create(false);
  for I:=Low(Workers) to High(Workers) do
    begin
      Workers[I].WaitFor;
      Check(Workers[I].FatalException=nil,'parallel exception');
      Check(not Workers[I].Failed,'parallel conversion');
      Workers[I].Free;
    end;
end;

begin
  GetUnicodeStringManager(Manager);
  if ParamStr(1)<>'--threads' then
    begin
      DecodeRef:=iconv_open('UTF-16LE','UTF-8');
      EncodeRef:=iconv_open('UTF-8//TRANSLIT','UTF-16LE');
      Check((DecodeRef<>Pointer(-1)) and (EncodeRef<>Pointer(-1)),'native reference');
      try
        Scalars;
        Boundaries;
        CodePages;
      finally
        iconv_close(DecodeRef);
        iconv_close(EncodeRef);
      end;
    end;
  if ParamStr(1)='--threads' then
    begin
      Pointer(OpenCount):=dlsym(nil,'moon_utf8_open_count');
      Check(Assigned(OpenCount),'native counter loaded');
      BeforeThreads:=OpenCount();
    end;
  Threads;
  if Assigned(OpenCount) then WriteLn('CWSTRING_UTF8_THREAD_ICONV_OPENS=',OpenCount()-BeforeThreads);
  WriteLn('checks=',Checks);
  WriteLn('CWSTRING_UTF8_CONTRACTS_OK');
end.
