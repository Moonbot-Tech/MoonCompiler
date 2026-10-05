{
    This file is part of the MoonCompiler runtime.
    Copyright (c) 2026 by the MoonCompiler contributors

    multipart/form-data bodies with the Delphi System.Net.Mime surface, over
    mORMot's THttpMultiPartStream.

    Provenance: written for MoonCompiler from the behavioural contract in the
    planning document "DELPHI_SURFACE_ADDITIONS_20260920" (section 3.1) and
    the MoonBot compatibility unit MoonBot.Compat.Mime it replaces.  No
    Embarcadero source, interface text or documentation excerpt was consulted
    or copied.  Author: MoonCompiler team, 2026-09-21.

    The unit lives in runtime/mormot and is compiled into each project against
    the project's own mORMot (rule 0.2 of the planning document).

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit System.Net.Mime;

{$mode delphi}
{$H+}

interface

uses
  SysUtils,
  Classes,
  mormot.net.client;

type
  { A multipart/form-data body: AddField/AddFile, then
    Client.ContentType := MimeTypeHeader; Stream.Position := 0;
    Client.Post(URL, Stream).  A file part streams its file when the body is
    read (mORMot opens it in AddFile; a missing file fails there).  mORMot
    preserves the order in which parts are added.
    Reading Stream closes the body with the final boundary; an Add* after
    that raises EMultipartFormData. }
  EMultipartFormData = class(Exception);

  TMultipartFormData = class
  private
    FStream: THttpMultiPartStream;   { a TMoonMultiPartStream }
    FOwnsStream: Boolean;
    procedure RequireOpen;
    function GetMimeTypeHeader: string;
    function GetStream: TStream;
    function GetBoundary: string;
  public
    constructor Create(AOwnsOutputStream: Boolean = True);
    destructor Destroy; override;
    procedure AddField(const AField, AValue: string; const AContentType: string = ''; const AHeaders: TStrings = nil);
    procedure AddFile(const AField, AFilePath: string; const AContentType: string = ''; const AHeaders: TStrings = nil);
    { a file part from memory: the bytes, or the stream read from its
      current position to its end (an owned stream lives until the body is freed) }
    procedure AddBytes(const AField: string; const ABytes: TBytes; const AFileName: string = '';
      const AContentType: string = ''; const AHeaders: TStrings = nil);
    procedure AddStream(const AField: string; AStream: TStream; AOwnsStream: Boolean;
      const AFileName: string = ''; const AContentType: string = ''; const AHeaders: TStrings = nil); overload;
    procedure AddStream(const AField: string; AStream: TStream;
      const AFileName: string = ''; const AContentType: string = ''; const AHeaders: TStrings = nil); overload;
    property Stream: TStream read GetStream;
    property MimeTypeHeader: string read GetMimeTypeHeader;
    property Boundary: string read GetBoundary;
  end;

implementation

uses
  mormot.core.base,
  mormot.core.buffers,
  mormot.core.unicode,
  MoonORMot.Need;

type
  { TNestedStreamReader owns each window, not necessarily its source. }
  TPartWindow = class(TStream)
  private
    FSource: TStream;
    FOwns: Boolean;
    FStart, FLength, FPosition: Int64;
  public
    constructor Create(ASource: TStream; AOwns: Boolean);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  TMoonMultiPartStream = class(THttpMultiPartStream)
  private
    FClosed: Boolean;
  public
    constructor Create;
    procedure AddPart(const Field, FileName, ContentType: string; Source: TStream; Headers: TStrings);
    procedure Flush; override;
    property Closed: Boolean read FClosed;
  end;

constructor TPartWindow.Create(ASource: TStream; AOwns: Boolean);
begin
  inherited Create;
  FSource := ASource;
  FOwns := AOwns;
  If FSource = nil then
    raise EMultipartFormData.Create('A multipart stream cannot be nil');
  FStart := FSource.Position;
  FLength := FSource.Size - FStart;
  If FLength < 0 then
    raise EMultipartFormData.Create('The stream position exceeds its size');
end;

destructor TPartWindow.Destroy;
begin
  If FOwns then
    FSource.Free;
  inherited Destroy;
end;

function TPartWindow.Read(var Buffer; Count: Longint): Longint;
begin
  If Count <= 0 then
    Exit(0);
  If Count > FLength - FPosition then
    Count := FLength - FPosition;
  FSource.Position := FStart + FPosition;
  Result := FSource.Read(Buffer, Count);
  Inc(FPosition, Result);
end;

function TPartWindow.Write(const Buffer; Count: Longint): Longint;
begin
  raise EStreamError.Create('Multipart parts are read-only');
end;

function TPartWindow.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: Result := Offset;
    soCurrent: Result := FPosition + Offset;
    soEnd: Result := FLength + Offset;
  else
    raise EStreamError.Create('Invalid stream origin');
  end;
  If (Result < 0) or (Result > FLength) then
    raise EStreamError.Create('Multipart seek outside the part');
  FPosition := Result;
end;

constructor TMoonMultiPartStream.Create;
begin
  inherited Create;
  fBound := MultiPartFormDataNewBound(fBounds);
  fMultipartContentType := 'multipart/form-data; boundary=' + fBound;
end;

function QuotedPartName(const Value: string): string;
var
  C: Char;
begin
  Result := '';
  for C in Value do begin
    If (Ord(C) < 32) or (Ord(C) = 127) then
      raise EMultipartFormData.Create('Control character in multipart name');
    If (C = '"') or (C = '\') then
      Result := Result + '\';
    Result := Result + C;
  end;
end;

procedure TMoonMultiPartStream.AddPart(const Field, FileName, ContentType: string;
  Source: TStream; Headers: TStrings);
var
  Header, Line, Kind: string;
  I, P: Integer;
begin
  { Own Source on entry, including validation failure. Only publish it after
    all user-controlled header text has been validated. }
  try
    Kind := ContentType;
    If Kind = '' then begin
      If FileName = '' then
        Kind := 'text/plain; charset=utf-8'
      else
        Kind := 'application/octet-stream';
    end;
    If (Pos(#13, Kind) <> 0) or (Pos(#10, Kind) <> 0) then
      raise EMultipartFormData.Create('Invalid multipart content type');
    Header := '--' + Utf8ToString(fBound) + #13#10 +
      'Content-Disposition: form-data; name="' + QuotedPartName(Field) + '"';
    If FileName <> '' then
      Header := Header + '; filename="' + QuotedPartName(FileName) + '"';
    Header := Header + #13#10 + 'Content-Type: ' + Kind + #13#10;
    If Headers <> nil then
      for I := 0 to Headers.Count - 1 do begin
        Line := Headers[I];
        P := Pos(':', Line);
        If (P <= 1) or (Pos(#13, Line) <> 0) or (Pos(#10, Line) <> 0) then
          raise EMultipartFormData.Create('Invalid multipart header');
        If SameText(Copy(Line, 1, P - 1), 'Content-Disposition') or
           SameText(Copy(Line, 1, P - 1), 'Content-Type') then
          raise EMultipartFormData.Create('Use multipart parameters for disposition and content type');
        Header := Header + Line + #13#10;
      end;
    Append(StringToUtf8(Header + #13#10));
    NewStream(Source);
    Source := nil;
    Append(#13#10);
  finally
    Source.Free;
  end;
end;

procedure TMoonMultiPartStream.Flush;
begin
  inherited Flush;
  FClosed := True;
end;

constructor TMultipartFormData.Create(AOwnsOutputStream: Boolean);
begin
  inherited Create;
  FOwnsStream := AOwnsOutputStream;
  FStream := TMoonMultiPartStream.Create;
end;

procedure TMultipartFormData.RequireOpen;
begin
  If TMoonMultiPartStream(FStream).Closed then
    raise EMultipartFormData.Create('The body was already read; create a new TMultipartFormData');
end;

destructor TMultipartFormData.Destroy;
begin
  If FOwnsStream then
    FreeAndNil(FStream);
  inherited Destroy;
end;

procedure TMultipartFormData.AddField(const AField, AValue: string; const AContentType: string;
  const AHeaders: TStrings);
begin
  RequireOpen;
  TMoonMultiPartStream(FStream).AddPart(AField, '', AContentType,
    TBytesStream.Create(TEncoding.UTF8.GetBytes(AValue)), AHeaders);
end;

procedure TMultipartFormData.AddFile(const AField, AFilePath: string; const AContentType: string;
  const AHeaders: TStrings);
var
  ContentType: string;
begin
  RequireOpen;
  ContentType := AContentType;
  If ContentType = '' then
    ContentType := Utf8ToString(GetMimeContentType(nil, 0, AFilePath));
  AddStream(AField, TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite), True,
    ExtractFileName(AFilePath), ContentType, AHeaders);
end;

procedure TMultipartFormData.AddBytes(const AField: string; const ABytes: System.TBytes; const AFileName: string;
  const AContentType: string; const AHeaders: TStrings);
begin
  RequireOpen;
  TMoonMultiPartStream(FStream).AddPart(AField, AFileName, AContentType,
    TBytesStream.Create(Copy(ABytes)), AHeaders);
end;

procedure TMultipartFormData.AddStream(const AField: string; AStream: TStream; AOwnsStream: Boolean;
  const AFileName: string; const AContentType: string; const AHeaders: TStrings);
var
  Window: TPartWindow;
begin
  { Take ownership before RequireOpen, just as on all other failure paths. }
  Window := TPartWindow.Create(AStream, AOwnsStream);
  try
    RequireOpen;
  except
    Window.Free;
    raise;
  end;
  TMoonMultiPartStream(FStream).AddPart(AField, AFileName, AContentType, Window, AHeaders);
end;

procedure TMultipartFormData.AddStream(const AField: string; AStream: TStream;
  const AFileName: string; const AContentType: string; const AHeaders: TStrings);
begin
  AddStream(AField, AStream, False, AFileName, AContentType, AHeaders);
end;

function TMultipartFormData.GetMimeTypeHeader: string;
begin
  Result := Utf8ToString(FStream.MultipartContentType);
end;

function TMultipartFormData.GetBoundary: string;
var
  P: Integer;
begin
  Result := GetMimeTypeHeader;
  P := Pos('boundary=', Result);
  If P > 0 then
    Result := Copy(Result, P + Length('boundary='), MaxInt)
  else
    Result := '';
end;

function TMultipartFormData.GetStream: TStream;
begin
  FStream.Flush;
  Result := FStream;
end;

end.
