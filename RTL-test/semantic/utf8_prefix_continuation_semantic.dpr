program utf8_prefix_continuation_semantic;

{ Mixed UTF-8 conversion continues after an already converted ASCII prefix.
  The suffix kernels keep the established replacement-character policy for
  malformed UTF-16/UTF-8 and the pure ASCII path remains unchanged. }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

procedure Check(const Name: string; Condition: Boolean);
begin
  If not Condition then
    raise Exception.Create(Name);
end;

procedure CheckPosition(Position, Total: Integer);
var
  Source,Decoded: UnicodeString;
  Encoded: UTF8String;
begin
  Source:=StringOfChar('a',Total);
  Source[Position+1]:=#$0416;
  Encoded:=UTF8Encode(Source);
  Decoded:=UTF8Decode(Encoded);
  Check('roundtrip-'+IntToStr(Position),Decoded=Source);
  Check('length-'+IntToStr(Position),Length(Encoded)=Total+1);
  Check('prefix-'+IntToStr(Position),
    (Position=0) or (Encoded[Position]='a'));
  Check('payload-'+IntToStr(Position),
    (Byte(Encoded[Position+1])=$D0) and (Byte(Encoded[Position+2])=$96));
end;

var
  Source,Decoded: UnicodeString;
  Encoded,Malformed: UTF8String;
begin
  try
    CheckPosition(0,4096);
    CheckPosition(1,4096);
    CheckPosition(8,4096);
    CheckPosition(64,4096);
    CheckPosition(4095,4096);

    Source:=#$D83D#$DE00;
    Encoded:=UTF8Encode(Source);
    Check('surrogate-encode',(Length(Encoded)=4) and
      (Byte(Encoded[1])=$F0) and (Byte(Encoded[2])=$9F) and
      (Byte(Encoded[3])=$98) and (Byte(Encoded[4])=$80));
    Check('surrogate-roundtrip',UTF8Decode(Encoded)=Source);

    Source:='prefix'+#$D83D;
    Encoded:=UTF8Encode(Source);
    Check('invalid-surrogate',(Length(Encoded)=9) and
      (Byte(Encoded[7])=$EF) and (Byte(Encoded[8])=$BF) and
      (Byte(Encoded[9])=$BD));

    Malformed:=UTF8String('prefix');
    SetLength(Malformed,9);
    Malformed[7]:=AnsiChar($E2);
    Malformed[8]:='(';
    Malformed[9]:=AnsiChar($A1);
    Decoded:=UTF8Decode(Malformed);
    Check('malformed-prefix',Copy(Decoded,1,6)='prefix');
    Check('malformed-policy',(Length(Decoded)=9) and
      (Decoded[7]=#$FFFD) and (Decoded[8]='(') and (Decoded[9]=#$FFFD));

    WriteLn('UTF8_PREFIX_CONTINUATION_OK');
  except
    on E: Exception do begin
      WriteLn('UTF8_PREFIX_CONTINUATION_FAIL ',E.Message);
      Halt(1);
    end;
  end;
end.
