program net_encoding_streams_semantic;

{ R-014/R-010 (axis 3 of the text programme): position- and
  short-I/O-safe TNetEncoding streams and raw URL byte overloads.
  DCC64 canvas (netenc_oracle probe): the stream facades transform the
  REMAINING bytes from Position (base64 of 'llo' from position 2 is
  'bGxv'); a negative, at-end or past-end position returns 0 without an
  exception.  Deliberately STRICTER than DCC64: a premature EOF (a
  stream whose Read returns 0 with bytes still owed) raises instead of
  silently encoding the never-received zero tail, and the URL byte
  overloads keep raw bytes (measured DCC64 raises EEncodingError on a
  $FF byte - its byte path transcodes through Unicode). }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils, Classes, System.NetEncoding;

var
  Fails: Integer = 0;

procedure Check(const Name: AnsiString; Cond: Boolean);
begin
  if not Cond then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

type
  { a stream that lies: claims a size but delivers nothing }
  TBrokenStream = class(TMemoryStream)
  private
    FBroken: Boolean;
  public
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;

function TBrokenStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  if FBroken then
    Result := 0
  else
    Result := inherited Read(Buffer, Count);
end;

function OutText(S: TMemoryStream): AnsiString;
begin
  SetLength(Result, S.Size);
  if S.Size > 0 then
    Move(S.Memory^, Result[1], S.Size);
end;

var
  SIn: TBrokenStream;
  SOut: TMemoryStream;
  B, E: TBytes;
  R: Integer;
  Caught: Boolean;
begin
  SIn := TBrokenStream.Create;
  SOut := TMemoryStream.Create;
  try
    B := TEncoding.ASCII.GetBytes('Hello');
    SIn.Write(B[0], Length(B));

    { remaining-from-position transform (DCC canvas) }
    SIn.Position := 2;
    SOut.Clear;
    Check('enc-pos2-r', TNetEncoding.Base64.Encode(SIn, SOut) = 4);
    Check('enc-pos2-out', OutText(SOut) = 'bGxv');
    Check('enc-pos2-inpos', SIn.Position = 5);

    { at-end / past-end / negative: 0, no exception, output untouched }
    SOut.Clear;
    SIn.Position := 5;
    Check('enc-at-end', (TNetEncoding.Base64.Encode(SIn, SOut) = 0) and (SOut.Size = 0));
    SIn.Position := 100;
    Check('enc-past-end', (TNetEncoding.Base64.Encode(SIn, SOut) = 0) and (SOut.Size = 0));
    SIn.Seek(-3, soBeginning);
    Check('enc-neg-pos', (TNetEncoding.Base64.Encode(SIn, SOut) = 0) and (SOut.Size = 0));

    { URL stream decode from a position }
    SIn.Clear;
    B := TEncoding.ASCII.GetBytes('XXa%20b');
    SIn.Write(B[0], Length(B));
    SIn.Position := 2;
    SOut.Clear;
    Check('url-dec-pos2-r', TNetEncoding.URL.Decode(SIn, SOut) = 3);
    Check('url-dec-pos2-out', OutText(SOut) = 'a b');

    { Base64 stream decode from a position }
    SIn.Clear;
    B := TEncoding.ASCII.GetBytes('XXbGxv');
    SIn.Write(B[0], Length(B));
    SIn.Position := 2;
    SOut.Clear;
    Check('b64-dec-pos2-r', TNetEncoding.Base64.Decode(SIn, SOut) = 3);
    Check('b64-dec-pos2-out', OutText(SOut) = 'llo');
    SIn.Position := 100;
    SOut.Clear;
    Check('b64-dec-past-end', (TNetEncoding.Base64.Decode(SIn, SOut) = 0) and (SOut.Size = 0));

    { restore the encode fixture }
    SIn.Clear;
    B := TEncoding.ASCII.GetBytes('Hello');
    SIn.Write(B[0], Length(B));

    { premature EOF raises instead of encoding a zero tail (stricter) }
    SIn.Position := 0;
    SIn.FBroken := True;
    SOut.Clear;
    Caught := False;
    try
      TNetEncoding.Base64.Encode(SIn, SOut);
    except
      on E2: EStreamError do
        Caught := True;
    end;
    Check('premature-eof-raises', Caught);
    Check('premature-eof-output-untouched', SOut.Size = 0);
    SIn.FBroken := False;

    { raw URL bytes survive: $FF percent-encodes and round-trips
      (stricter than DCC64's EEncodingError) }
    B := TBytes.Create($FF, $01, Ord('a'));
    E := TNetEncoding.URL.Encode(B);
    Check('url-enc-bytes', TEncoding.ASCII.GetString(E) = '%FF%01a');
    B := TNetEncoding.URL.Decode(E);
    Check('url-dec-bytes', (Length(B) = 3) and (B[0] = $FF) and (B[1] = $01) and (B[2] = Ord('a')));

    { the empty input keeps its shape }
    B := nil;
    Check('url-enc-empty', Length(TNetEncoding.URL.Encode(B)) = 0);
  finally
    SIn.Free;
    SOut.Free;
  end;

  if Fails <> 0 then
    Halt(1);
  WriteLn('NET_ENCODING_STREAMS_OK');
end.
