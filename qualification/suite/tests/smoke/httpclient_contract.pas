program httpclient_contract;
{$mode delphi}{$H+}{$codepage utf8}

{ System.Net.HttpClient against the loopback server of
  run_runtime_mormot_gate.py.  Arguments:
    1  http base URL            e.g. http://127.0.0.1:12345
    2  https base URL           self-signed certificate for localhost
    3  https base URL with a certificate for another host name, or '-'
    4  'trusted' when the process trusts the certificate of 2, else 'untrusted'
    5  a TCP port on 127.0.0.1 that refuses connections
  Prints FAIL lines and exits 1 on any failed check; HTTPCLIENT_CONTRACT_PASS
  otherwise.  The server records every request; the Python side checks what
  the client sent, this side checks what the client returned. }

uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes, System.ZLib, System.Net.URLClient, System.Net.HttpClient, System.Net.Mime;

var
  Failures: Integer;
  Base, TlsBase, TlsOtherBase: string;
  TlsTrusted: Boolean;
  RefusedPort: string;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

function Body(const R: IHTTPResponse): string;
begin
  Result := R.ContentAsString;
end;

function HasLine(const Text, Line: string): Boolean;
begin
  Result := Pos(#10 + Line + #10, #10 + StringReplace(Text, #13#10, #10, [rfReplaceAll]) + #10) > 0;
end;

function StartsWith(const Text, Prefix: string): Boolean;
begin
  Result := Copy(Text, 1, Length(Prefix)) = Prefix;
end;

function Fnv(P: PByte; N: Int64): string;
var
  H: Cardinal;
  I: Int64;
begin
  H := 2166136261;
  for I := 0 to N - 1 do
    H := (H xor P[I]) * 16777619;
  Result := IntToHex(H, 8);
end;

{ the stream's bytes read through Read, as a byte string }
function ReadAll(S: TStream): RawByteString;
begin
  SetLength(Result, S.Size);
  S.Position := 0;
  If S.Size > 0 then
    S.ReadBuffer(Result[1], S.Size);
end;

{ ------------------------------------------------------------------ }

{ The body of a response received into the client's own stream lies in
  memory as one block: ContentStream is a TMemoryStream whose Memory/Size
  are the body, exactly as received, Position 0 - the form MoonBot reads
  (TMemoryStream(ContentStream).Memory into a RawUtf8, no copy in between).
  The stream is still a stream: it may be written, resized and cleared.
  A request body up to 1 MB is sent as bytes with the headers, a bigger
  one is streamed; both arrive whole. }
procedure BodyInMemory;
var
  C: THTTPClient;
  R: IHTTPResponse;
  S: TStream;
  M: TMemoryStream;
  T: string;
  Bytes: RawByteString;
  I: Integer;
  Buf: array[0..3] of AnsiChar;
begin
  C := THTTPClient.Create;
  M := TMemoryStream.Create;
  try
    R := C.Get(Base + '/echo');
    S := R.ContentStream;
    Check(S is TMemoryStream, 'internal ContentStream is a TMemoryStream: ' + S.ClassName);
    Check(S.Position = 0, 'ContentStream Position 0 after the request');
    Check(S.Size = StrToInt(R.HeaderValue['Content-Length']), 'ContentStream Size is the Content-Length');
    Bytes := ReadAll(S);
    Check((Length(Bytes) = S.Size) and CompareMem(TMemoryStream(S).Memory, Pointer(Bytes), S.Size),
      'Memory holds exactly the bytes Read gives');
    Check(Copy(Bytes, 1, 9) = 'GET /echo', 'Memory starts with the body');
    {$IFDEF FPC}
    { the block is the one the socket filled: no copy was made }
    Check(S is TReceivedBody, 'internal ContentStream is the received body: ' + S.ClassName);
    Check((Pointer(TReceivedBody(S).Data) = TMemoryStream(S).Memory) and (Length(TReceivedBody(S).Data) = S.Size),
      'Memory is the received byte string itself');
    {$ENDIF}
    { the same for a body of 1 MB read in one block and a chunked one }
    R := C.Get(Base + '/big');
    S := R.ContentStream;
    Check((S is TMemoryStream) and (S.Size = 1048576) and (S.Position = 0), 'big body in memory');
    Check(Fnv(TMemoryStream(S).Memory, S.Size) = Fnv(Pointer(ReadAll(S)), S.Size), 'big body: Memory and Read agree');
    Check((PByte(TMemoryStream(S).Memory)[0] = 0) and (PByte(TMemoryStream(S).Memory)[1048575] = ((1048575 * 7) and 255)),
      'big body: first and last byte');
    R := C.Get(Base + '/big-chunked');
    S := R.ContentStream;
    Check((S is TMemoryStream) and (S.Size = 1048576) and
      (Fnv(TMemoryStream(S).Memory, S.Size) = Fnv(Pointer(ReadAll(S)), S.Size)), 'chunked body in memory');
    { the received stream behaves as a stream when written to }
    R := C.Get(Base + '/status/201');
    S := R.ContentStream;
    Bytes := ReadAll(S);
    S.Position := S.Size;
    S.WriteBuffer(PAnsiChar('!')^, 1);
    Check((S.Size = Length(Bytes) + 1) and (ReadAll(S) = Bytes + '!'), 'append keeps the received bytes: ' + string(ReadAll(S)));
    {$IFDEF FPC}
    Check(TReceivedBody(S).Data = '', 'the storage is the stream''s own after a write');
    {$ENDIF}
    S.Position := 0;
    S.WriteBuffer(PAnsiChar('ST')^, 2);
    Check(ReadAll(S) = 'STatus 201!', 'overwrite at the start: ' + string(ReadAll(S)));
    S.Size := 6;
    Check(ReadAll(S) = 'STatus', 'shrink keeps the head: ' + string(ReadAll(S)));
    S.Size := 8;
    S.Position := 6;
    S.WriteBuffer(PAnsiChar(' x')^, 2);
    Check(ReadAll(S) = 'STatus x', 'grow then write: ' + string(ReadAll(S)));
    M.Clear;
    S.Position := 0;
    M.CopyFrom(S, 0);
    Check((M.Size = 8) and (ReadAll(M) = 'STatus x'), 'CopyFrom the received stream');
    TMemoryStream(S).Clear;
    Check((S.Size = 0) and (S.Position = 0), 'Clear empties it');
    S.WriteBuffer(PAnsiChar('again')^, 5);
    Check(ReadAll(S) = 'again', 'usable after Clear');
    R := C.Get(Base + '/status/201');
    S := R.ContentStream;
    S.Position := 3;
    Check((S.Read(Buf, 4) = 4) and (Buf[0] = 't') and (Buf[3] = ' ') and (S.Position = 7), 'Read from a position');
    Check(S.Seek(-2, soEnd) = 8, 'Seek from the end');
    { ContentAsString decodes what Memory holds, as TEncoding.UTF8 does }
    R := C.Get(Base + '/charset-quoted');
    Check(Body(R) = TEncoding.UTF8.GetString(BytesOf(ReadAll(R.ContentStream))), 'ContentAsString = TEncoding.UTF8 on the bytes');
    R := C.Get(Base + '/bad-utf8');
    T := Body(R);
    Check(T = TEncoding.UTF8.GetString(BytesOf(ReadAll(R.ContentStream))), 'invalid UTF-8 decoded as TEncoding.UTF8 does');
    Check((Copy(T, 1, 2) = 'ab') and (T[3] = #$FFFD) and (Pos('cd', T) > 0) and (Pos(#$041F, T) > 0) and (T[Length(T)] = #$FFFD),
      'invalid bytes become U+FFFD, the valid ones stay');
    { request bodies: small ones go with the headers, big ones are streamed }
    M.Clear;
    M.Size := 1572864;
    for I := 0 to 1572863 do
      PByte(M.Memory)[I] := Byte((I * 13 + 5) and 255);
    M.Position := 0;
    R := C.Post(Base + '/digest', M);
    Check(Body(R) = 'len=1572864 fnv=' + Fnv(M.Memory, M.Size), '1.5 MB body streamed whole: ' + Body(R));
    Check(M.Position = M.Size, 'streamed source consumed');
    M.Size := 1048576;
    M.Position := 0;
    R := C.Post(Base + '/digest', M);
    Check(Body(R) = 'len=1048576 fnv=' + Fnv(M.Memory, M.Size), '1 MB body sent as bytes: ' + Body(R));
    M.Position := 1048576 - 10;
    R := C.Post(Base + '/digest', M);
    Check(Body(R) = 'len=10 fnv=' + Fnv(PByte(M.Memory) + 1048576 - 10, 10), 'small body from the position: ' + Body(R));
    Check(M.Position = M.Size, 'small source consumed');
    C.ContentType := 'application/json';
    M.Position := M.Size;
    R := C.Post(Base + '/echo', M);
    Check(HasLine(Body(R), 'H:content-length=0') and HasLine(Body(R), 'H:content-type=application/json'),
      'empty source: Content-Length 0 with the Content-Type: ' + Body(R));
  finally
    C.Free;
    M.Free;
  end;
end;

procedure Methods;
var
  C: THTTPClient;
  R: IHTTPResponse;
  S: TStringStream;
  M: TMemoryStream;
  T: string;
  I, J: Integer;
begin
  C := THTTPClient.Create;
  S := TStringStream.Create('hello world', TEncoding.UTF8);
  M := TMemoryStream.Create;
  try
    Check(C.ConnectionTimeout = 60000, 'ConnectionTimeout default');
    Check(C.SendTimeout = 60000, 'SendTimeout default');
    Check(C.ResponseTimeout = 60000, 'ResponseTimeout default');
    Check(C.HandleRedirects, 'HandleRedirects default');
    Check(C.MaxRedirects = 5, 'MaxRedirects default');
    Check(C.AutomaticDecompression = [], 'AutomaticDecompression default');
    Check((C.UserAgent <> '') and (Pos('Embarcadero', C.UserAgent) = 0), 'own default User-Agent: ' + C.UserAgent);
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'GET status');
    Check(R.StatusText = 'OK', 'GET reason phrase: ' + R.StatusText);
    T := Body(R);
    Check(HasLine(T, 'GET /echo'), 'GET echoed');
    Check(R.HeaderValue['x-test'] = 'yes', 'HeaderValue ignores case');
    Check(R.HeaderValue['X-Missing'] = '', 'HeaderValue of an absent header');
    Check(R.HeaderValue['X-Spaced'] = 'padded value', 'blanks around a value dropped: [' + R.HeaderValue['X-Spaced'] + ']');
    I := -1;
    for J := 0 to High(R.Headers) do
      If SameText(R.Headers[J].Name, 'X-Empty') then
        I := J;
    Check((I >= 0) and (R.Headers[I].Value = ''), 'a header with an empty value is listed');
    Check(R.HeaderValue['Content-Length'] = IntToStr(R.ContentStream.Size), 'Content-Length header present and right');
    Check(R.ContentEncoding = '', 'no Content-Encoding');
    Check(R.GetContentEncoding = '', 'GetContentEncoding');
    Check(StartsWith(R.HeaderValue['Content-Type'], 'text/plain'), 'Content-Type header: ' + R.HeaderValue['Content-Type']);
    Check(Length(R.Headers) >= 3, 'all headers listed');
    { HEAD: no body }
    R := C.Head(Base + '/echo');
    Check((R.StatusCode = 200) and (R.ContentStream.Size = 0) and (R.HeaderValue['Content-Length'] <> ''), 'HEAD without body');
    { POST from the current position; the source ends at its end }
    S.Position := 3;
    R := C.Post(Base + '/echo', S);
    T := Body(R);
    Check(HasLine(T, 'POST /echo'), 'POST echoed');
    Check(HasLine(T, 'BODY=lo world'), 'POST body from Position: ' + T);
    Check(HasLine(T, 'H:content-length=8'), 'POST Content-Length');
    Check(S.Position = S.Size, 'source consumed');
    { PUT nil, PATCH nil, POST nil }
    R := C.Put(Base + '/echo');
    T := Body(R);
    Check(HasLine(T, 'PUT /echo') and HasLine(T, 'H:content-length=0'), 'PUT without body');
    R := C.Patch(Base + '/echo');
    Check(HasLine(Body(R), 'PATCH /echo'), 'PATCH');
    R := C.Post(Base + '/echo', TStream(nil));
    Check(HasLine(Body(R), 'POST /echo'), 'POST nil');
    R := C.Delete(Base + '/echo');
    Check(HasLine(Body(R), 'DELETE /echo'), 'DELETE');
    { statuses without exceptions }
    R := C.Get(Base + '/status/201');
    Check((R.StatusCode = 201) and (Body(R) = 'status 201'), '201 with body');
    R := C.Get(Base + '/status/204');
    Check((R.StatusCode = 204) and (R.ContentStream.Size = 0), '204 without body');
    R := C.Get(Base + '/status/404');
    Check((R.StatusCode = 404) and (Body(R) = 'status 404') and (R.StatusText = 'Not Found'), '404 with body');
    R := C.Get(Base + '/status/500');
    Check((R.StatusCode = 500) and (Body(R) = 'status 500'), '500 with body');
    R := C.Post(Base + '/status/400', S);
    Check(R.StatusCode = 400, 'POST 400');
    { caller-owned response stream: appended at its position, position restored }
    M.WriteBuffer(PAnsiChar('12345')^, 5);
    R := C.Get(Base + '/status/201', M);
    Check(R.ContentStream = M, 'ContentStream is the caller stream');
    Check((M.Size = 5 + 10) and (M.Position = 5), 'body appended at the position, position restored');
    Check(Body(R) = 'status 201', 'ContentAsString from the position');
    Check(M.Position = 5, 'ContentAsString keeps the position');
    { bytes the caller left past the write are not part of the body }
    M.Clear;
    M.Size := 80;
    FillChar(M.Memory^, 80, Ord('A'));
    M.Position := 0;
    R := C.Get(Base + '/status/201', M);
    Check(M.Size = 80, 'a longer caller stream is not truncated');
    Check(Body(R) = 'status 201', 'ContentAsString stops at the received body, not the stream tail');
    Check(M.Position = 0, 'position restored on a pre-sized stream');
  finally
    C.Free;
    S.Free;
    M.Free;
  end;
end;

procedure Headers;
var
  C: THTTPClient;
  R: IHTTPResponse;
  T: string;
  H: TNetHeaders;
begin
  C := THTTPClient.Create;
  try
    C.CustomHeaders['X-Client'] := 'client';
    C.CustomHeaders['X-Only-Client'] := 'one';
    C.Accept := 'application/json';
    C.AcceptLanguage := 'ru';
    C.ContentType := 'text/x-ignored';
    Check(C.CustHeaders.Value['x-client'] = 'client', 'CustHeaders is the same collection');
    SetLength(H, 2);
    H[0] := TNetHeader.Create('X-Client', 'call');
    H[1] := TNetHeader.Create('X-Call', 'yes');
    R := C.Get(Base + '/echo', nil, H);
    T := Body(R);
    Check(HasLine(T, 'H:x-client=call'), 'call header replaces the client header');
    Check(HasLine(T, 'H:x-only-client=one'), 'client header sent');
    Check(HasLine(T, 'H:x-call=yes'), 'call header sent');
    Check(HasLine(T, 'H:accept=application/json'), 'Accept sent: ' + T);
    Check(HasLine(T, 'H:accept-language=ru'), 'Accept-Language sent');
    Check(HasLine(T, 'H:content-type=text/x-ignored'), 'Content-Type property sent with GET');
    Check(HasLine(T, 'H:user-agent=' + C.UserAgent), 'User-Agent sent');
    Check(HasLine(T, 'H:host=' + Copy(Base, 8, MaxInt)), 'Host header: ' + T);
    R := C.Get(Base + '/echo', nil, [TNetHeader.Create('User-Agent', 'call-agent'), TNetHeader.Create('Accept', 'call-accept')]);
    T := Body(R);
    Check(HasLine(T, 'H:user-agent=call-agent') and HasLine(T, 'H:accept=call-accept'), 'named call headers replace properties');
    R := C.Get(Base + '/echo', nil, [TNetHeader.Create('User-Agent', ''), TNetHeader.Create('Accept', '')]);
    T := Body(R);
    Check((Pos('H:user-agent=', T) = 0) and (Pos('H:accept=', T) = 0), 'empty call headers suppress properties');
    R := C.Get(Base + '/echo');
    T := Body(R);
    Check(HasLine(T, 'H:user-agent=' + C.UserAgent) and HasLine(T, 'H:accept=' + C.Accept), 'call headers do not change properties');
    C.CustHeaders.Delete('X-Client');
    C.CustHeaders.Delete('X-Only-Client');
    C.UserAgent := '';
    R := C.Get(Base + '/echo');
    T := Body(R);
    Check(not HasLine(T, 'H:x-only-client=one'), 'deleted header not sent');
    Check(Pos('H:user-agent=', T) = 0, 'no User-Agent when empty: ' + T);
    Check(Pos('H:x-client=', T) = 0, 'CustHeaders.Delete removed the header');
  finally
    C.Free;
  end;
end;

procedure Redirects;
var
  C: THTTPClient;
  R: IHTTPResponse;
  S: TStringStream;
  T: string;
begin
  C := THTTPClient.Create;
  S := TStringStream.Create('payload', TEncoding.UTF8);
  try
    C.ContentType := 'text/plain';
    { 301/302/303 turn POST into GET without the body }
    S.Position := 0;
    R := C.Post(Base + '/redirect/301', S);
    T := Body(R);
    Check((R.StatusCode = 200) and HasLine(T, 'GET /echo'), '301 POST becomes GET: ' + T);
    Check(not HasLine(T, 'BODY=payload') and (Pos('H:content-type=', T) = 0), '301 drops the body and Content-Type');
    S.Position := 0;
    R := C.Post(Base + '/redirect/302', S);
    Check(HasLine(Body(R), 'GET /echo'), '302 POST becomes GET');
    S.Position := 0;
    R := C.Put(Base + '/redirect/303', S);
    Check(HasLine(Body(R), 'GET /echo'), '303 PUT becomes GET');
    R := C.Delete(Base + '/redirect/303');
    Check(HasLine(Body(R), 'GET /echo'), '303 DELETE becomes GET');
    { 307/308 keep method and body }
    S.Position := 0;
    R := C.Post(Base + '/redirect/307', S);
    T := Body(R);
    Check(HasLine(T, 'POST /echo') and HasLine(T, 'BODY=payload') and HasLine(T, 'H:content-type=text/plain'),
      '307 keeps POST and its body: ' + T);
    S.Position := 0;
    R := C.Put(Base + '/redirect/308', S);
    T := Body(R);
    Check(HasLine(T, 'PUT /echo') and HasLine(T, 'BODY=payload'), '308 keeps PUT and its body');
    S.Position := 0;
    R := C.Put(Base + '/redirect/301', S);
    T := Body(R);
    Check(HasLine(T, 'PUT /echo') and HasLine(T, 'BODY=payload'), '301 keeps PUT (only POST changes)');
    { a chain within the limit and a relative Location }
    R := C.Get(Base + '/redirect/chain/4');
    Check((R.StatusCode = 200) and HasLine(Body(R), 'GET /echo'), 'chain of 4');
    R := C.Get(Base + '/redirect/relative/deep');
    Check(HasLine(Body(R), 'GET /redirect/target'), 'relative Location resolved: ' + Body(R));
    R := C.Get(Base + '/redirect/query');
    Check(HasLine(Body(R), 'GET /echo?from=redirect'), 'Location with a query');
    { ".." in an absolute path, an absolute URL and a protocol-relative URL }
    R := C.Get(Base + '/redirect/dots');
    Check(HasLine(Body(R), 'GET /echo'), 'absolute-path Location drops dot segments: ' + Body(R));
    R := C.Get(Base + '/redirect/dots-abs');
    Check(HasLine(Body(R), 'GET /echo'), 'absolute URL Location drops dot segments: ' + Body(R));
    R := C.Get(Base + '/redirect/dots-proto');
    Check(HasLine(Body(R), 'GET /echo'), 'protocol-relative Location drops dot segments: ' + Body(R));
    { same origin keeps Authorization; another port does not, nor the caller's Cookie }
    R := C.Get(Base + '/redirect/302', nil, [TNetHeader.Create('Authorization', 'Bearer secret'),
      TNetHeader.Create('Cookie', 'secret=1')]);
    T := Body(R);
    Check(HasLine(T, 'H:authorization=Bearer secret'), 'same-origin redirect keeps Authorization: ' + T);
    Check(HasLine(T, 'H:cookie=secret=1'), 'same-origin redirect keeps Cookie: ' + T);
    R := C.Get(Base + '/redirect/cross-auth', nil, [TNetHeader.Create('Authorization', 'Bearer secret'),
      TNetHeader.Create('Cookie', 'secret=1')]);
    T := Body(R);
    Check(HasLine(T, 'GET /echo'), 'cross-origin redirect arrived: ' + T);
    Check(Pos('authorization=', T) = 0, 'cross-origin redirect dropped Authorization: ' + T);
    Check(Pos('secret=1', T) = 0, 'cross-origin redirect dropped the caller Cookie: ' + T);
    R := C.Get(Base + '/redirect/cross-return', nil, [TNetHeader.Create('Authorization', 'Bearer secret'),
      TNetHeader.Create('Cookie', 'secret=1')]);
    T := Body(R);
    Check(HasLine(T, 'H:authorization=Bearer secret') and HasLine(T, 'H:cookie=secret=1'),
      'A-B-A redirects restore caller credentials only at A');
    { over the limit }
    try
      R := C.Get(Base + '/redirect/chain/6');
      Check(False, 'chain of 6 accepted with MaxRedirects 5');
    except
      on ENetHTTPRequestException do ;
    end;
    C.MaxRedirects := 6;
    R := C.Get(Base + '/redirect/chain/6');
    Check(R.StatusCode = 200, 'chain of 6 with MaxRedirects 6');
    { redirects off: the 3xx comes back }
    C.HandleRedirects := False;
    R := C.Get(Base + '/redirect/302');
    Check((R.StatusCode = 302) and (R.HeaderValue['Location'] = '/echo') and (R.StatusText = 'Found'), '302 returned as is');
    C.HandleRedirects := True;
    { the client still works afterwards }
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'client usable after redirects');
  finally
    C.Free;
    S.Free;
  end;
end;

procedure Compression;
var
  C: THTTPClient;
  R: IHTTPResponse;
  B: array[0..1] of Byte;
  T: string;
  Z: TDecompressionStream;
  M: TMemoryStream;
  I: Integer;
begin
  C := THTTPClient.Create;
  try
    C.AcceptEncoding := 'gzip, deflate';
    R := C.Get(Base + '/gzip');
    Check(R.ContentEncoding = 'gzip', 'gzip Content-Encoding kept: ' + R.ContentEncoding);
    R.ContentStream.Position := 0;
    R.ContentStream.ReadBuffer(B, 2);
    Check((B[0] = $1F) and (B[1] = $8B), 'ContentStream is the raw gzip body');
    Check(Body(R) = 'compressed text', 'ContentAsString inflates gzip: ' + Body(R));
    Check(Body(R) = 'compressed text', 'ContentAsString a second time');
    R := C.Get(Base + '/deflate');
    Check((R.ContentEncoding = 'deflate') and (Body(R) = 'compressed text'), 'ContentAsString inflates zlib deflate');
    { the raw body inflated by the caller through System.ZLib over
      ContentStream, as MoonBot does: a decompression stream on the
      received stream, CopyFrom(Z, 0) for the whole body; windowBits 31 for
      gzip, 15 for zlib deflate, 47 for either }
    Z := TDecompressionStream.Create(R.ContentStream, 15);
    M := TMemoryStream.Create;
    try
      M.CopyFrom(Z, 0);
      SetString(T, PAnsiChar(M.Memory), M.Size);
      Check(T = 'compressed text', 'caller inflates zlib deflate over ContentStream: ' + T);
    finally
      Z.Free;
      M.Free;
    end;
    R := C.Get(Base + '/gzip');
    R.ContentStream.Position := 0;
    Z := TDecompressionStream.Create(R.ContentStream, 15 + 16);
    M := TMemoryStream.Create;
    try
      M.CopyFrom(Z, 0);
      SetString(T, PAnsiChar(M.Memory), M.Size);
      Check(T = 'compressed text', 'caller inflates gzip over ContentStream: ' + T);
    finally
      Z.Free;
      M.Free;
    end;
    R.ContentStream.Position := 0;
    Z := TDecompressionStream.Create(R.ContentStream, 47);
    try
      T := '';
      repeat
        I := Z.Read(B, 2);
        If I > 0 then
          T := T + Copy(string(AnsiChar(B[0]) + AnsiChar(B[1])), 1, I);
      until I = 0;
      Check(T = 'compressed text', 'caller inflates with automatic header detection (47): ' + T);
    finally
      Z.Free;
    end;
    R := C.Get(Base + '/deflate-raw');
    Check(Body(R) = 'compressed text', 'ContentAsString inflates raw deflate');
    R := C.Get(Base + '/gzip', nil, [TNetHeader.Create('Accept-Encoding', 'identity')]);
    Check(R.HeaderValue['X-Accept-Encoding'] = 'identity', 'call header wins for Accept-Encoding');
    { automatic }
    C.AcceptEncoding := '';
    C.CustHeaders.Delete('Accept-Encoding');
    C.AutomaticDecompression := [THTTPCompressionMethod.GZip];
    R := C.Get(Base + '/gzip');
    Check(R.HeaderValue['X-Accept-Encoding'] = 'gzip', 'Accept-Encoding added automatically: ' + R.HeaderValue['X-Accept-Encoding']);
    R.ContentStream.Position := 0;
    SetLength(T, R.ContentStream.Size);
    Check(R.ContentStream.Size = Length('compressed text'), 'ContentStream inflated automatically');
    Check(Body(R) = 'compressed text', 'ContentAsString does not inflate twice');
    { the headers describe what the stream holds now: no coding, no length of
      the coded body (a caller inflating by ContentEncoding would inflate twice) }
    Check(R.ContentEncoding = '', 'ContentEncoding empty after automatic inflation: ' + R.ContentEncoding);
    Check(R.HeaderValue['Content-Encoding'] = '', 'Content-Encoding header dropped after automatic inflation');
    Check(R.HeaderValue['Content-Length'] = '', 'Content-Length header dropped after automatic inflation: ' + R.HeaderValue['Content-Length']);
    Check(StartsWith(R.HeaderValue['Content-Type'], 'text/plain'), 'other headers kept after automatic inflation');
    C.AutomaticDecompression := [THTTPCompressionMethod.Any];
    R := C.Get(Base + '/deflate');
    Check((R.HeaderValue['X-Accept-Encoding'] = 'gzip, deflate') and (Body(R) = 'compressed text'), 'Any covers deflate');
    C.AutomaticDecompression := [THTTPCompressionMethod.Deflate];
    R := C.Get(Base + '/gzip', nil, [TNetHeader.Create('Accept-Encoding', 'gzip')]);
    R.ContentStream.Position := 0;
    R.ContentStream.ReadBuffer(B, 2);
    Check((B[0] = $1F) and (B[1] = $8B), 'gzip stays raw when only Deflate is automatic');
    Check(Body(R) = 'compressed text', 'and ContentAsString still inflates it');
    { a gzip member that does not end is not a body: both the explicit
      inflate in ContentAsString and AutomaticDecompression must refuse it }
    C.AutomaticDecompression := [];
    C.AcceptEncoding := 'gzip';
    try
      R := C.Get(Base + '/gzip-cut');
      Check(False, 'truncated gzip decoded as "' + Body(R) + '"');
    except
      on E: ENetHTTPResponseException do ;
      on E: Exception do
        Check(False, 'truncated gzip: ' + E.ClassName + ': ' + E.Message);
    end;
    C.AutomaticDecompression := [THTTPCompressionMethod.GZip];
    try
      R := C.Get(Base + '/gzip-cut');
      Check(False, 'truncated gzip accepted by automatic decompression: ' + Body(R));
    except
      on E: ENetHTTPResponseException do ;
      on E: Exception do
        Check(False, 'truncated gzip automatic: ' + E.ClassName + ': ' + E.Message);
    end;
    { charsets }
    C.AutomaticDecompression := [];
    R := C.Get(Base + '/charset1251');
    Check(Body(R) = 'Привет', 'charset=windows-1251 decoded: ' + Body(R));
    Check(R.ContentAsString(TEncoding.UTF8) <> 'Привет', 'explicit encoding overrides');
    R := C.Get(Base + '/charset-quoted');
    Check(Body(R) = 'Привет', 'quoted charset=utf-8 decoded');
    R := C.Get(Base + '/bom');
    Check((Length(Body(R)) = 4) and (Body(R)[1] = #$FEFF), 'BOM kept');
  finally
    C.Free;
  end;
end;

procedure Forms;
var
  C: THTTPClient;
  R: IHTTPResponse;
  L: TStringList;
  T: string;
  E: TEncoding;
begin
  C := THTTPClient.Create;
  L := TStringList.Create;
  try
    C.ContentType := 'text/x-property';
    L.Add('a=1');
    L.Add('noequals');
    L.Add('b=Привет мир');
    L.Add('c=x&y=z');
    R := C.Post(Base + '/echo', L);
    T := Body(R);
    Check(HasLine(T, 'BODY=a=1&b=%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82+%D0%BC%D0%B8%D1%80&c=x%26y%3Dz'), 'form body: ' + T);
    Check(HasLine(T, 'H:content-type=application/x-www-form-urlencoded; charset=utf-8'), 'form Content-Type: ' + T);
    E := TEncoding.GetEncoding(1251);
    try
      R := C.Post(Base + '/echo', L, nil, E);
      T := Body(R);
      Check(HasLine(T, 'BODY=a=1&b=%CF%F0%E8%E2%E5%F2+%EC%E8%F0&c=x%26y%3Dz'), 'form body in cp1251: ' + T);
      Check(HasLine(T, 'H:content-type=application/x-www-form-urlencoded; charset=windows-1251'), 'cp1251 charset');
    finally
      E.Free;
    end;
    R := C.Post(Base + '/echo', L, nil, nil, [TNetHeader.Create('X-Form', '1')]);
    Check(HasLine(Body(R), 'H:x-form=1'), 'form call headers');
  finally
    C.Free;
    L.Free;
  end;
end;

procedure Cookies;
var
  C, Other: THTTPClient;
  R: IHTTPResponse;
  T: string;
begin
  C := THTTPClient.Create;
  Other := THTTPClient.Create;
  try
    R := C.Get(Base + '/cookies/set');
    Check(R.StatusCode = 200, 'cookies set');
    R := C.Get(Base + '/cookies/show');
    T := Body(R);
    Check(Pos('sid=abc', T) > 0, 'cookie sent back to its host: ' + T);
    Check((Pos('pref=1', T) > 0) and (Pos('Path', T) = 0) and (Pos('HttpOnly', T) = 0), 'attributes stripped, name=value kept: ' + T);
    R := C.Get(Base + '/show');
    Check(Pos('sid=abc', Body(R)) > 0, 'cookie sent for any path of the host');
    R := C.Get(Base + '/cookies/replace');
    R := C.Get(Base + '/cookies/show');
    T := Body(R);
    Check((Pos('sid=def', T) > 0) and (Pos('sid=abc', T) = 0), 'same name replaced: ' + T);
    C.CookieManager.AddServerCookie('manual=m; Path=/', Base + '/x');
    C.CookieManager.AddServerCookie('bm_sz=Aaaa', 'https://api2.bybit.com/');
    R := C.Get(Base + '/cookies/show');
    T := Body(R);
    Check((Pos('manual=m', T) > 0) and (Pos('bm_sz', T) = 0), 'AddServerCookie by hand, other host not sent: ' + T);
    R := C.Get(Base + '/cookies/show', nil, [TNetHeader.Create('Cookie', 'given=g')]);
    T := Body(R);
    Check((Pos('given=g', T) > 0) and (Pos('manual=m', T) > 0), 'call Cookie header merged with the jar: ' + T);
    R := Other.Get(Base + '/cookies/show');
    Check(Pos('=', Body(R)) = 0, 'another instance has its own jar: ' + Body(R));
    Check(C.CookieManager.Count > 0, 'jar count');
  finally
    C.Free;
    Other.Free;
  end;
end;

type
  TProgress = class
    Calls, FirstRead: Integer;
    FirstLength, LastLength, LastRead, MaxRead: Int64;
    Monotonic: Boolean;
    AbortAfter: Int64;
    Aborted: Boolean;
    constructor Create;
    procedure OnReceive(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
  end;

constructor TProgress.Create;
begin
  inherited Create;
  Monotonic := True;
  FirstRead := -1;
  FirstLength := -2;
  AbortAfter := -1;
end;

procedure TProgress.OnReceive(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
begin
  If Calls = 0 then begin
    FirstRead := AReadCount;
    FirstLength := AContentLength;
  end;
  Inc(Calls);
  If AReadCount < LastRead then
    Monotonic := False;
  LastRead := AReadCount;
  LastLength := AContentLength;
  If AReadCount > MaxRead then
    MaxRead := AReadCount;
  If (AbortAfter >= 0) and (AReadCount >= AbortAfter) then begin
    AAbort := True;
    Aborted := True;
  end;
end;

procedure Progress;
var
  C: THTTPClient;
  P: TProgress;
  R: IHTTPResponse;
  I: Integer;
  Ids: string;
  S: TStringStream;
begin
  C := THTTPClient.Create;
  P := TProgress.Create;
  try
    C.OnReceiveData := P.OnReceive;
    R := C.Get(Base + '/big');
    Check(R.StatusCode = 200, 'big status');
    Check(R.ContentStream.Size = 1048576, 'big body complete');
    Check(P.Calls >= 2, 'several progress calls: ' + IntToStr(P.Calls));
    Check((P.FirstRead = 0) and (P.FirstLength = 1048576), 'first call before the body with the length');
    Check((P.LastRead = 1048576) and P.Monotonic, 'last call with the whole size, monotonic');
    { chunked: unknown length }
    P.Free;
    P := TProgress.Create;
    C.OnReceiveData := P.OnReceive;
    R := C.Get(Base + '/big-chunked');
    Check(R.ContentStream.Size = 1048576, 'chunked body complete');
    Check((P.FirstLength = -1) and (P.LastRead = 1048576), 'chunked: length -1, read count complete');
    Check(R.HeaderValue['Transfer-Encoding'] = 'chunked', 'Transfer-Encoding header listed');
    { no calls for 4xx }
    P.Free;
    P := TProgress.Create;
    C.OnReceiveData := P.OnReceive;
    R := C.Get(Base + '/status/404');
    Check((R.StatusCode = 404) and (Body(R) = 'status 404'), '404 body with a progress handler');
    Check(P.Calls = 0, 'no progress calls for 404: ' + IntToStr(P.Calls));
    { abort without an exception }
    P.Free;
    P := TProgress.Create;
    P.AbortAfter := 100000;
    C.OnReceiveData := P.OnReceive;
    R := C.Get(Base + '/big');
    Check(P.Aborted, 'abort requested');
    Check((R.StatusCode = 200) and (R.StatusText = 'OK'), 'aborted response has its status and reason phrase');
    Check(R.HeaderValue['Content-Length'] = '1048576', 'aborted response has the headers');
    Check((R.ContentStream.Size >= 100000) and (R.ContentStream.Size < 1048576), 'truncated body: ' + IntToStr(R.ContentStream.Size));
    { and the client keeps working }
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'client usable after an abort');
    C.OnReceiveData := nil;
    { keep-alive: the same connection over a series }
    Ids := '';
    for I := 1 to 5 do begin
      R := C.Get(Base + '/conn');
      If I = 1 then
        Ids := R.HeaderValue['X-Conn-Id']
      else If Ids <> R.HeaderValue['X-Conn-Id'] then
        Ids := 'differ';
    end;
    Check((Ids <> '') and (Ids <> 'differ'), 'keep-alive: one connection for five requests');
    { An idempotent GET can retry an idle connection; a POST without an
      answer fails, because the client cannot prove it was not processed. }
    R := C.Get(Base + '/conn-drop');
    Ids := R.HeaderValue['X-Conn-Id'];
    Sleep(100);
    R := C.Get(Base + '/conn-after');
    Check((R.StatusCode = 200) and (R.HeaderValue['X-Conn-Id'] <> Ids), 'dropped idle connection replaced for GET');
    R := C.Get(Base + '/conn-drop');
    Sleep(100);
    S := TStringStream.Create('after-drop', TEncoding.UTF8);
    try
      try
        R := C.Post(Base + '/echo', S);
        Check(False, 'POST automatically replayed after an empty answer');
      except
        on ENetHTTPClientException do ;
      end;
    finally
      S.Free;
    end;
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'client usable after ambiguous POST failure');
  finally
    C.Free;
    P.Free;
  end;
end;

procedure Timeouts;
var
  C: THTTPClient;
  R: IHTTPResponse;
  Started: TDateTime;
  Ms: Int64;
  Bytes: RawByteString;
begin
  C := THTTPClient.Create;
  try
    C.ResponseTimeout := 400;
    Started := Now;
    try
      R := C.Get(Base + '/slow-headers');
      Check(False, 'slow headers accepted');
    except
      on E: ENetHTTPClientException do
        Check(Pos('imeout', E.Message) > 0, 'response timeout message: ' + E.Message);
    end;
    Ms := Round(Abs(Now - Started) * MSecsPerDay);
    Check((Ms >= 300) and (Ms < 2500), 'response timeout elapsed: ' + IntToStr(Ms));
    { the client recovers }
    C.ResponseTimeout := 60000;
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'usable after a timeout');
    { body stalls: headers arrived, the body did not }
    C.ResponseTimeout := 400;
    try
      R := C.Get(Base + '/slow-body');
      Check(False, 'stalled body accepted');
    except
      on ENetHTTPResponseException do ;
      on E: Exception do
        Check(False, 'stalled body raised ' + E.ClassName + ': ' + E.Message);
    end;
    C.ResponseTimeout := 60000;
    { Content-Length that lies.  Too long with the server gone idle: the
      wait ends with the response timeout, nothing truncated is handed out,
      the request is not repeated.  Too long with the server closing: an
      error at once, again no partial body, no repeat.  Too short: the body
      is what the header says; the bytes beyond it are in front of the next
      answer on that connection - that answer is refused as not HTTP and
      the connection dropped; the request after it rides a new one. }
    C.ResponseTimeout := 400;
    Started := Now;
    try
      R := C.Get(Base + '/lie-long-idle');
      Check(False, 'Content-Length too long, server idle: accepted with ' + IntToStr(R.ContentStream.Size) + ' bytes');
    except
      on ENetHTTPResponseException do ;
      on E: Exception do
        Check(False, 'Content-Length too long, server idle, raised ' + E.ClassName + ': ' + E.Message);
    end;
    Ms := Round(Abs(Now - Started) * MSecsPerDay);
    Check((Ms >= 300) and (Ms < 2500), 'Content-Length too long, server idle: gave up after ' + IntToStr(Ms) + ' ms');
    C.ResponseTimeout := 60000;
    try
      R := C.Get(Base + '/lie-long-close');
      Check(False, 'Content-Length too long, server closed: accepted with ' + IntToStr(R.ContentStream.Size) + ' bytes');
    except
      on ENetHTTPResponseException do ;
      on E: Exception do
        Check(False, 'Content-Length too long, server closed, raised ' + E.ClassName + ': ' + E.Message);
    end;
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'usable after a lying Content-Length');
    R := C.Get(Base + '/lie-short');
    Check((R.StatusCode = 200) and (Body(R) = 'ABCDE'), 'Content-Length too short: the announced bytes: ' + Body(R));
    try
      R := C.Get(Base + '/echo');
      Check(False, 'bytes beyond Content-Length taken for the next answer: ' + IntToStr(R.StatusCode));
    except
      on ENetHTTPResponseException do ;
      on E: Exception do
        Check(False, 'bytes beyond Content-Length raised ' + E.ClassName + ': ' + E.Message);
    end;
    R := C.Get(Base + '/echo');
    Check((R.StatusCode = 200) and HasLine(Body(R), 'GET /echo'), 'usable after the out-of-step connection was dropped');
    { a Content-Length of 2 GB is refused before anything is allocated or
      waited for (mORMot's MaxHttpInMemSize), not after the response timeout }
    C.ResponseTimeout := 5000;
    Started := Now;
    try
      R := C.Get(Base + '/lie-huge');
      Check(False, 'Content-Length of 2 GB accepted with ' + IntToStr(R.ContentStream.Size) + ' bytes');
    except
      on ENetHTTPResponseException do ;
      on E: Exception do
        Check(False, 'Content-Length of 2 GB raised ' + E.ClassName + ': ' + E.Message);
    end;
    Ms := Round(Abs(Now - Started) * MSecsPerDay);
    Check(Ms < 1500, 'Content-Length of 2 GB refused at once: ' + IntToStr(Ms) + ' ms');
    C.ResponseTimeout := 60000;
    { a body delimited by the connection's close (no Content-Length, no
      chunking) arrives byte for byte - LF, CR LF and NUL included }
    R := C.Get(Base + '/close-delimited');
    Bytes := ReadAll(R.ContentStream);
    Check((R.StatusCode = 200) and (Bytes = 'line1'#10'line2'#13#10'bin'#0#1#255' end'),
      'close-delimited body byte for byte: ' + IntToStr(Length(Bytes)) + ' bytes');
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'usable after a close-delimited body');
    { refused connection }
    C.ConnectionTimeout := 2000;
    try
      R := C.Get('http://127.0.0.1:' + RefusedPort + '/echo');
      Check(False, 'refused port accepted');
    except
      on E: ENetHTTPClientException do
        Check(Pos('127.0.0.1:' + RefusedPort, E.Message) > 0, 'refused message names the URL: ' + E.Message);
    end;
    { bad URLs: an unsupported scheme is the client's error; no scheme, no
      host or nothing at all is a URI error (ENetURIException, as in Delphi)
      raised at once, before any connection is tried }
    try
      R := C.Get('ftp://127.0.0.1/x');
      Check(False, 'ftp accepted');
    except
      on ENetHTTPClientException do ;
    end;
    Started := Now;
    try
      R := C.Get('');
      Check(False, 'empty URL accepted');
    except
      on ENetURIException do ;
      on E: Exception do
        Check(False, 'empty URL raised ' + E.ClassName + ': ' + E.Message);
    end;
    try
      R := C.Get(Copy(Base, Pos('//', Base) + 2, MaxInt) + '/echo');
      Check(False, 'URL without a scheme accepted');
    except
      on ENetURIException do ;
      on E: Exception do
        Check(False, 'URL without a scheme raised ' + E.ClassName + ': ' + E.Message);
    end;
    try
      R := C.Get('http://');
      Check(False, 'URL without a host accepted');
    except
      on ENetURIException do ;
      on E: Exception do
        Check(False, 'URL without a host raised ' + E.ClassName + ': ' + E.Message);
    end;
    Ms := Round(Abs(Now - Started) * MSecsPerDay);
    Check(Ms < 500, 'bad URLs refused without connecting: ' + IntToStr(Ms) + ' ms');
  finally
    C.Free;
  end;
end;

procedure Async;
var
  C: THTTPClient;
  A: IAsyncResult;
  R: IHTTPResponse;
  Waited, I: Integer;
begin
  C := THTTPClient.Create;
  try
    A := C.BeginGet(Base + '/echo');
    Waited := 0;
    while not A.IsCompleted and (Waited < 200) do begin
      Sleep(25);
      Inc(Waited);
    end;
    Check(A.IsCompleted, 'async GET completed');
    Check(not A.IsCancelled, 'not cancelled');
    R := THTTPClient.EndAsyncHTTP(A);
    Check((R.StatusCode = 200) and HasLine(Body(R), 'GET /echo'), 'async response');
    R := C.EndAsyncHTTP(A);
    Check(R.StatusCode = 200, 'EndAsyncHTTP through an instance, again');
    Check(not A.Cancel, 'Cancel of a completed request is False');
    { cancel a slow one }
    A := C.BeginGet(Base + '/slow-body-long');
    Sleep(300);
    Check(not A.IsCompleted, 'slow request still running');
    If A.IsCompleted then
      try
        R := THTTPClient.EndAsyncHTTP(A);
        WriteLn('  early completion: status ', R.StatusCode, ' body ', R.ContentStream.Size, ' [', Body(R), ']');
        for I := 0 to High(R.Headers) do WriteLn('    ', R.Headers[I].Name, ': ', R.Headers[I].Value);
      except
        on E: Exception do
          WriteLn('  early completion: ', E.ClassName, ': ', E.Message);
      end;
    Check(A.Cancel, 'Cancel of a running request is True');
    Check(A.IsCancelled, 'IsCancelled after Cancel');
    Check(not A.Cancel, 'second Cancel is False');
    Waited := 0;
    while not A.IsCompleted and (Waited < 400) do begin
      Sleep(25);
      Inc(Waited);
    end;
    Check(A.IsCompleted, 'cancelled request completes');
    try
      R := THTTPClient.EndAsyncHTTP(A);
      Check(False, 'EndAsyncHTTP of a cancelled request returned');
    except
      on ENetHTTPClientException do ;
    end;
    { an error is rethrown by EndAsyncHTTP }
    A := C.BeginGet('http://127.0.0.1:' + RefusedPort + '/x');
    try
      R := THTTPClient.EndAsyncHTTP(A);
      Check(False, 'EndAsyncHTTP returned for a refused connection');
    except
      on ENetHTTPClientException do ;
    end;
    { the synchronous client is untouched by the clones }
    R := C.Get(Base + '/echo');
    Check(R.StatusCode = 200, 'client usable after async');
  finally
    C.Free;
  end;
end;

type
  TValidator = class
    Calls: Integer;
    Accept: Boolean;
    Boom: Boolean;
    Subject, Issuer, URL, Method: string;
    procedure Validate(const Sender: TObject; const ARequest: TURLRequest; const Certificate: TCertificate;
      var Accepted: Boolean);
  end;

procedure TValidator.Validate(const Sender: TObject; const ARequest: TURLRequest; const Certificate: TCertificate;
  var Accepted: Boolean);
begin
  Inc(Calls);
  Subject := Certificate.Subject;
  Issuer := Certificate.Issuer;
  URL := ARequest.URL;
  Method := ARequest.MethodString;
  Check(not Accepted, 'handler called with Accepted = False');
  If Boom then
    raise Exception.Create('certificate handler failed');
  Accepted := Accept;
end;

procedure Tls;
var
  C, C2: THTTPClient;
  R: IHTTPResponse;
  V: TValidator;
begin
  C := THTTPClient.Create;
  V := TValidator.Create;
  try
    If TlsTrusted then begin
      R := C.Get(TlsBase + '/echo');
      Check((R.StatusCode = 200) and HasLine(Body(R), 'GET /echo'), 'trusted https');
      C.OnValidateServerCertificate := V.Validate;
      R := C.Get(TlsBase + '/echo');
      Check((R.StatusCode = 200) and (V.Calls = 0), 'handler not called for a trusted certificate');
      C.OnValidateServerCertificate := nil;
      If TlsOtherBase <> '-' then
        try
          R := C.Get(TlsOtherBase + '/echo');
          Check(False, 'certificate for another host accepted');
        except
          on ENetHTTPCertificateException do ;
          on E: Exception do
            Check(False, 'other host raised ' + E.ClassName + ': ' + E.Message);
        end;
    end else begin
      try
        R := C.Get(TlsBase + '/echo');
        Check(False, 'untrusted certificate accepted');
      except
        on ENetHTTPCertificateException do ;
        on E: Exception do
          Check(False, 'untrusted raised ' + E.ClassName + ': ' + E.Message);
      end;
      V.Accept := False;
      C.OnValidateServerCertificate := V.Validate;
      try
        R := C.Get(TlsBase + '/echo');
        Check(False, 'handler refusing still accepted');
      except
        on ENetHTTPCertificateException do ;
      end;
      Check(V.Calls = 1, 'handler called once when refusing: ' + IntToStr(V.Calls));
      V.Accept := True;
      V.Calls := 0;
      R := C.Get(TlsBase + '/echo');
      Check((R.StatusCode = 200) and HasLine(Body(R), 'GET /echo'), 'handler accepting lets the request through');
      Check(V.Calls = 1, 'handler called once when accepting: ' + IntToStr(V.Calls));
      Check(Pos('localhost', V.Subject) > 0, 'certificate subject given to the handler: ' + V.Subject);
      Check((V.URL = TlsBase + '/echo') and (V.Method = 'GET'), 'request given to the handler');
      R := C.Get(TlsBase + '/status/201');
      Check((R.StatusCode = 201) and (V.Calls = 1), 'accepted connection reused without asking again');
      { a handler that raises must drop the socket opened with verification off }
      C2 := THTTPClient.Create;
      try
        V.Boom := True;
        V.Calls := 0;
        C2.OnValidateServerCertificate := V.Validate;
        try
          R := C2.Get(TlsBase + '/echo');
          Check(False, 'raising certificate handler was accepted');
        except
          on E: Exception do
            Check(Pos('certificate handler failed', E.Message) > 0,
              'raising handler: ' + E.ClassName + ' ' + E.Message);
        end;
        V.Boom := False;
        V.Accept := True;
        R := C2.Get(TlsBase + '/echo');
        Check((R.StatusCode = 200) and (V.Calls = 2),
          'raising handler did not keep the unverified socket: calls ' + IntToStr(V.Calls));
      finally
        C2.Free;
      end;
    end;
  finally
    C.Free;
    V.Free;
  end;
end;

procedure Multipart;
var
  C: THTTPClient;
  F: TMultipartFormData;
  R: IHTTPResponse;
  FileName: string;
  Bytes: TBytes;
  I: Integer;
begin
  FileName := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'httpclient-upload-' + IntToStr(GetProcessID) + '.bin';
  SetLength(Bytes, 70000);
  for I := 0 to High(Bytes) do
    Bytes[I] := Byte(I * 31 + 7);
  with TFileStream.Create(FileName, fmCreate) do
    try
      WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Free;
    end;
  C := THTTPClient.Create;
  F := TMultipartFormData.Create;
  try
    F.AddField('caption', 'Фото → тест');
    F.AddFile('photo', FileName, 'image/x-test');
    C.ContentType := F.MimeTypeHeader;
    F.Stream.Position := 0;
    R := C.Post(Base + '/upload', F.Stream);
    Check((R.StatusCode = 200) and (Body(R) = 'parts=2 caption=Фото → тест photo=70000 type=image/x-test'),
      'multipart accepted by the server: ' + Body(R));
  finally
    C.Free;
    F.Free;
    DeleteFile(FileName);
  end;
end;

procedure ImmediateCancel;
var
  C: THTTPClient;
  A: IAsyncResult;
  R: IHTTPResponse;
  I: Integer;
  Started: UInt64;
begin
  C := THTTPClient.Create;
  try
    for I := 1 to 3 do begin
      Started := GetTickCount64;
      A := C.BeginGet(Base + '/immediate-cancel');
      Check(A.Cancel, 'immediate Cancel accepted');
      try
        R := THTTPClient.EndAsyncHTTP(A);
        Check(False, 'immediate cancelled response accepted');
      except
        on ENetHTTPClientException do ;
      end;
      Check(GetTickCount64 - Started < 1000, 'immediate cancellation does not wait for the server response');
      A := nil;
    end;
  finally
    C.Free;
  end;
end;

procedure NoReplay;
var
  C: THTTPClient;
  R: IHTTPResponse;
  S: TStringStream;
  Method: string;
begin
  C := THTTPClient.Create;
  try
    for Method in ['POST', 'PATCH'] do begin
      R := C.Get(Base + '/echo');
      S := TStringStream.Create('order=123', TEncoding.UTF8);
      try
        try
          If Method = 'POST' then
            R := C.Post(Base + '/processed-noresponse', S)
          else
            R := C.Patch(Base + '/processed-noresponse', S);
          Check(False, 'empty response accepted for ' + Method);
        except
          on ENetHTTPClientException do ;
        end;
      finally
        S.Free;
      end;
    end;
  finally
    C.Free;
  end;
end;

procedure CompressionBoundaries;
const Sizes: array[0..5] of Integer = (65535, 65536, 65537, 131071, 131072, 131073);
var
  C: THTTPClient;
  R: IHTTPResponse;
  Kind: string;
  Size: Integer;
begin
  C := THTTPClient.Create;
  try
    for Kind in ['gzip', 'zlib', 'raw'] do
      for Size in Sizes do begin
        R := C.Get(Base + '/compressed-boundary/' + Kind + '/' + IntToStr(Size));
        try
          Check(Length(Body(R)) = Size, 'complete compressed body ' + Kind + '/' + IntToStr(Size));
        except
          on E: Exception do
            Check(False, 'complete compressed body ' + Kind + '/' + IntToStr(Size) + ': ' + E.Message);
        end;
      end;
  finally
    C.Free;
  end;
end;

begin
  Failures := 0;
  If ParamCount < 5 then begin
    WriteLn('usage: httpclient_contract <http-base> <https-base> <https-other-base|-> <trusted|untrusted> <refused-port>');
    Halt(2);
  end;
  Base := ParamStr(1);
  TlsBase := ParamStr(2);
  TlsOtherBase := ParamStr(3);
  TlsTrusted := ParamStr(4) = 'trusted';
  RefusedPort := ParamStr(5);
  Methods;
  BodyInMemory;
  Headers;
  Redirects;
  Compression;
  CompressionBoundaries;
  NoReplay;
  Forms;
  Cookies;
  Progress;
  Timeouts;
  Async;
  ImmediateCancel;
  Tls;
  Multipart;
  If Failures <> 0 then begin
    WriteLn('FAILURES ', Failures);
    Halt(1);
  end;
  WriteLn('HTTPCLIENT_CONTRACT_PASS');
end.
