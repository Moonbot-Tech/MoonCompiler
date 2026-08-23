{ %OPT=-O2 }

program tdelphibytestringconcatdomain1;

{$ifdef FPC}
  {$mode delphiunicode}
  {$codepage utf8}
{$endif}

const
  NamedAnsi: AnsiString = 'a';
  NamedU8: UTF8String = 'u';

function PickAnsi(const V: AnsiString): Integer; overload;
begin
  Result:=1;
end;

function PickAnsi(const V: UnicodeString): Integer; overload;
begin
  Result:=2;
end;

function PickRaw(const V: RawByteString): Integer; overload;
begin
  Result:=1;
end;

function PickRaw(const V: UnicodeString): Integer; overload;
begin
  Result:=2;
end;

function PickUtf8(const V: UTF8String): Integer; overload;
begin
  Result:=1;
end;

function PickUtf8(const V: UnicodeString): Integer; overload;
begin
  Result:=2;
end;

function MakeAnsi: AnsiString;
begin
  Result:='f';
end;

var
  RuntimeWideSeed: Word = 0;

function RuntimeWide(Value: Word): WideChar;
begin
  Result:=WideChar(Value+RuntimeWideSeed);
end;

var
  A: AnsiString;
  Expected: AnsiString;
  R: RawByteString;
  U8, U8Value, ExpectedU8: UTF8String;
  U: UnicodeString;
  W: WideChar;
begin
  A:='a';
  R:='r';
  U8:='u';
  U:='w';

  if PickAnsi(AnsiString('a')+'b')<>2 then Halt(1);
  if PickAnsi(AnsiString('a')+AnsiString('b'))<>1 then Halt(2);
  if PickAnsi(NamedAnsi+'b')<>1 then Halt(3);
  if PickAnsi(A+'b')<>1 then Halt(4);
  if PickAnsi('b'+A)<>1 then Halt(5);
  if PickAnsi(MakeAnsi+'b')<>1 then Halt(6);
  if PickAnsi(A+#233)<>1 then Halt(7);
  if PickAnsi(A+#1081)<>1 then Halt(8);
  if PickAnsi(A+WideChar(1081))<>1 then Halt(9);
  if PickAnsi(A+U)<>2 then Halt(10);

  if PickRaw(RawByteString('r')+'b')<>2 then Halt(11);
  if PickRaw(RawByteString('r')+RawByteString('b'))<>1 then Halt(12);
  if PickRaw(R+'b')<>1 then Halt(13);
  if PickRaw('b'+R)<>1 then Halt(14);
  if PickRaw(R+U)<>2 then Halt(15);

  if PickUtf8(UTF8String('u')+'b')<>2 then Halt(16);
  if PickUtf8(UTF8String('u')+UTF8String('b'))<>1 then Halt(17);
  if PickUtf8(U8+'b')<>1 then Halt(18);
  if PickUtf8('b'+U8)<>1 then Halt(19);
  if PickUtf8(U8+U)<>2 then Halt(20);

  A:='a';
  if Byte((A+#$85)[2])<>$85 then Halt(21);
  if Byte((A+#$85#$86)[2])<>$85 then Halt(22);
  if Byte((A+#$85#$86)[3])<>$86 then Halt(23);
  if Byte((A+AnsiChar($85))[2])<>$85 then Halt(24);
  if Byte((A+AnsiChar('Z'))[2])<>Ord('Z') then Halt(25);
  W:=RuntimeWide($85);
  Expected:=A+W;
  if A+Chr($85)<>Expected then Halt(26);
  Expected:=A+W;
  if A+WideChar($85)<>Expected then Halt(27);

  U8:='u';
  U8Value:=U8+#$85;
  if (StringCodePage(U8Value)<>65001) or
     (Length(U8Value)<>2) or (Byte(U8Value[2])<>$85) then Halt(28);
  U8Value:=U8+AnsiChar($85);
  if (StringCodePage(U8Value)<>65001) or
     (Length(U8Value)<>2) or (Byte(U8Value[2])<>$85) then Halt(29);
  U8Value:=NamedU8+#$85;
  if (Length(U8Value)<>2) or (Byte(U8Value[2])<>$85) then Halt(33);
  ExpectedU8:=U8+AnsiString(#$85#$86);
  if U8+#$85#$86<>ExpectedU8 then Halt(34);
  if NamedU8+#$85#$86<>ExpectedU8 then Halt(35);

  { A folded UTF8String cast is a typed literal, not a runtime byte-string
    value.  Its adjacent source literal is transcoded exactly once. }
  ExpectedU8:=U8+AnsiString(#$85);
  U8Value:=UTF8String('u')+#$85;
  if U8Value<>ExpectedU8 then Halt(30);
  U8Value:=UTF8String('u')+AnsiChar($85);
  if U8Value<>ExpectedU8 then Halt(31);
  ExpectedU8:=U8+AnsiString(#$85#$86);
  U8Value:=UTF8String('u')+#$85#$86;
  if U8Value<>ExpectedU8 then Halt(32);

  { RawByteString constants keep exact scanner bytes, but their run-time
    header carries the active source code page rather than CP_NONE. }
  R:=RawByteString('abc');
  if (R<>'abc') or (StringCodePage(R)=CP_NONE) then Halt(36);
  R:=RawByteString(#$C2);
  if (Length(R)<>1) or (Byte(R[1])<>$C2) or
     (StringCodePage(R)=CP_NONE) then Halt(37);
  R:=RawByteString('x'+#$C2);
  if (Length(R)<>2) or (Byte(R[1])<>Ord('x')) or
     (Byte(R[2])<>$C2) or (StringCodePage(R)=CP_NONE) then Halt(38);
end.
