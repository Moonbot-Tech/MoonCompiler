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
    writes the fields before the files, whatever the order of the calls.
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
    procedure AddField(const AField, AValue: string; const AContentType: string = '');
    procedure AddFile(const AField, AFilePath: string; const AContentType: string = '');
    { a file part from memory: the bytes, or the stream read from its
      current position to its end (an owned stream is freed here) }
    procedure AddBytes(const AField: string; const ABytes: TBytes; const AFileName: string = '';
      const AContentType: string = '');
    procedure AddStream(const AField: string; AStream: TStream; AOwnsStream: Boolean;
      const AFileName: string = ''; const AContentType: string = ''); overload;
    procedure AddStream(const AField: string; AStream: TStream;
      const AFileName: string = ''; const AContentType: string = ''); overload;
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
  { mORMot's Flush is idempotent; retain only the closed-body state used
    by RequireOpen. }
  TMoonMultiPartStream = class(THttpMultiPartStream)
  private
    FClosed: Boolean;
  public
    procedure Flush; override;
    property Closed: Boolean read FClosed;
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

procedure TMultipartFormData.AddField(const AField, AValue: string; const AContentType: string);
begin
  RequireOpen;
  FStream.AddContent(StringToUtf8(AField), RawByteString(StringToUtf8(AValue)), StringToUtf8(AContentType));
end;

procedure TMultipartFormData.AddFile(const AField, AFilePath: string; const AContentType: string);
begin
  RequireOpen;
  FStream.AddFile(StringToUtf8(AField), AFilePath, StringToUtf8(AContentType));
end;

procedure TMultipartFormData.AddBytes(const AField: string; const ABytes: System.TBytes; const AFileName: string;
  const AContentType: string);
var
  Content: RawByteString;
begin
  RequireOpen;
  SetLength(Content, Length(ABytes));
  If ABytes <> nil then
    Move(ABytes[0], Content[1], Length(ABytes));
  FStream.AddFileContent(StringToUtf8(AField), StringToUtf8(AFileName), Content, StringToUtf8(AContentType));
end;

procedure TMultipartFormData.AddStream(const AField: string; AStream: TStream; AOwnsStream: Boolean;
  const AFileName: string; const AContentType: string);
var
  Bytes: System.TBytes;
  Left: Int64;
begin
  try
    RequireOpen;
    Left := AStream.Size - AStream.Position;
    If Left < 0 then
      Left := 0;
    SetLength(Bytes, Left);
    If Left > 0 then
      AStream.ReadBuffer(Bytes[0], Left);
    AddBytes(AField, Bytes, AFileName, AContentType);
  finally
    If AOwnsStream then
      FreeAndNil(AStream);
  end;
end;

procedure TMultipartFormData.AddStream(const AField: string; AStream: TStream;
  const AFileName: string; const AContentType: string);
begin
  AddStream(AField, AStream, False, AFileName, AContentType);
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
