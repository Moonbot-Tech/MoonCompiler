program tstringstream_unicode_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Classes;

type
  TRaisingUTF8Encoding = class(TUTF8Encoding)
  strict protected
    function GetChars(Bytes: PByte; ByteCount: Integer; Chars: PUnicodeChar;
      CharCount: Integer): Integer; override;
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('TSTRINGSTREAM_UNICODE_POSITION_FAIL: ' + AMessage);
end;

function TRaisingUTF8Encoding.GetChars(Bytes: PByte; ByteCount: Integer;
  Chars: PUnicodeChar; CharCount: Integer): Integer;
begin
  Result := 0;
  raise EEncodingError.Create('injected decode failure');
end;

procedure TestChunkedReadAndPosition;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(UnicodeString('abcdef'), TEncoding.Unicode, False);
  try
    Check(Stream.Size = 12, 'UTF-16 byte size');
    Check(Stream.Position = 0, 'initial position');
    Check(Stream.ReadUnicodeString(4) = 'ab', 'first chunk');
    Check(Stream.Position = 4, 'position after first chunk');
    Check(Stream.ReadUnicodeString(4) = 'cd', 'second chunk');
    Check(Stream.Position = 8, 'position after second chunk');
    Check(Stream.ReadUnicodeString(100) = 'ef', 'oversize final chunk');
    Check(Stream.Position = Stream.Size, 'position at EOF');
    Check(Stream.ReadUnicodeString(4) = '', 'EOF read');
    Check(Stream.Position = Stream.Size, 'position remains at EOF');
    Stream.Position := 2;
    Check(Stream.ReadUnicodeString(0) = '', 'zero read');
    Check(Stream.Position = 2, 'zero read preserves position');
  finally
    Stream.Free;
  end;
end;

procedure TestEncodingAndAdjacentPath;
var
  Stream: TStringStream;
  Utf8: TEncoding;
begin
  Utf8 := TEncoding.UTF8;
  Stream := TStringStream.Create(UnicodeString('Ж€'), Utf8, False);
  try
    Check(Stream.ReadUnicodeString(Stream.Size) = 'Ж€', 'UTF-8 Unicode read');
    Check(Stream.Position = Stream.Size, 'UTF-8 position');
  finally
    Stream.Free;
  end;

  Stream := TStringStream.Create(AnsiString('abcdef'), TEncoding.ASCII, False);
  try
    Check(Stream.ReadAnsiString(2) = 'ab', 'adjacent ANSI first chunk');
    Check((Stream.Position = 2) and (Stream.ReadAnsiString(2) = 'cd'),
      'adjacent ANSI advances');
  finally
    Stream.Free;
  end;
end;

procedure TestDecodeFailurePosition;
var
  Raised: Boolean;
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(UnicodeString('abc'),
    TRaisingUTF8Encoding.Create, True);
  try
    Raised := False;
    try
      Stream.ReadUnicodeString(3);
    except
      on EEncodingError do
        Raised := True;
    end;
    Check(Raised, 'decode exception propagation');
    Check(Stream.Position = 0, 'decode exception preserves position');
  finally
    Stream.Free;
  end;
end;

begin
  try
    TestChunkedReadAndPosition;
    TestEncodingAndAdjacentPath;
    TestDecodeFailurePosition;
    WriteLn('TSTRINGSTREAM_UNICODE_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
