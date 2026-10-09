{
    This file is part of the MoonCompiler runtime.
    Copyright (c) 2026 by the MoonCompiler contributors

    The Delphi System.Net.HttpClient surface over mORMot's socket client.

    Provenance: written for MoonCompiler from the behavioural contract in the
    planning document "DELPHI_SURFACE_ADDITIONS_20260920" (section 3.1),
    RFC 9110/9111 (HTTP semantics), RFC 6265 (cookies), RFC 1866/3986
    (form encoding, URI resolution) and the MoonBot compatibility unit
    MoonBot.Compat.HttpClient it replaces, without Embarcadero's source.
    Audit of 2026-09-21: the contract program of the gate was also built by
    Delphi 12.2 and run against the same loopback servers (gate option
    --http-executable); where the two behaved differently Delphi's
    implementation was read to classify the difference.  No code was taken
    from it (line-level resemblance check in the journal); the differences
    kept on purpose are listed in runtime/mormot/README.md.
    Author: MoonCompiler team, 2026-09-21.

    The unit lives in runtime/mormot and is compiled into each project against
    the project's own mORMot (rule 0.2 of the planning document): the build
    drivers keep runtime/mormot on the unit path, mormot.* comes from the
    project's source= or dependency= trees.  Applications without mORMot in
    their trees cannot use this unit.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit System.Net.HttpClient;

{$mode delphi}
{$H+}
{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Classes,
  SyncObjs, Types, Generics.Collections,
  System.Net.Mime, System.Net.URLClient;

type
  ENetHTTPException = class(ENetURIException);
  ENetHTTPCertificateException = class(ENetURIException);
  ENetHTTPClientException = class(ENetURIClientException);
  ENetHTTPRequestException = class(ENetURIRequestException);
  ENetHTTPResponseException = class(ENetURIResponseException);

  { called with AReadCount = 0 before the body (AContentLength from the
    header, -1 when unknown), then after every received piece; AAbort := True
    stops receiving without an exception - the response keeps the headers and
    the truncated body }
  TReceiveDataEvent = procedure(const Sender: TObject; AContentLength, AReadCount: Int64;
    var AAbort: Boolean) of object;

  THTTPCompressionMethod = (Deflate, GZip, Brotli, Any);
  THTTPCompressionMethods = set of THTTPCompressionMethod;
  THTTPContentDecoder = procedure(Source, Destination: TStream; EncodedSize: Int64);

  { The ContentStream of a response received into the client's own stream:
    the body as the socket received it, without a copy.  The bytes stay in
    the byte string the socket filled in one allocation (Data), Memory
    points into it, Size is its length, Position is 0.  A caller that only
    reads (Memory/Size, Read, CopyFrom, ContentAsString, System.Zip) never
    causes a copy; the first write, resize or Clear moves the bytes to
    storage the stream owns (Data is '' from then on), after which it is an
    ordinary TMemoryStream. }
  TReceivedBody = class(TMemoryStream)
  private
    FData: RawByteString;
  protected
    function Realloc(var NewCapacity: TMemoryStreamCapacity): Pointer; override;
  public
    { takes the bytes over (AData is left empty); Position is set to the end,
      as after a write of the same bytes }
    procedure Adopt(var AData: RawByteString);
    property Data: RawByteString read FData;
  end;

  THTTPProtocolVersion = (UNKNOWN_HTTP, HTTP_1_0, HTTP_1_1, HTTP_2_0);
  TSendDataEvent = procedure(const Sender: TObject; AContentLength, AWriteCount: Int64;
    var AAbort: Boolean) of object;
  TCookie = record
  private
    FHostOnly: Boolean;
  public
    Name, Value, Domain, Path: string;
    Expires: TDateTime;
    Secure, HttpOnly: Boolean;
    class function Create(const Data: string; const URI: System.Net.URLClient.TURI): TCookie; static;
    function ToString: string;
    function GetServerCookie: string;
  end;
  TCookies = class(TList<TCookie>);
  TCookiesArray = array of TCookie;

  IHTTPResponse = interface(IURLResponse)
    ['{ED07313B-324B-448F-84AD-F199D38981DA}']
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetHeaderValue(const AName: string): string;
    function GetContentEncoding: string;
    function GetContentCharSet: string;
    function GetContentLanguage: string;
    function GetContentLength: Int64;
    function GetDate: string;
    function GetLastModified: string;
    function GetVersion: THTTPProtocolVersion;
    function ContainsHeader(const AName: string): Boolean;
    function GetCookies: TCookies;
    property ContentCharSet: string read GetContentCharSet;
    property ContentLanguage: string read GetContentLanguage;
    property ContentLength: Int64 read GetContentLength;
    property Date: string read GetDate;
    property LastModified: string read GetLastModified;
    property Version: THTTPProtocolVersion read GetVersion;
    property Cookies: TCookies read GetCookies;
    property StatusCode: Integer read GetStatusCode;
    property StatusText: string read GetStatusText;
    property HeaderValue[const AName: string]: string read GetHeaderValue;
    property ContentEncoding: string read GetContentEncoding;
  end;

  IAsyncResult = Types.IAsyncResult;

  { RFC 6265 jar. Sync and async clients retain the same session object. }
  TCookieManager = class(TInterfacedObject)
  private
    FCookies: TCookiesArray;
    FLock: TCriticalSection;
    procedure PurgeExpired;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddServerCookie(const ACookieData, ACookieURL: string);
    function CookieHeader(const AURL: string): string;
    procedure Assign(Source: TCookieManager);
    function Count: Integer;
  end;

  THTTPClient = class(TURLClient)
  private
    FHandleRedirects: Boolean;
    FMaxRedirects: Integer;
    FAutomaticDecompression: THTTPCompressionMethods;
    FCookieManager: TCookieManager;
    FSharedCookies: IInterface;
    FActiveRequest: IURLRequest;
    FOnSendData: TSendDataEvent;
    FOnReceiveData: TReceiveDataEvent;
    FOnValidateServerCertificate: TValidateCertificateEvent;
    FSocketGuard: TCriticalSection;
    FSocket: TObject;          { a TMoonHttpSocket }
    FSocketKey: string;
    FAbortRequested: Boolean;
    FConnectionDeadline: UInt64;
    FConnectionExpired: Boolean;
    procedure CheckRequest(Outcome: TNetRequestOutcome = TNetRequestOutcome.NotSent);
    function GetAccept: string;
    procedure SetAccept(const AValue: string);
    function GetAcceptLanguage: string;
    procedure SetAcceptLanguage(const AValue: string);
    function GetAcceptEncoding: string;
    procedure SetAcceptEncoding(const AValue: string);
    function GetContentType: string;
    procedure SetContentType(const AValue: string);
    function ExecuteHTTP(const AMethod, AURL: string; ASource, AResponseContent: TStream;
      const AHeaders: TNetHeaders): IHTTPResponse;
    procedure CloseSocket;
  protected
    procedure Abort; override;
    function CloneClient(const Scheme: string): TURLClient; override;
    function AsyncResultClass: TURLAsyncResultClass; override;
    function DoExecute(const Request: IURLRequest; Content: TStream; const Headers: TNetHeaders): IURLResponse; override;
  public
    constructor Create; override;
    function Execute(const Method, URL: string; const Source: TStream = nil;
      const Content: TStream = nil; const Headers: TNetHeaders = nil): IHTTPResponse; reintroduce; overload;
    function Execute(const Method: string; const URI: System.Net.URLClient.TURI; const Source: TStream = nil;
      const Content: TStream = nil; const Headers: TNetHeaders = nil): IHTTPResponse; overload;
    function Execute(const Request: IURLRequest; const Content: TStream = nil;
      const Headers: TNetHeaders = nil): IURLResponse; overload; override;
    destructor Destroy; override;
    function Get(const AURL: string; const AResponseContent: TStream = nil;
      const AHeaders: TNetHeaders = nil): IHTTPResponse;
    function Head(const AURL: string; const AHeaders: TNetHeaders = nil): IHTTPResponse;
    function Delete(const AURL: string; const AResponseContent: TStream = nil;
      const AHeaders: TNetHeaders = nil): IHTTPResponse;
    function Post(const AURL: string; const ASource: TStream; const AResponseContent: TStream = nil;
      const AHeaders: TNetHeaders = nil): IHTTPResponse; overload;
    function Post(const AURL: string; const ASource: TStrings; const AResponseContent: TStream = nil;
      const AEncoding: TEncoding = nil; const AHeaders: TNetHeaders = nil): IHTTPResponse; overload;
    function Put(const AURL: string; const ASource: TStream = nil; const AResponseContent: TStream = nil;
      const AHeaders: TNetHeaders = nil): IHTTPResponse; overload;
    function Patch(const AURL: string; const ASource: TStream = nil; const AResponseContent: TStream = nil;
      const AHeaders: TNetHeaders = nil): IHTTPResponse;
    {$i httpclient.overloads.intf.inc}
    class function EndAsyncHTTP(const AAsyncResult: IAsyncResult): IHTTPResponse; overload; static;
    class function EndAsyncHTTP(const AResponse: IHTTPResponse): IHTTPResponse; overload; static;
    property HandleRedirects: Boolean read FHandleRedirects write FHandleRedirects;
    property MaxRedirects: Integer read FMaxRedirects write FMaxRedirects;
    property AutomaticDecompression: THTTPCompressionMethods read FAutomaticDecompression write FAutomaticDecompression;
    property CookieManager: TCookieManager read FCookieManager;
    property Accept: string read GetAccept write SetAccept;
    property AcceptLanguage: string read GetAcceptLanguage write SetAcceptLanguage;
    property AcceptEncoding: string read GetAcceptEncoding write SetAcceptEncoding;
    property ContentType: string read GetContentType write SetContentType;
    property OnSendData: TSendDataEvent read FOnSendData write FOnSendData;
    property OnReceiveData: TReceiveDataEvent read FOnReceiveData write FOnReceiveData;
    property OnValidateServerCertificate: TValidateCertificateEvent
      read FOnValidateServerCertificate write FOnValidateServerCertificate;
  end;

{ Initialization-only extension hook for Moon.HttpClient.Brotli. Register before
  starting HTTP work; nil removes the decoder during unit finalization. }
procedure RegisterBrotliDecoder(Decoder: THTTPContentDecoder);

implementation

uses
  System.ZLib, DateUtils, System.NetEncoding,
  {$ifdef WINDOWS}WinSock2,{$else}Sockets, BaseUnix,{$endif}
  mormot.core.datetime,
  mormot.core.base,
  mormot.core.buffers,
  mormot.core.text,
  mormot.core.os,
  mormot.core.unicode,
  mormot.lib.openssl11,
  mormot.net.sock,
  mormot.net.http,
  mormot.net.client,
  MoonORMot.Need;

const
  DefaultUserAgent = 'Mozilla/5.0 (compatible; MoonCompiler HttpClient/1.0)';
  { a request body up to this size is sent as bytes with the headers (the
    socket would otherwise stage a stream through a 1 MB buffer) }
  SmallBodyLimit = 1 shl 20;
  BrotliModuleRequired = 'Brotli support requires Moon.HttpClient.Brotli in the project uses clause';

var
  BrotliDecoder: THTTPContentDecoder;

procedure RegisterBrotliDecoder(Decoder: THTTPContentDecoder);
begin
  BrotliDecoder := Decoder;
end;

{ mormot.core.text declares RawUtf8 overloads of these names; declared here,
  the string versions win and no UTF-8 round trip happens }
function Trim(const S: string): string; inline;
begin
  Result := SysUtils.Trim(S);
end;

function LowerCase(const S: string): string; inline;
begin
  Result := SysUtils.LowerCase(S);
end;

function UpperCase(const S: string): string; inline;
begin
  Result := SysUtils.UpperCase(S);
end;

{ ---------------------------------------------------------------------
  header helpers
  ---------------------------------------------------------------------}

function HeaderIndex(const Headers: TNetHeaders; const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Headers) do
    If SameText(Headers[I].Name, Name) then
      Exit(I);
  Result := -1;
end;

procedure SetHeader(var Headers: TNetHeaders; const Name, Value: string);
var
  I: Integer;
begin
  I := HeaderIndex(Headers, Name);
  If I < 0 then begin
    I := Length(Headers);
    SetLength(Headers, I + 1);
    Headers[I].Name := Name;
  end;
  Headers[I].Value := Value;
end;

procedure RemoveHeader(var Headers: TNetHeaders; const Name: string);
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(Headers) do
    If not SameText(Headers[I].Name, Name) then begin
      If N <> I then
        Headers[N] := Headers[I];
      Inc(N);
    end;
  SetLength(Headers, N);
end;

procedure AddHeader(var Headers: TNetHeaders; const Name, Value: string);
var
  I: Integer;
begin
  I := Length(Headers);
  SetLength(Headers, I + 1);
  Headers[I] := TNetHeader.Create(Name, Value);
end;

function ContentCharset(const ContentType: string): string;
var
  L, S: string;
  P, E: Integer;
begin
  Result := '';
  L := LowerCase(ContentType);
  P := Pos('charset=', L);
  If P = 0 then
    Exit;
  S := Trim(Copy(ContentType, P + Length('charset='), MaxInt));
  E := Pos(';', S);
  If E > 0 then
    S := Trim(Copy(S, 1, E - 1));
  If (Length(S) >= 2) and (((S[1] = '"') and (S[Length(S)] = '"')) or ((S[1] = '''') and (S[Length(S)] = ''''))) then
    S := Copy(S, 2, Length(S) - 2);
  Result := S;
end;

function CharsetNameOf(Encoding: TEncoding): string;
begin
  If (Encoding = nil) or (Encoding.CodePage = 65001) then
    Exit('utf-8');
  case Encoding.CodePage of
    1200: Result := 'utf-16';
    1201: Result := 'utf-16be';
    20866: Result := 'koi8-r';
    21866: Result := 'koi8-u';
    1250..1258: Result := 'windows-' + IntToStr(Encoding.CodePage);
    28591..28599, 28603, 28605: Result := 'iso-8859-' + IntToStr(Encoding.CodePage - 28590);
  else
    Result := LowerCase(Encoding.EncodingName);
  end;
end;

function FormEncode(const Value: string; Encoding: TEncoding): string;
const
  Hex: array[0..15] of Char = '0123456789ABCDEF';
var
  Bytes: TBytes;
  I: Integer;
  B: Byte;
begin
  If Encoding = nil then
    Encoding := TEncoding.UTF8;
  Bytes := Encoding.GetBytes(Value);
  Result := '';
  for I := 0 to High(Bytes) do begin
    B := Bytes[I];
    If B = Ord(' ') then
      Result := Result + '+'
    else If (B in [Ord('0')..Ord('9'), Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('-'), Ord('_'), Ord('.'), Ord('*')]) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + Hex[B shr 4] + Hex[B and $F];
  end;
end;

{ ---------------------------------------------------------------------
  URLs
  ---------------------------------------------------------------------}

{ RFC 3986 5.2.4: "." and ".." segments of an absolute path }
function RemoveDotSegments(const Path: string): string;
var
  Segments: TArray<string>;
  Count, I, Start: Integer;
  Segment: string;
  TrailingSlash: Boolean;
begin
  Segments := nil;
  Count := 0;
  Start := 2;   { the path starts with '/' }
  TrailingSlash := False;
  for I := 2 to Length(Path) + 1 do
    If (I > Length(Path)) or (Path[I] = '/') then begin
      Segment := Copy(Path, Start, I - Start);
      Start := I + 1;
      If Segment = '.' then
        TrailingSlash := True
      else If Segment = '..' then begin
        If Count > 0 then
          Dec(Count);
        TrailingSlash := True;
      end else begin
        If Count = Length(Segments) then
          SetLength(Segments, Count + 4);
        Segments[Count] := Segment;
        Inc(Count);
        TrailingSlash := False;
      end;
    end;
  Result := '';
  for I := 0 to Count - 1 do
    Result := Result + '/' + Segments[I];
  If (Result = '') or (TrailingSlash and (Result[Length(Result)] <> '/')) then
    Result := Result + '/';
end;

function NormalizeHttpURL(const URL: string): string; forward;
function SameOrigin(const A, B: string): Boolean; forward;

function ResolveRedirectURL(const BaseURL, Location: string): string;
var
  Base: TUri;
  Path, Loc, Query: string;
  P: Integer;
  Origin: string;
begin
  Loc := Trim(Location);
  P := Pos('#', Loc);
  If P > 0 then
    Loc := Copy(Loc, 1, P - 1);
  If (Pos('http://', LowerCase(Loc)) = 1) or (Pos('https://', LowerCase(Loc)) = 1) then
    Exit(NormalizeHttpURL(Loc));
  If not Base.From(StringToUtf8(BaseURL)) then
    Exit(Loc);
  Origin := Utf8ToString(Base.ServerPort);   { scheme://server:port/ }
  If (Origin <> '') and (Origin[Length(Origin)] = '/') then
    SetLength(Origin, Length(Origin) - 1);
  If Loc = '' then
    Exit(BaseURL);
  If Copy(Loc, 1, 2) = '//' then
    Exit(NormalizeHttpURL(Copy(Origin, 1, Pos(':', Origin)) + Loc));
  Path := '/' + Utf8ToString(Base.Address);
  If Loc[1] = '/' then begin
    Query := '';
    P := Pos('?', Loc);
    If P > 0 then begin
      Query := Copy(Loc, P, MaxInt);
      Path := Copy(Loc, 1, P - 1);
    end else
      Path := Loc;
    Exit(Origin + RemoveDotSegments(Path) + Query);
  end;
  If Loc[1] = '?' then begin
    P := Pos('?', Path);
    If P > 0 then
      Path := Copy(Path, 1, P - 1);
    Exit(Origin + Path + Loc);
  end;
  { relative to the directory of the current path }
  P := Pos('?', Path);
  If P > 0 then
    Path := Copy(Path, 1, P - 1);
  P := Length(Path);
  while (P > 0) and (Path[P] <> '/') do
    Dec(P);
  Path := Copy(Path, 1, P) + Loc;
  Query := '';
  P := Pos('?', Path);
  If P > 0 then begin
    Query := Copy(Path, P, MaxInt);
    Path := Copy(Path, 1, P - 1);
  end;
  Result := Origin + RemoveDotSegments(Path) + Query;
end;

{ scheme://authority is kept; ".." and "." in the path are removed.
  An absolute Location used to be returned as written, so "/a/../echo"
  was requested as that path and missed /echo. }
function NormalizeHttpURL(const URL: string): string;
var
  I, Q, Slash: Integer;
  Path, Query, Prefix: string;
begin
  Result := URL;
  I := Pos('://', URL);
  If I = 0 then
    Exit;
  Slash := 0;
  for I := I + 3 to Length(URL) do
    If URL[I] = '/' then begin
      Slash := I;
      Break;
    end else If URL[I] = '?' then
      Exit;
  If Slash = 0 then
    Exit;
  Prefix := Copy(URL, 1, Slash - 1);
  Path := Copy(URL, Slash, MaxInt);
  Q := Pos('?', Path);
  Query := '';
  If Q > 0 then begin
    Query := Copy(Path, Q, MaxInt);
    Path := Copy(Path, 1, Q - 1);
  end;
  Result := Prefix + RemoveDotSegments(Path) + Query;
end;

function SameOrigin(const A, B: string): Boolean;
var
  UA, UB: TUri;
begin
  Result := UA.From(StringToUtf8(A)) and UB.From(StringToUtf8(B)) and (UA.Https = UB.Https) and
    SameText(Utf8ToString(UA.Server), Utf8ToString(UB.Server)) and (UA.Port = UB.Port);
end;

{ ---------------------------------------------------------------------
  TCookieManager
  ---------------------------------------------------------------------}

{$i httpclient.cookies.inc}

{ ---------------------------------------------------------------------
  the socket: mORMot's client with two adjustments
  ---------------------------------------------------------------------}

type
  TMoonHttpSocket = class(THttpClientSocket)
  private
    FPlainProxy: Boolean;
    FCancelGuard: TCriticalSection;
    FCancelSocket: TNetSocket;
    FResponseReceived: Boolean;
    class function ReadText(var Buffer: TTextRec): Integer; static;
    procedure ReadCloseDelimitedBody(Destination: TStream);
  protected
    { mORMot always sends User-Agent; the contract sends none when the
      client's UserAgent is '' }
    procedure RequestSendHeader(const url, method: RawUtf8); override;
  public
    { the wait for the response line uses TCrtSocket.TimeOut, which only the
      constructor sets: the response timeout of the client goes here }
    procedure ApplyTimeouts(SendMs, ResponseMs: Integer);
    function CanReuse: Boolean;
    function FailureReason(E: Exception): TNetFailureReason;
    procedure RequestInternal(var Context: THttpClientRequest); override;
    procedure Abort; override;
    procedure Close; override;
    procedure ConnectCancelable(const URI: TUri; const Options: THttpRequestExtendedOptions; Client: THTTPClient);
  end;

function HTTPHost(const Server: RawUtf8): RawUtf8;
begin
  If (Pos(':', Server) > 0) and (Server[1] <> '[') then
    Result := '[' + Server + ']'
  else
    Result := Server;
end;

function NetFailureReason(Code: TNetResult): TNetFailureReason;
begin
  case Code of
    nrNotFound: Result := TNetFailureReason.DNS;
    nrClosed: Result := TNetFailureReason.ConnectionClosed;
    nrRefused: Result := TNetFailureReason.ConnectionRefused;
    nrTimeout: Result := TNetFailureReason.Timeout;
    nrInvalidParameter: Result := TNetFailureReason.InvalidParameter;
  else
    Result := TNetFailureReason.Connection;
  end;
end;

function ExceptionFailureReason(E: Exception): TNetFailureReason;
begin
  If E is ENetException then
    Result := ENetException(E).Reason
  else If E is ENetSock then
    Result := NetFailureReason(ENetSock(E).LastError)
  else
    Result := TNetFailureReason.Unknown;
end;

function IsCertificateFailure(E: Exception; const TLS: TNetTlsContext): Boolean; forward;

{$i httpclient.connect.inc}

procedure TMoonHttpSocket.RequestSendHeader(const url, method: RawUtf8);
var
  Host: RawUtf8;
begin
  If not SockIsDefined then
    Exit;
  If SockIn = nil then
    CreateSockIn;
  Host := HTTPHost(Server);
  If FPlainProxy then
    SockSend([method, ' http://', Host, ':', Port, url, ' HTTP/1.1'])
  else If (url = '') or (url[1] <> '/') then
    SockSend([method, ' /', url, ' HTTP/1.1'])
  else
    SockSend([method, ' ', url, ' HTTP/1.1']);
  If Port = DEFAULT_PORT[TLS.Enabled] then
    SockSend(['Host: ', Host])
  else
    SockSend(['Host: ', Host, ':', Port]);
  If FPlainProxy and (Tunnel.User <> '') then
    SockSend(['Proxy-Authorization: Basic ', Tunnel.UserPasswordBase64]);
  If Accept <> '' then
    SockSend(['Accept: ', Accept]);
  If UserAgent <> '' then
    SockSend(['User-Agent: ', UserAgent]);
end;

procedure TMoonHttpSocket.ApplyTimeouts(SendMs, ResponseMs: Integer);
begin
  fTimeOut := ResponseMs;
  If SockIsDefined then begin
    SendTimeout := SendMs;
    ReceiveTimeout := ResponseMs;
  end;
end;

function TMoonHttpSocket.CanReuse: Boolean;
var
  Socket: TNetSocket;
  Events: TNetEvents;
  Count: Integer;
  Value: Byte;
  Code: TNetResult;
begin
  Result := False;
  If Aborted or not SockIsDefined then
    Exit;
  If (SockIn <> nil) and (TTextRec(SockIn^).BufPos <> TTextRec(SockIn^).BufEnd) then
    Exit;
  If (fSecure <> nil) and (fSecure.ReceivePending <> 0) then
    Exit;
  Socket := fSock;
  Events := Socket.WaitFor(0, [neRead, neError]);
  If Events * [neError, neClosed] <> [] then
    Exit;
  If not (neRead in Events) then
    Exit(True);
  { Read through TLS, so tickets/key updates are not mistaken for EOF. The
    descriptor must be nonblocking: a readable partial TLS record is not a
    complete record, regardless of the high-level socket timeout. }
  If Socket.MakeAsync <> nrOK then
    Exit;
  try
    try
      Count := 1;
      If fSecure <> nil then
        Code := fSecure.Receive(@Value, Count)
      else
        Code := Socket.Recv(@Value, Count);
      Result := (Code = nrRetry) and not Aborted;
      If Result and (fSecure <> nil) then
        Result := fSecure.ReceivePending = 0;
    except
      Result := False;
    end;
  finally
    If Socket.MakeBlocking <> nrOK then
      Result := False;
  end;
end;

{$i httpclient.exchange.inc}

{ ---------------------------------------------------------------------
  streams
  ---------------------------------------------------------------------}

{ the rest of a stream, from its Position to its end, as bytes; a memory
  stream is copied straight from its memory }
function ReadRest(Source: TStream): RawByteString;
var
  Len: Int64;
begin
  Result := '';
  Len := Source.Size - Source.Position;
  If Len <= 0 then
    Exit;
  If Source is TCustomMemoryStream then begin
    FastSetRawByteString(Result, PAnsiChar(TCustomMemoryStream(Source).Memory) + Source.Position, Len);
    Source.Position := Source.Size;
  end else begin
    FastSetRawByteString(Result, nil, Len);
    Source.ReadBuffer(Pointer(Result)^, Len);
  end;
end;

type
  { the body of Post/Put/Patch: the source from its Position to its end,
    presented as a whole stream (mORMot rewinds to 0 and sends Size bytes) }
  TBodyWindow = class(TStream)
  private
    FSource: TStream;
    FStart, FLength, FPosition: Int64;
    FClient: THTTPClient;
    FLastReported: Int64;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(ASource: TStream; AClient: THTTPClient = nil);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

constructor TBodyWindow.Create(ASource: TStream; AClient: THTTPClient);
begin
  inherited Create;
  FSource := ASource;
  FClient := AClient;
  FLastReported := -1;
  FStart := ASource.Position;
  FLength := ASource.Size - FStart;
  If FLength < 0 then
    FLength := 0;
end;

function TBodyWindow.GetSize: Int64;
begin
  Result := FLength;
end;

function TBodyWindow.Read(var Buffer; Count: Longint): Longint;
var
  Stop: Boolean;
begin
  { The previous Read has been sent before mORMot asks for the next chunk.
    Report here, rather than claiming newly read bytes were already sent. }
  If (FClient <> nil) and Assigned(FClient.FOnSendData) and (FLastReported <> FPosition) then begin
    Stop := False;
    FClient.FOnSendData(FClient, FLength, FPosition, Stop);
    FLastReported := FPosition;
    If Stop then begin
      FClient.Abort;
      raise ENetHTTPClientException.CreateFailure('Upload was cancelled', TNetFailureReason.Cancelled, TNetRequestOutcome.Unknown);
    end;
  end;
  If (FClient <> nil) and (Count > 65536) then
    Count := 65536;
  If Count > FLength - FPosition then
    Count := FLength - FPosition;
  If Count <= 0 then
    Exit(0);
  FSource.Position := FStart + FPosition;
  Result := FSource.Read(Buffer, Count);
  Inc(FPosition, Result);
end;

function TBodyWindow.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
  raise EStreamError.Create('request body is read-only');
end;

function TBodyWindow.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent: FPosition := FPosition + Offset;
    soEnd: FPosition := FLength + Offset;
  end;
  If FPosition < 0 then
    FPosition := 0;
  If FPosition > FLength then
    FPosition := FLength;
  Result := FPosition;
end;

procedure TReceivedBody.Adopt(var AData: RawByteString);
begin
  Clear;
  FData := AData;
  AData := '';
  SetPointer(Pointer(FData), Length(FData));
  Position := Length(FData);
end;

function TReceivedBody.Realloc(var NewCapacity: TMemoryStreamCapacity): Pointer;
var
  Kept: PtrInt;
begin
  If FData = '' then
    Exit(inherited Realloc(NewCapacity));
  { the storage changes for the first time: the adopted bytes that still
    fit go to memory the stream owns; NewCapacity is honoured as asked }
  If NewCapacity <= 0 then
    Result := nil
  else begin
    GetMem(Result, NewCapacity);
    Kept := Size;
    If Kept > NewCapacity then
      Kept := NewCapacity;
    If Kept > 0 then
      Move(Memory^, Result^, Kept);
  end;
  FData := '';
end;

type
  { raised from the progress bridge to stop receiving; caught in Execute }
  EReceiveAborted = class(Exception);

  { forwards the body to the output stream and reports each piece; mORMot
    streams into a TStreamRedirect only for 200/206, so 3xx/4xx/5xx bodies
    come back in Http.Content and no event fires for them }
  TProgressBridge = class(TStreamRedirect)
  private
    FClient: THTTPClient;
    FSocket: TMoonHttpSocket;
    FFirstReported: Boolean;
    FAborted: Boolean;
    function ContentLengthForEvent: Int64;
    procedure Report(Sender: TStreamRedirect);
  public
    constructor Create(AClient: THTTPClient; ASocket: TMoonHttpSocket; ARedirected: TStream); reintroduce;
    function Write(const Buffer; Count: Longint): Longint; override;
    property Aborted: Boolean read FAborted;
  end;

constructor TProgressBridge.Create(AClient: THTTPClient; ASocket: TMoonHttpSocket; ARedirected: TStream);
begin
  inherited Create(ARedirected);
  FClient := AClient;
  FSocket := ASocket;
  ReportDelay := 0;
  OnProgress := Report;
end;

function TProgressBridge.ContentLengthForEvent: Int64;
begin
  If hfTransferChunked in FSocket.Http.HeaderFlags then
    Result := -1
  else
    Result := FSocket.Http.ContentLength;
  If Result < 0 then
    Result := -1;
end;

function TProgressBridge.Write(const Buffer; Count: Longint): Longint;
var
  AbortRequest: Boolean;
begin
  If not FFirstReported then begin
    FFirstReported := True;
    AbortRequest := False;
    If Assigned(FClient.FOnReceiveData) then
      FClient.FOnReceiveData(FClient, ContentLengthForEvent, 0, AbortRequest);
    If AbortRequest then begin
      FAborted := True;
      raise EReceiveAborted.Create('receive aborted before the body');
    end;
  end;
  Result := inherited Write(Buffer, Count);
end;

procedure TProgressBridge.Report(Sender: TStreamRedirect);
var
  AbortRequest: Boolean;
begin
  AbortRequest := False;
  If Assigned(FClient.FOnReceiveData) then
    FClient.FOnReceiveData(FClient, ContentLengthForEvent, Sender.ProcessedSize, AbortRequest);
  If AbortRequest then begin
    FAborted := True;
    raise EReceiveAborted.Create('receive aborted');
  end;
end;

{ ---------------------------------------------------------------------
  THTTPResponse
  ---------------------------------------------------------------------}

type
  THTTPResponse = class(TInterfacedObject, IHTTPResponse, IURLResponse, IAsyncResult)
  private
    FStatusCode: Integer;
    FVersion: THTTPProtocolVersion;
    FCookies: TCookies;
    FDone: TMultiWaitEvent;
    FContext: TObject;
    FStatusText: string;
    FHeaders: TNetHeaders;
    FStream: TStream;
    FOwnsStream: Boolean;
    FStart, FEnd: Int64;     { the received body is the bytes [FStart, FEnd) }
    FDecoded: Boolean;       { the body was inflated by AutomaticDecompression }
  public
    constructor Create(AStatusCode: Integer; const AStatusText: string; const AHeaders: TNetHeaders;
      AStream: TStream; AOwnsStream: Boolean; AStart, AEnd: Int64; ADecoded: Boolean; const URL, StatusLine: string; Context: TObject);
    destructor Destroy; override;
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetHeaders: TNetHeaders;
    function GetHeaderValue(const AName: string): string;
    function GetContentStream: TStream;
    function GetContentEncoding: string;
    function GetMimeType: string;
    function GetContentCharSet: string;
    function GetContentLanguage: string;
    function GetContentLength: Int64;
    function GetDate: string;
    function GetLastModified: string;
    function GetVersion: THTTPProtocolVersion;
    function ContainsHeader(const AName: string): Boolean;
    function GetCookies: TCookies;
    function GetAsyncResult: IAsyncResult;
    function GetAsyncContext: TObject;
    function GetAsyncWaitEvent: TMultiWaitEvent;
    function GetCompletedSynchronously: Boolean;
    function GetIsCompleted: Boolean;
    function GetIsCancelled: Boolean;
    function Cancel: Boolean;
    function ContentAsString(const AnEncoding: TEncoding = nil): string;
  end;

constructor THTTPResponse.Create(AStatusCode: Integer; const AStatusText: string; const AHeaders: TNetHeaders;
  AStream: TStream; AOwnsStream: Boolean; AStart, AEnd: Int64; ADecoded: Boolean;
  const URL, StatusLine: string; Context: TObject);
var
  H: TNetHeader;
  Cookie: TCookie;
  URI: System.Net.URLClient.TURI;
begin
  inherited Create;
  FStatusCode := AStatusCode;
  FStatusText := AStatusText;
  FHeaders := AHeaders;       { the caller's array, handed over }
  FStream := AStream;
  FStart := AStart;
  FEnd := AEnd;
  FDecoded := ADecoded;
  FContext := Context;
  FDone := TMultiWaitEvent.Create;
  FDone.SetEvent;
  FVersion := THTTPProtocolVersion.UNKNOWN_HTTP;
  If Copy(StatusLine, 1, 8) = 'HTTP/1.0' then
    FVersion := THTTPProtocolVersion.HTTP_1_0
  else If Copy(StatusLine, 1, 8) = 'HTTP/1.1' then
    FVersion := THTTPProtocolVersion.HTTP_1_1;
  FCookies := TCookies.Create;
  URI := System.Net.URLClient.TURI.Create(URL);
  for H in FHeaders do
    If SameText(H.Name, 'Set-Cookie') then begin
      Cookie := TCookie.Create(H.Value, URI);
      If Cookie.Name <> '' then
        FCookies.Add(Cookie);
    end;
  FOwnsStream := AOwnsStream;
end;

destructor THTTPResponse.Destroy;
begin
  FCookies.Free;
  FDone.Free;
  If FOwnsStream then
    FreeAndNil(FStream);
  inherited Destroy;
end;

function THTTPResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

function THTTPResponse.GetStatusText: string;
begin
  Result := FStatusText;
end;

function THTTPResponse.GetHeaders: TNetHeaders;
begin
  Result := Copy(FHeaders);
end;

function THTTPResponse.GetHeaderValue(const AName: string): string;
var
  I: Integer;
begin
  I := HeaderIndex(FHeaders, AName);
  If I >= 0 then
    Result := FHeaders[I].Value
  else
    Result := '';
end;

function THTTPResponse.GetContentStream: TStream;
begin
  Result := FStream;
end;

function THTTPResponse.GetContentEncoding: string;
begin
  Result := GetHeaderValue('Content-Encoding');
end;

type
  { TEncoding decodes from a pointer only through its strict protected
    GetCharCount/GetChars, reachable from a descendant's own method: the
    bytes at P decoded by Encoding straight from where they lie - the same
    two calls TEncoding.GetString makes, without the TBytes in between }
  TEncodingFromMemory = class(TEncoding)
    class function Decode(Encoding: TEncoding; P: PByte; Len: Integer): string; static;
  end;

class function TEncodingFromMemory.Decode(Encoding: TEncoding; P: PByte; Len: Integer): string;
var
  Chars: Integer;
  Text: UnicodeString;
begin
  Result := '';
  If (P = nil) or (Len <= 0) then
    Exit;
  Chars := TEncodingFromMemory(Encoding).GetCharCount(P, Len);
  If Chars <= 0 then
    Exit;
  SetLength(Text, Chars);
  Chars := TEncodingFromMemory(Encoding).GetChars(P, Len, PUnicodeChar(Pointer(Text)), Chars);
  If Chars <> Length(Text) then
    SetLength(Text, Chars);
  Result := Text;
end;

{ inflates Source from its position up to SourceEnd into Dest.  A complete
  member is required: TZDecompressionStream treats a short read as "what we
  got", and a truncated gzip would come back as a successful partial body.
  A "deflate" body may be zlib-wrapped (RFC 1950) or raw (RFC 1951). }
procedure InflateBody(Source, Dest: TStream; SourceEnd: Int64; GZip: Boolean);
var
  StartSource, StartDest: Int64;
  WindowBits, Code: Integer;

  function Run(Bits: Integer): Integer;
  var
    Strm: z_stream;
    InBuf, OutBuf: array[0..65535] of Byte;
    Got, Produced, Before: Integer;
    Left: Int64;
  begin
    Strm := Default(z_stream);
    Result := inflateInit2(Strm, Bits);
    If Result <> Z_OK then
      Exit;
    try
      repeat
        If Strm.avail_in = 0 then begin
          Left := SourceEnd - Source.Position;
          If Left > 0 then begin
            If Left > SizeOf(InBuf) then
              Left := SizeOf(InBuf);
            Got := Source.Read(InBuf, Left);
            If Got <= 0 then
              Exit(Z_BUF_ERROR);
            Strm.next_in := @InBuf[0];
            Strm.avail_in := Got;
          end;
          { With no input left, inflate may still have pending output. }
        end;
        Before := Strm.avail_in;
        Strm.next_out := @OutBuf[0];
        Strm.avail_out := SizeOf(OutBuf);
        Result := inflate(Strm, Z_NO_FLUSH);
        Produced := SizeOf(OutBuf) - Integer(Strm.avail_out);
        If Produced > 0 then
          Dest.WriteBuffer(OutBuf[0], Produced);
        If Result = Z_STREAM_END then
          Exit;
        If (Result <> Z_OK) and (Result <> Z_BUF_ERROR) then
          Exit;
        If (Produced = 0) and (Integer(Strm.avail_in) = Before) then
          Exit(Z_BUF_ERROR);
      until False;
    finally
      inflateEnd(Strm);
    end;
  end;

begin
  StartSource := Source.Position;
  StartDest := Dest.Position;
  If GZip then
    WindowBits := 31
  else
    WindowBits := 15;
  repeat
    Source.Position := StartSource;
    Dest.Position := StartDest;
    Dest.Size := StartDest;
    Code := Run(WindowBits);
    If Code = Z_STREAM_END then
      Exit;
    If (not GZip) and (WindowBits = 15) and (Code = Z_DATA_ERROR) then
      WindowBits := -15                 { raw deflate on the second attempt }
    else
      raise ENetHTTPResponseException.CreateFailure('Cannot decode the compressed body (' + IntToStr(Code) + ')',
        TNetFailureReason.Protocol, TNetRequestOutcome.ResponseReceived);
  until False;
end;

procedure DecodeBody(Source, Dest: TStream; SourceEnd: Int64; const Coding: string);
begin
  If SameText(Coding, 'br') then begin
    If not Assigned(BrotliDecoder) then
      raise ENetHTTPResponseException.CreateFailure(BrotliModuleRequired, TNetFailureReason.InvalidParameter,
        TNetRequestOutcome.ResponseReceived);
    BrotliDecoder(Source, Dest, SourceEnd - Source.Position);
  end else
    InflateBody(Source, Dest, SourceEnd, SameText(Coding, 'gzip'));
end;

function THTTPResponse.ContentAsString(const AnEncoding: TEncoding): string;
var
  Encoding: TEncoding;
  OwnsEncoding: Boolean;
  Charset, Coding: string;
  Raw: TMemoryStream;
  Bytes: TBytes;
  Size: Int64;
begin
  Result := '';
  If FStream = nil then
    Exit;
  Encoding := AnEncoding;
  OwnsEncoding := False;
  If Encoding = nil then begin
    Charset := ContentCharset(GetHeaderValue('Content-Type'));
    If (Charset <> '') and not SameText(Charset, 'utf-8') and not SameText(Charset, 'utf8') then begin
      try
        Encoding := TEncoding.GetEncoding(Charset);
      except
        on EEncodingError do
          raise EEncodingError.Create('Unsupported HTTP response charset');
      end;
      OwnsEncoding := True;
    end else
      Encoding := TEncoding.UTF8;
  end;
  try
    FStream.Position := FStart;
    Coding := Trim(GetContentEncoding);
    Raw := nil;
    try
      If (not FDecoded) and (SameText(Coding, 'gzip') or SameText(Coding, 'deflate') or SameText(Coding, 'br')) then begin
        Raw := TMemoryStream.Create;
        DecodeBody(FStream, Raw, FEnd, Coding);
        Exit(TEncodingFromMemory.Decode(Encoding, Raw.Memory, Raw.Size));
      end;
      Size := FEnd - FStart;
      { a body held in memory is decoded where it lies }
      If FStream is TCustomMemoryStream then
        Exit(TEncodingFromMemory.Decode(Encoding, PByte(TCustomMemoryStream(FStream).Memory) + FStart, Size));
      SetLength(Bytes, Size);
      If Size > 0 then
        FStream.ReadBuffer(Bytes[0], Size);
    finally
      FreeAndNil(Raw);
      FStream.Position := FStart;
    end;
    Result := Encoding.GetString(Bytes);
  finally
    If OwnsEncoding then
      FreeAndNil(Encoding);
  end;
end;

{ ---------------------------------------------------------------------
  THTTPClient
  ---------------------------------------------------------------------}

constructor THTTPClient.Create;
begin
  inherited Create;
  FConnectionTimeout := 60000;
  FSendTimeout := 60000;
  FResponseTimeout := 60000;
  FHandleRedirects := True;
  FMaxRedirects := 5;
  FCustomHeaders.Value['User-Agent'] := DefaultUserAgent;
  FCookieManager := TCookieManager.Create;
  FSharedCookies := FCookieManager;
  FSocketGuard := TCriticalSection.Create;
end;

destructor THTTPClient.Destroy;
begin
  CloseSocket;
  FreeAndNil(FSocketGuard);
  FSharedCookies := nil;
  FCookieManager := nil;
  inherited Destroy;
end;

function THTTPClient.GetAccept: string;
begin
  Result := GetCustomHeader('Accept');
end;

procedure THTTPClient.SetAccept(const AValue: string);
begin
  SetCustomHeader('Accept', AValue);
end;

function THTTPClient.GetAcceptLanguage: string;
begin
  Result := GetCustomHeader('Accept-Language');
end;

procedure THTTPClient.SetAcceptLanguage(const AValue: string);
begin
  SetCustomHeader('Accept-Language', AValue);
end;

function THTTPClient.GetAcceptEncoding: string;
begin
  Result := GetCustomHeader('Accept-Encoding');
end;

procedure THTTPClient.SetAcceptEncoding(const AValue: string);
begin
  SetCustomHeader('Accept-Encoding', AValue);
end;

function THTTPClient.GetContentType: string;
begin
  Result := GetCustomHeader('Content-Type');
end;

procedure THTTPClient.SetContentType(const AValue: string);
begin
  SetCustomHeader('Content-Type', AValue);
end;

procedure THTTPClient.CloseSocket;
var
  Socket: TObject;
begin
  FSocketGuard.Acquire;
  try
    Socket := FSocket;
    If Socket <> nil then
      TMoonHttpSocket(Socket).Abort;
    FSocket := nil;
    FSocketKey := '';
  finally
    FSocketGuard.Release;
  end;
  Socket.Free;
end;

procedure THTTPClient.Abort;
begin
  FSocketGuard.Acquire;
  try
    FAbortRequested := True;
    If FSocket <> nil then
      TMoonHttpSocket(FSocket).Abort;
  finally
    FSocketGuard.Release;
  end;
end;

{ the certificate as the TLS layer reports it: subject, issuer and the CN }
function CertificateOf(const TLS: TNetTlsContext): TCertificate;
var
  P, E: Integer;
begin
  Result := Default(TCertificate);
  Result.Subject := Utf8ToString(TLS.PeerSubject);
  Result.Issuer := Utf8ToString(TLS.PeerIssuer);
  P := Pos('CN=', Result.Subject);
  If P > 0 then begin
    E := P + 3;
    while (E <= Length(Result.Subject)) and not CharInSet(Result.Subject[E], [',', '/']) do
      Inc(E);
    Result.CertName := Trim(Copy(Result.Subject, P + 3, E - P - 3));
  end;
end;

{ a TLS failure caused by the server certificate (chain, trust, name, dates)
  as opposed to a plain connection or handshake failure: OpenSSL reports the
  X509_V_ERR in the context, SChannel puts the SEC_E/CERT_E code in the text }
function IsCertificateFailure(E: Exception; const TLS: TNetTlsContext): Boolean;
const
  Marks: array[0..12] of string = ('certificate', 'x509', 'untrusted', 'cert_e_', 'wrong_principal',
    '80090325',   { SEC_E_UNTRUSTED_ROOT }
    '80090327',   { SEC_E_CERT_UNKNOWN }
    '80090328',   { SEC_E_CERT_EXPIRED }
    '80090322',   { SEC_E_WRONG_PRINCIPAL: host name mismatch }
    '800b0109',   { CERT_E_UNTRUSTEDROOT }
    '800b010f',   { CERT_E_CN_NO_MATCH }
    '800b0101',   { CERT_E_EXPIRED }
    '800b010a');  { CERT_E_CHAINING }
var
  M, Mark: string;
begin
  If TLS.LastError <> '' then
    Exit(True);
  M := LowerCase(E.Message);
  for Mark in Marks do
    If Pos(Mark, M) > 0 then
      Exit(True);
  Result := False;
end;

{$i httpclient.auth.inc}

{ Lower-layer messages may contain credentials or peer-controlled text. Keep
  the error category and the socket's fixed result name, never its message. }
function TransportErrorKind(E: Exception): string;
begin
  Result := E.ClassName;
  If E is ENetSock then
    Result := Result + ': ' + string(ToText(ENetSock(E).LastError)^);
end;

function THTTPClient.ExecuteHTTP(const AMethod, AURL: string; ASource, AResponseContent: TStream;
  const AHeaders: TNetHeaders): IHTTPResponse;
var
  Output: TStream;
  OwnsOutput: Boolean;
  OriginalPosition: Int64;
  Proxy: TProxySettings;
  ProxyCredential: TCredentialsStorage.TCredential;
  Method, URL, Location, StartURL, RequestURL: string;
  Body: TStream;
  RequestHeaders, ReplyHeaders: TNetHeaders;
  Hops: Integer;
  Status: Integer;
  Socket: TMoonHttpSocket;
  Bridge: TProgressBridge;
  HeaderText, DataType: RawUtf8;
  I: Integer;
  Truncated, Decoded, BodyDropped: Boolean;
  Coding: string;
  Data: RawByteString;       { the request body when it is small enough }
  HasBody, Adoptable: Boolean;
  Reused, Retried: Boolean;
  AuthURL, AuthValue: string;
  AuthTried: Boolean;

  function Authenticate: Boolean;
  var
    Realm: string;
    Credential: TCredentialsStorage.TCredential;
    Persistence: TAuthPersistenceType;
    AbortAuth: Boolean;
  begin
    Result := False;
    If AuthTried or not BasicChallengeRealm(ReplyHeaders, Realm) then
      Exit;
    AuthTried := True;
    Credential := Default(TCredentialsStorage.TCredential);
    If FCredentialsStorage <> nil then
      Credential := FCredentialsStorage.FindAccurateCredential(TAuthTargetType.Server, Realm, URL);
    Persistence := TAuthPersistenceType.Request;
    AbortAuth := False;
    If Credential.IsEmpty then begin
      Credential := TCredentialsStorage.TCredential.Create(TAuthTargetType.Server, Realm, URL, '', '');
      If Assigned(FAuthEvent) then
        FAuthEvent(Self, TAuthTargetType.Server, Realm, URL, Credential.UserName, Credential.Password, AbortAuth, Persistence)
      else If Assigned(FAuthCallback) then
        FAuthCallback(Self, TAuthTargetType.Server, Realm, URL, Credential.UserName, Credential.Password, AbortAuth, Persistence);
    end;
    If AbortAuth or Credential.IsEmpty then
      Exit;
    AuthValue := BasicAuthorization(Credential.UserName, Credential.Password);
    AuthURL := URL;
    If (Persistence = TAuthPersistenceType.Client) and (FCredentialsStorage <> nil) then
      FCredentialsStorage.AddCredential(Credential);
    Result := True;
  end;

  function OpenSocket(const URI: TUri; IgnoreCertificate: Boolean; out TLS: TNetTlsContext): TMoonHttpSocket;
  var
    Options: THttpRequestExtendedOptions;
  begin
    CheckRequest;
    TLS := Default(TNetTlsContext);
    Options.Init;
    Options.Proxy := StringToUtf8(Proxy.ToString);
    Options.CreateTimeoutMS := FConnectionTimeout;
    Options.RedirectMax := 0;
    Options.UserAgent := StringToUtf8(UserAgent);
    Options.TLS.IgnoreCertificateErrors := IgnoreCertificate;
    Options.TLS.HostNamesCsv := URI.Server;
    FSocketGuard.Acquire;
    try
      Result := TMoonHttpSocket.Create(FConnectionTimeout);
      FSocket := Result;
      If (FConnectionDeadline = 0) and (FConnectionTimeout > 0) then
        FConnectionDeadline := SysUtils.GetTickCount64 + UInt64(FConnectionTimeout);
    finally
      FSocketGuard.Release;
    end;
    try
      try
        Result.ConnectCancelable(URI, Options, Self);
        CheckRequest;
      finally
        TLS := Result.TLS;
      end;
    except
      CloseSocket;
      raise;
    end;
  end;

  { the connection for URI: the kept one when it is to the same origin and
    still open (Reused = True), otherwise a new one }
  function EnsureSocket(const URI: TUri; out Reused: Boolean): TMoonHttpSocket;
  var
    Key: string;
    TLS: TNetTlsContext;
    Request: TURLRequest;
    Certificate: TCertificate;
    Accepted: Boolean;
  begin
    Key := LowerCase(Utf8ToString(URI.Server)) + ':' + Utf8ToString(URI.Port) + '|' + BoolToStr(URI.Https, True) + '|' + Proxy.ToString;
    FSocketGuard.Acquire;
    try
      Result := TMoonHttpSocket(FSocket);
      If (Result <> nil) and ((FSocketKey <> Key) or Result.Aborted or not Result.SockIsDefined) then
        Result := nil;
    finally
      FSocketGuard.Release;
    end;
    If (Result <> nil) and not Result.CanReuse then
      Result := nil;
    Reused := Result <> nil;
    If Result = nil then begin
      CloseSocket;
      try
        Result := OpenSocket(URI, False, TLS);
      except
        on E: Exception do begin
          CheckRequest;
          If not (E is ENetHTTPCertificateException) then begin
            If E is ENetHTTPClientException then
              raise;
            raise ENetHTTPClientException.CreateFailure('HTTP connection failed (' + TransportErrorKind(E) + ')', ExceptionFailureReason(E));
          end;
          If not Assigned(FOnValidateServerCertificate) then
            raise;
          { a second connection, this time ignoring the verification, gives
            the handler the certificate; when it accepts, that connection
            serves the request }
          try
            Result := OpenSocket(URI, True, TLS);
          except
            on E2: Exception do begin
              CheckRequest;
              If E2 is ENetHTTPClientException then
                raise;
              raise ENetHTTPClientException.CreateFailure('HTTP connection failed (' + TransportErrorKind(E2) + ')', ExceptionFailureReason(E2));
            end;
          end;
          try
            Certificate := CertificateOf(TLS);
            Accepted := False;
            Request := TURLRequest.Create(URL, Method);
            try
              FOnValidateServerCertificate(Self, Request, Certificate, Accepted);
              If not Accepted then
                raise ENetHTTPCertificateException.CreateFailure('Server certificate was not accepted', TNetFailureReason.TLS);
            finally
              FreeAndNil(Request);
            end;
          except
            CloseSocket;
            Result := nil;
            raise;
          end;
        end;
      end;
      FSocketGuard.Acquire;
      try
        FSocket := Result;
        FSocketKey := Key;
        FConnectionDeadline := 0;
      finally
        FSocketGuard.Release;
      end;
    end;
    Result.ApplyTimeouts(FSendTimeout, FResponseTimeout);
  end;

  function MergedHeaders: TNetHeaders;
  var
    Cookie: string;
    K: Integer;
  begin
    Result := Copy(FCustomHeaders.Headers);
    for K := 0 to High(AHeaders) do
      SetHeader(Result, AHeaders[K].Name, AHeaders[K].Value);
    { Caller credentials belong to the original origin; the jar is merged below. }
    If (URL <> StartURL) and not SameOrigin(StartURL, URL) then begin
      RemoveHeader(Result, 'Authorization');
      RemoveHeader(Result, 'Proxy-Authorization');
      RemoveHeader(Result, 'Cookie');
    end;
    If (AuthValue <> '') and (AuthURL = URL) then
      SetHeader(Result, 'Authorization', AuthValue);
    If (FAutomaticDecompression <> []) and (HeaderIndex(Result, 'Accept-Encoding') < 0) then begin
      Cookie := '';
      If (THTTPCompressionMethod.GZip in FAutomaticDecompression) or (THTTPCompressionMethod.Any in FAutomaticDecompression) then
        Cookie := 'gzip';
      If (THTTPCompressionMethod.Deflate in FAutomaticDecompression) or (THTTPCompressionMethod.Any in FAutomaticDecompression) then begin
        If Cookie <> '' then
          Cookie := Cookie + ', ';
        Cookie := Cookie + 'deflate';
      end;
      If Assigned(BrotliDecoder) and ((THTTPCompressionMethod.Brotli in FAutomaticDecompression) or
        (THTTPCompressionMethod.Any in FAutomaticDecompression)) then begin
        If Cookie <> '' then
          Cookie := Cookie + ', ';
        Cookie := Cookie + 'br';
      end;
      If Cookie <> '' then
        SetHeader(Result, 'Accept-Encoding', Cookie);
    end;
    Cookie := FCookieManager.CookieHeader(URL);
    If Cookie <> '' then begin
      K := HeaderIndex(Result, 'Cookie');
      If (K >= 0) and (Result[K].Value <> '') then
        Cookie := Result[K].Value + '; ' + Cookie;
      SetHeader(Result, 'Cookie', Cookie);
    end;
  end;

  function HeadersAsText(const Headers: TNetHeaders; HasBody: Boolean): RawUtf8;
  var
    K: Integer;
    Text: string;
  begin
    Text := '';
    for K := 0 to High(Headers) do begin
      { the socket writes these itself }
      If SameText(Headers[K].Name, 'User-Agent') or SameText(Headers[K].Name, 'Accept') or
         SameText(Headers[K].Name, 'Host') or SameText(Headers[K].Name, 'Connection') or
         SameText(Headers[K].Name, 'Keep-Alive') or SameText(Headers[K].Name, 'Content-Length') or
         (HasBody and SameText(Headers[K].Name, 'Content-Type')) then
        Continue;
      If Headers[K].Value = '' then
        Continue;
      Text := Text + Headers[K].Name + ': ' + Headers[K].Value + #13#10;
    end;
    Result := StringToUtf8(Text);
  end;

  { the header lines the socket kept as text, split in place: the array
    grows by sixteen, each name and value is decoded straight from its slice }
  function ResponseHeaders: TNetHeaders;
  var
    P, LineEnd, Colon, B, E: PUtf8Char;
    N: Integer;
  begin
    Result := nil;
    P := Pointer(Socket.Http.Headers);
    If P = nil then
      Exit;
    N := 0;
    while P^ <> #0 do begin
      LineEnd := P;
      while not (LineEnd^ in [#0, #10, #13]) do
        Inc(LineEnd);
      Colon := P;
      while (Colon < LineEnd) and (Colon^ <> ':') do
        Inc(Colon);
      If (Colon > P) and (Colon < LineEnd) then begin
        If N = Length(Result) then
          SetLength(Result, N + 16);
        { the name: up to the colon, without surrounding blanks }
        B := P;
        E := Colon;
        while (B < E) and (B^ in [' ', #9]) do
          Inc(B);
        while (E > B) and (E[-1] in [' ', #9]) do
          Dec(E);
        Result[N].Name := Utf8DecodeToString(B, E - B);
        { the value: after the colon, without surrounding blanks }
        B := Colon + 1;
        E := LineEnd;
        while (B < E) and (B^ in [' ', #9]) do
          Inc(B);
        while (E > B) and (E[-1] in [' ', #9]) do
          Dec(E);
        Result[N].Value := Utf8DecodeToString(B, E - B);
        Inc(N);
      end;
      P := LineEnd;
      while P^ in [#10, #13] do
        Inc(P);
    end;
    SetLength(Result, N);
    { the socket keeps these apart from the header text }
    If (Socket.Http.ContentType <> '') and (HeaderIndex(Result, 'Content-Type') < 0) then
      AddHeader(Result, 'Content-Type', Utf8ToString(Socket.Http.ContentType));
    If hfTransferChunked in Socket.Http.HeaderFlags then
      AddHeader(Result, 'Transfer-Encoding', 'chunked')
    else If (Socket.Http.ContentLength >= 0) and (HeaderIndex(Result, 'Content-Length') < 0) then
      AddHeader(Result, 'Content-Length', IntToStr(Socket.Http.ContentLength));
    If HeaderIndex(Result, 'Connection') < 0 then
      If hfConnectionClose in Socket.Http.HeaderFlags then
        AddHeader(Result, 'Connection', 'close')
      else If hfConnectionKeepAlive in Socket.Http.HeaderFlags then
        AddHeader(Result, 'Connection', 'keep-alive');
  end;

  function StatusTextOf: string;
  var
    S: string;
    P: Integer;
  begin
    S := Utf8ToString(Socket.Http.CommandResp);
    P := Pos(' ', S);
    If P > 0 then
      S := Copy(S, P + 1, MaxInt);
    P := Pos(' ', S);
    If P > 0 then
      Result := Trim(Copy(S, P + 1, MaxInt))
    else
      Result := '';
  end;

  procedure RewindOutput;
  begin
    If Output.Position <> OriginalPosition then begin
      Output.Size := OriginalPosition;
      Output.Position := OriginalPosition;
    end;
  end;

  function RetryConnection(Reason: TNetFailureReason): Boolean;
  begin
    Result := Reused and not Retried and not Socket.FResponseReceived and
      (Reason in [TNetFailureReason.ConnectionClosed, TNetFailureReason.Connection,
        TNetFailureReason.ConnectionRefused]) and
      ((Method = 'GET') or (Method = 'HEAD') or (Method = 'PUT') or (Method = 'DELETE'));
    If Result then begin
      CheckRequest(TNetRequestOutcome.Unknown);
      CloseSocket;
      Retried := True;
      RewindOutput;
    end;
  end;

  procedure FailTransport(const What: string; ClientSide: Boolean; Reason: TNetFailureReason);
  var
    Outcome: TNetRequestOutcome;
  begin
    If Socket.FResponseReceived then
      Outcome := TNetRequestOutcome.ResponseReceived
    else
      Outcome := TNetRequestOutcome.Unknown;
    CheckRequest(Outcome);
    CloseSocket;
    If ClientSide then
      raise ENetHTTPClientException.CreateFailure(What, Reason, Outcome)
    else
      raise ENetHTTPResponseException.CreateFailure(What, Reason, Outcome);
  end;

var
  URI: TUri;
  Redirect: Boolean;
  Inflated: TMemoryStream;
  BodyEnd: Int64;
begin
  Result := nil;
  Proxy := FProxySettings;
  ProxyCredential := FActiveRequest.Credential;
  If not ProxyCredential.IsEmpty and (ProxyCredential.AuthTarget = TAuthTargetType.Proxy) then begin
    If Proxy.Host = '' then
      raise ENetHTTPClientException.CreateFailure('Proxy credentials require a configured HTTP proxy', TNetFailureReason.InvalidParameter);
    BasicAuthorization(ProxyCredential.UserName, ProxyCredential.Password);
    Proxy.UserName := ProxyCredential.UserName;
    Proxy.Password := ProxyCredential.Password;
  end;
  If (THTTPCompressionMethod.Brotli in FAutomaticDecompression) and not Assigned(BrotliDecoder) then
    raise ENetHTTPClientException.CreateFailure(BrotliModuleRequired, TNetFailureReason.InvalidParameter);
  Method := UpperCase(AMethod);
  URL := AURL;
  StartURL := AURL;
  OwnsOutput := AResponseContent = nil;
  { without a caller stream and a progress handler the body is received
    into one exact buffer and handed over without a copy }
  Adoptable := OwnsOutput and not Assigned(FOnReceiveData);
  If OwnsOutput then
    Output := TReceivedBody.Create
  else
    Output := AResponseContent;
  OriginalPosition := Output.Position;
  Body := nil;
  Bridge := nil;
  Data := '';
  HasBody := ASource <> nil;
  try
    { a body up to 1 MB travels as bytes: the socket sends a small one in
      the same packet as the headers and needs no 1 MB staging buffer; a
      bigger one is streamed from its source }
    If HasBody then begin
      If (ASource.Size - ASource.Position <= SmallBodyLimit) and not Assigned(FOnSendData) then
        Data := ReadRest(ASource)
      else
        Body := TBodyWindow.Create(ASource, Self);
    end;
    Hops := 0;
    Truncated := False;
    BodyDropped := False;
    Retried := False;
    AuthTried := False;
    repeat
      { a URL without a scheme or a host is refused before any connection is
        tried ("localhost:8080/x" would otherwise be taken for a host name and
        wait out ConnectionTimeout); it is a URI error, as in Delphi }
      { URI fragments are client-side identifiers, never part of an HTTP target.
        Keep the original URL for response/request APIs and redirect resolution. }
      RequestURL := URL;
      I := Pos('#', RequestURL);
      If I > 0 then
        SetLength(RequestURL, I - 1);
      If (Pos('://', RequestURL) = 0) or not URI.From(StringToUtf8(RequestURL)) or (URI.Server = '') then
        raise ENetURIException.CreateFailure('Invalid request URI', TNetFailureReason.InvalidParameter);
      If not (URI.Https or SameText(Utf8ToString(URI.Scheme), 'http')) then
        raise ENetHTTPClientException.CreateFailure('Unsupported HTTP request scheme', TNetFailureReason.InvalidParameter);
      CheckRequest;
      Socket := EnsureSocket(URI, Reused);
      If FAbortRequested then begin
        CloseSocket;
        raise ENetHTTPClientException.CreateFailure('HTTP request was cancelled', TNetFailureReason.Cancelled);
      end;
      RequestHeaders := MergedHeaders;
      I := HeaderIndex(RequestHeaders, 'Accept');
      If I >= 0 then
        Socket.Accept := StringToUtf8(RequestHeaders[I].Value)
      else
        Socket.Accept := '';
      I := HeaderIndex(RequestHeaders, 'User-Agent');
      If I >= 0 then
        Socket.UserAgent := StringToUtf8(RequestHeaders[I].Value)
      else
        Socket.UserAgent := '';
      If BodyDropped then
        RemoveHeader(RequestHeaders, 'Content-Type');
      I := HeaderIndex(RequestHeaders, 'Content-Type');
      If (I >= 0) and HasBody then
        DataType := StringToUtf8(RequestHeaders[I].Value)
      else
        DataType := '';
      HeaderText := HeadersAsText(RequestHeaders, HasBody);
      { the socket keeps the last status line until the next answer
        overwrites it; a request that fails before sending must not be
        taken for one that was answered }
      Socket.Http.CommandResp := '';
      try
        If Assigned(FOnReceiveData) then begin
          Bridge := TProgressBridge.Create(Self, Socket, Output);
          try
            Status := Socket.Request(URI.Address, StringToUtf8(Method), 30000, HeaderText, Data, DataType, True, Body, Bridge);
          finally
            Truncated := Bridge.Aborted;
            Bridge.Redirected := nil;
            FreeAndNil(Bridge);
          end;
        end else If Adoptable then
          Status := Socket.Request(URI.Address, StringToUtf8(Method), 30000, HeaderText, Data, DataType, True, Body, nil)
        else
          Status := Socket.Request(URI.Address, StringToUtf8(Method), 30000, HeaderText, Data, DataType, True, Body, Output);
      except
        on EReceiveAborted do begin
          { the headers are in; the body stops here and the connection, in
            the middle of a body, cannot be reused }
          Status := StrToIntDef(Copy(Utf8ToString(Socket.Http.CommandResp), 10, 3), HTTP_SUCCESS);
          Truncated := True;
        end;
        on E: ENetSock do begin
          If RetryConnection(Socket.FailureReason(E)) then
            Continue;
          FailTransport('HTTP response transport failed (' + TransportErrorKind(E) + ')', Socket.Http.CommandResp = '', Socket.FailureReason(E));
        end;
        on E: EHttpSocket do
          FailTransport('Invalid HTTP response (' + TransportErrorKind(E) + ')', Socket.Http.CommandResp = '', Socket.FailureReason(E));
        on E: ENetException do
          raise;
        on E: Exception do
          FailTransport('HTTP request failed (' + TransportErrorKind(E) + ')', Socket.Http.CommandResp = '', ExceptionFailureReason(E));
      end;
      If FAbortRequested then begin
        FailTransport('HTTP request was cancelled', True, TNetFailureReason.Cancelled);
      end;
      { a body the socket kept in memory: every body on the adoptable path,
        otherwise any status but 200/206 (those went to the stream) }
      If Socket.Http.Content <> '' then
        If Adoptable then
          TReceivedBody(Output).Adopt(Socket.Http.Content)
        else begin
          Output.WriteBuffer(Pointer(Socket.Http.Content)^, Length(Socket.Http.Content));
          Socket.Http.Content := '';
        end;
      ReplyHeaders := ResponseHeaders;
      for I := 0 to High(ReplyHeaders) do
        If SameText(ReplyHeaders[I].Name, 'Set-Cookie') then
          FCookieManager.AddServerCookie(ReplyHeaders[I].Value, URL);
      If Truncated then
        Socket.Close;
      If (Status = 401) and not Truncated and Authenticate then begin
        RewindOutput;
        Continue;
      end;
      Redirect := FHandleRedirects and not Truncated and
        ((Status = 300) or (Status = 301) or (Status = 302) or (Status = 303) or (Status = 307) or (Status = 308));
      If Redirect then begin
        Location := Trim(Utf8ToString(Socket.Http.HeaderGetValue('LOCATION')));
        Redirect := Location <> '';
      end;
      If not Redirect then
        Break;
      If Hops >= FMaxRedirects then
        raise ENetHTTPRequestException.CreateFailure(Format('Too many HTTP redirects (%d)', [Hops]),
          TNetFailureReason.Protocol, TNetRequestOutcome.ResponseReceived);
      Inc(Hops);
      RewindOutput;
      { RFC 9110: a POST redirected with 301/302/303 becomes a GET without
        its body; 303 turns any method but HEAD into GET; 307/308 keep both }
      If ((Method = 'POST') and ((Status = 301) or (Status = 302) or (Status = 303))) or
         ((Status = 303) and (Method <> 'HEAD')) then begin
        Method := 'GET';
        FreeAndNil(Body);
        Data := '';
        HasBody := False;
        BodyDropped := True;
      end;
      URL := ResolveRedirectURL(URL, Location);
      AuthTried := False;
      AuthValue := '';
    until False;
    { the body of ASource is consumed to its end }
    If ASource <> nil then
      ASource.Position := ASource.Size;
    { automatic decompression of the final body }
    Decoded := False;
    Coding := Trim(Utf8ToString(Socket.Http.HeaderGetValue('CONTENT-ENCODING')));
    If Coding = '' then begin
      I := HeaderIndex(ReplyHeaders, 'Content-Encoding');
      If I >= 0 then
        Coding := Trim(ReplyHeaders[I].Value);
    end;
    If (FAutomaticDecompression <> []) and not Truncated and (Output.Position > OriginalPosition) and
       ((SameText(Coding, 'gzip') and ((THTTPCompressionMethod.GZip in FAutomaticDecompression) or
                                       (THTTPCompressionMethod.Any in FAutomaticDecompression))) or
        (SameText(Coding, 'deflate') and ((THTTPCompressionMethod.Deflate in FAutomaticDecompression) or
                                          (THTTPCompressionMethod.Any in FAutomaticDecompression))) or
        (Assigned(BrotliDecoder) and SameText(Coding, 'br') and ((THTTPCompressionMethod.Brotli in FAutomaticDecompression) or
                                     (THTTPCompressionMethod.Any in FAutomaticDecompression)))) then begin
      Inflated := TMemoryStream.Create;
      try
        BodyEnd := Output.Position;
        Output.Position := OriginalPosition;
        DecodeBody(Output, Inflated, BodyEnd, Coding);
        Output.Size := OriginalPosition;
        Output.Position := OriginalPosition;
        If Inflated.Size > 0 then
          Output.WriteBuffer(Inflated.Memory^, Inflated.Size);
        Decoded := True;
        { the stream now holds the plain body: the headers that described the
          coded one would only mislead (a second inflate, a wrong length) }
        RemoveHeader(ReplyHeaders, 'Content-Encoding');
        RemoveHeader(ReplyHeaders, 'Content-Length');
      finally
        FreeAndNil(Inflated);
      end;
    end;
    BodyEnd := Output.Position;
    Output.Position := OriginalPosition;
    Result := THTTPResponse.Create(Status, StatusTextOf, ReplyHeaders, Output, OwnsOutput, OriginalPosition, BodyEnd, Decoded, URL, Utf8ToString(Socket.Http.CommandResp), Self);
    OwnsOutput := False;
  finally
    FreeAndNil(Body);
    If OwnsOutput then
      FreeAndNil(Output);
  end;
end;

function THTTPClient.Get(const AURL: string; const AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := Execute('GET', AURL, nil, AResponseContent, AHeaders);
end;

function THTTPClient.Head(const AURL: string; const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := Execute('HEAD', AURL, nil, nil, AHeaders);
end;

function THTTPClient.Delete(const AURL: string; const AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := Execute('DELETE', AURL, nil, AResponseContent, AHeaders);
end;

function THTTPClient.Post(const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := Execute('POST', AURL, ASource, AResponseContent, AHeaders);
end;

function THTTPClient.Put(const AURL: string; const ASource, AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := Execute('PUT', AURL, ASource, AResponseContent, AHeaders);
end;

function THTTPClient.Patch(const AURL: string; const ASource, AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := Execute('PATCH', AURL, ASource, AResponseContent, AHeaders);
end;

{$i httpclient.overloads.impl.inc}

initialization
  TURLSchemes.RegisterURLClientScheme(THTTPClient, 'http');
  TURLSchemes.RegisterURLClientScheme(THTTPClient, 'https');
finalization
  TURLSchemes.UnRegisterURLClientScheme('http');
  TURLSchemes.UnRegisterURLClientScheme('https');
end.
