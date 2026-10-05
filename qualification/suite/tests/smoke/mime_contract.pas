program mime_contract;
{$mode delphi}{$H+}{$codepage utf8}

{ System.Net.Mime over mORMot's THttpMultiPartStream (planning contract
  3.1).  The body is split at the boundary the object announces and every
  part is checked for its Content-Disposition, Content-Type and content; the
  file part is streamed from a temporary file.  The HTTP gate additionally
  has a server parse an upload with Python's email package. }

uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes, System.Net.Mime;

var
  Failures: Integer;
  PartReads, PartDestroys: Integer;

type
  TTrackedPart = class(TMemoryStream)
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

destructor TTrackedPart.Destroy;
begin
  Inc(PartDestroys);
  inherited Destroy;
end;

function TTrackedPart.Read(var Buffer; Count: Longint): Longint;
begin
  Inc(PartReads);
  Result := inherited Read(Buffer, Count);
end;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

function ReadAll(S: TStream): TBytes;
begin
  Result := nil;
  S.Position := 0;
  SetLength(Result, S.Size);
  If S.Size > 0 then
    S.ReadBuffer(Result[0], S.Size);
end;

function BytesPos(const Needle, Hay: TBytes; From: Integer): Integer;
var
  I, J: Integer;
begin
  for I := From to Length(Hay) - Length(Needle) do begin
    J := 0;
    while (J < Length(Needle)) and (Hay[I + J] = Needle[J]) do
      Inc(J);
    If J = Length(Needle) then
      Exit(I);
  end;
  Result := -1;
end;

type
  TPart = record
    Headers: string;
    Content: TBytes;
  end;

{ the parts between --boundary CRLF and CRLF --boundary; the closing
  --boundary-- ends the body }
function SplitParts(const Body: TBytes; const Boundary: string; out Closed: Boolean): TArray<TPart>;
var
  Delim, Close, CRLF2: TBytes;
  P, Q, H: Integer;
  Part: TPart;
begin
  Result := nil;
  Delim := TEncoding.ASCII.GetBytes('--' + Boundary + #13#10);
  Close := TEncoding.ASCII.GetBytes(#13#10'--' + Boundary + '--'#13#10);
  CRLF2 := TEncoding.ASCII.GetBytes(#13#10#13#10);
  Closed := BytesPos(Close, Body, 0) >= 0;
  P := BytesPos(Delim, Body, 0);
  while P >= 0 do begin
    P := P + Length(Delim);
    H := BytesPos(CRLF2, Body, P);
    If H < 0 then
      Break;
    Part.Headers := TEncoding.UTF8.GetString(Copy(Body, P, H - P));
    { the part ends before CRLF--boundary }
    Q := BytesPos(TEncoding.ASCII.GetBytes(#13#10'--' + Boundary), Body, H + 4);
    If Q < 0 then
      Break;
    Part.Content := Copy(Body, H + 4, Q - (H + 4));
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Part;
    P := BytesPos(Delim, Body, Q);
  end;
end;

function HeaderLine(const Headers, Name: string): string;
var
  L: TStringList;
  I: Integer;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := Headers;
    for I := 0 to L.Count - 1 do
      If Pos(LowerCase(Name) + ':', LowerCase(L[I])) = 1 then
        Exit(Trim(Copy(L[I], Length(Name) + 2, MaxInt)));
  finally
    L.Free;
  end;
end;

var
  F: TMultipartFormData;
  FileName: string;
  FileBytes, Body: TBytes;
  I: Integer;
  Parts: TArray<TPart>;
  Closed: Boolean;
  S: TStream;
  Twice: TBytes;
  PartHeaders: TStringList;
begin
  Failures := 0;
  FileName := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'mime-contract-' + IntToStr(GetProcessID) + '.png';
  SetLength(FileBytes, 70000);
  for I := 0 to High(FileBytes) do
    FileBytes[I] := Byte(I * 13 + 7);
  with TFileStream.Create(FileName, fmCreate) do
    try
      WriteBuffer(FileBytes[0], Length(FileBytes));
    finally
      Free;
    end;
  F := TMultipartFormData.Create;
  try
    F.AddField('caption', 'Фото → тест');
    F.AddField('typed', '{"a":1}', 'application/json');
    F.AddFile('photo', FileName, 'image/x-test');
    { file parts from memory: bytes, an owned stream read from its position }
    F.AddBytes('doc', TEncoding.UTF8.GetBytes('bytes-part'), 'doc.txt', 'text/plain');
    S := TMemoryStream.Create;
    S.WriteBuffer(FileBytes[0], 16);
    S.Position := 4;
    F.AddStream('tail', S, True, 'tail.bin');
    Check(Pos('multipart/form-data; boundary=', F.MimeTypeHeader) = 1, 'MimeTypeHeader: ' + F.MimeTypeHeader);
    Check((F.Boundary <> '') and (F.MimeTypeHeader = 'multipart/form-data; boundary=' + F.Boundary), 'Boundary');
    Body := ReadAll(F.Stream);
    Parts := SplitParts(Body, F.Boundary, Closed);
    Check(Closed, 'body closed with --boundary--');
    Check(Length(Parts) = 5, 'five parts: ' + IntToStr(Length(Parts)));
    If Length(Parts) = 5 then begin
      Check((Pos('name="doc"', Parts[3].Headers) > 0) and (Pos('filename="doc.txt"', Parts[3].Headers) > 0) and
            (HeaderLine(Parts[3].Headers, 'Content-Type') = 'text/plain') and
            (TEncoding.UTF8.GetString(Parts[3].Content) = 'bytes-part'), 'AddBytes part: ' + Parts[3].Headers);
      Check((Pos('name="tail"', Parts[4].Headers) > 0) and (Pos('filename="tail.bin"', Parts[4].Headers) > 0) and
            (Length(Parts[4].Content) = 12) and CompareMem(@Parts[4].Content[0], @FileBytes[4], 12),
        'AddStream part from the stream position: ' + Parts[4].Headers);
      Check(Pos('form-data; name="caption"', HeaderLine(Parts[0].Headers, 'Content-Disposition')) > 0, 'caption disposition: ' + Parts[0].Headers);
      Check(TEncoding.UTF8.GetString(Parts[0].Content) = 'Фото → тест', 'caption UTF-8 content');
      Check(Pos('form-data; name="typed"', HeaderLine(Parts[1].Headers, 'Content-Disposition')) > 0, 'typed disposition');
      Check(Pos('application/json', HeaderLine(Parts[1].Headers, 'Content-Type')) = 1, 'explicit field Content-Type: ' + Parts[1].Headers);
      Check((Pos('form-data; name="photo"', HeaderLine(Parts[2].Headers, 'Content-Disposition')) > 0) and
            (Pos('filename="' + ExtractFileName(FileName) + '"', Parts[2].Headers) > 0), 'file disposition: ' + Parts[2].Headers);
      Check(HeaderLine(Parts[2].Headers, 'Content-Type') = 'image/x-test', 'file Content-Type: ' + Parts[2].Headers);
      Check((Length(Parts[2].Content) = Length(FileBytes)) and CompareMem(@Parts[2].Content[0], @FileBytes[0], Length(FileBytes)),
        'file content streamed intact');
    end;
    { the body reads the same a second time: one closing boundary, same size }
    Twice := ReadAll(F.Stream);
    Check(Length(Twice) = Length(Body), 'second read has the same size: ' + IntToStr(Length(Twice)) + ' vs ' + IntToStr(Length(Body)));
    Check(F.Stream.Size = Length(Body), 'Size equals the bytes read');
    try
      F.AddField('late', 'x');
      Check(False, 'AddField after reading the body accepted');
    except
      on EMultipartFormData do ;
    end;
    { a missing file fails at AddFile }
    with TMultipartFormData.Create do
      try
        AddFile('inferred', FileName);
        Body := ReadAll(Stream);
        Parts := SplitParts(Body, Boundary, Closed);
        Check((Length(Parts) = 1) and
          (HeaderLine(Parts[0].Headers, 'Content-Type') = 'image/png'), 'AddFile infers MIME type from extension');
      finally
        Free;
      end;
    with TMultipartFormData.Create do
      try
        try
          AddFile('missing', FileName + '.missing');
          Check(False, 'missing file accepted');
        except
          on E: Exception do
            Check(not (E is EMultipartFormData), 'missing file raises the file error: ' + E.ClassName);
        end;
      finally
        Free;
      end;
  finally
    F.Free;
    DeleteFile(FileName);
  end;
  { the stream outlives the object when it is not owned }
  F := TMultipartFormData.Create(False);
  try
    F.AddField('a', 'b');
    S := F.Stream;
  finally
    F.Free;
  end;
  try
    Body := ReadAll(S);
    Check(Pos('name="a"', TEncoding.UTF8.GetString(Body)) > 0, 'unowned stream survives the object');
  finally
    S.Free;
  end;
  PartHeaders := TStringList.Create;
  S := TTrackedPart.Create;
  F := TMultipartFormData.Create;
  try
    S.WriteBuffer(FileBytes[0], 16);
    S.Position := 4;
    PartHeaders.Add('X-Part: retained');
    F.AddStream('borrowed', S, False, 'body.bin', 'application/octet-stream', PartHeaders);
    Check((PartReads = 0) and (PartDestroys = 0), 'AddStream neither materializes nor frees a borrowed part');
    Body := ReadAll(F.Stream);
    Parts := SplitParts(Body, F.Boundary, Closed);
    Check((Length(Parts) = 1) and (HeaderLine(Parts[0].Headers, 'X-Part') = 'retained'), 'part headers');
    Twice := ReadAll(F.Stream);
    Check((Length(Body) = Length(Twice)) and CompareMem(@Body[0], @Twice[0], Length(Body)), 'streamed replay bytes');
    F.Free;
    F := nil;
    Check((PartDestroys = 0) and (S.Size = 16), 'borrowed part survives body destruction');
  finally
    F.Free;
    S.Free;
    PartHeaders.Free;
  end;
  PartDestroys := 0;
  F := TMultipartFormData.Create;
  try
    S := TTrackedPart.Create;
    F.AddStream('owned', S, True);
    Check(PartDestroys = 0, 'owned part remains alive before body destruction');
  finally
    F.Free;
  end;
  Check(PartDestroys = 1, 'owned part freed exactly once with body');
  F := TMultipartFormData.Create;
  try
    try
      F.AddField('bad'#13#10'Injected: value', 'x');
      Check(False, 'multipart header injection accepted');
    except
      on EMultipartFormData do ;
    end;
    Body := ReadAll(F.Stream);
    Check(TEncoding.UTF8.GetString(Body) = '--' + F.Boundary + '--'#13#10, 'empty multipart is closed and rejected part is absent');
  finally
    F.Free;
  end;
  If Failures <> 0 then begin
    WriteLn('FAILURES ', Failures);
    Halt(1);
  end;
  WriteLn('MIME_CONTRACT_PASS');
end.
