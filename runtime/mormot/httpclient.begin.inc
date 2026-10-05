function THTTPClient.BeginGet(const AURL: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('GET', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(nil, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginGet(const Callback: TAsyncCallback; const AURL: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('GET', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(Callback, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginGet(const Callback: TAsyncCallbackEvent; const AURL: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('GET', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(nil, Callback, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginHead(const AURL: string;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('HEAD', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(nil, nil, Request, nil, AHeaders);
end;

function THTTPClient.BeginHead(const Callback: TAsyncCallback; const AURL: string;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('HEAD', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(Callback, nil, Request, nil, AHeaders);
end;

function THTTPClient.BeginHead(const Callback: TAsyncCallbackEvent; const AURL: string;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('HEAD', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(nil, Callback, Request, nil, AHeaders);
end;

function THTTPClient.BeginDelete(const AURL: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('DELETE', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(nil, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginDelete(const Callback: TAsyncCallback; const AURL: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('DELETE', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(Callback, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginDelete(const Callback: TAsyncCallbackEvent; const AURL: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('DELETE', AURL);
  Request.SourceStream := nil;
  Result := StartAsync(nil, Callback, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPost(const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('POST', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(nil, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallback; const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('POST', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(Callback, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('POST', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(nil, Callback, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPost(const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('POST', AURL);
  Headers := AHeaders;
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  Request.SourceStream := Source;
  Result := StartAsync(nil, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallback; const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('POST', AURL);
  Headers := AHeaders;
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  Request.SourceStream := Source;
  Result := StartAsync(Callback, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('POST', AURL);
  Headers := AHeaders;
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  Request.SourceStream := Source;
  Result := StartAsync(nil, Callback, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPost(const AURL: string; const ASource: TStrings; const AResponseContent: TStream; const AEncoding: TEncoding;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('POST', AURL);
  Headers := FormHeaders(AHeaders, AEncoding);
  Source := FormBody(ASource, AEncoding);
  Request.SourceStream := Source;
  Result := StartAsync(nil, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallback; const AURL: string; const ASource: TStrings; const AResponseContent: TStream; const AEncoding: TEncoding;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('POST', AURL);
  Headers := FormHeaders(AHeaders, AEncoding);
  Source := FormBody(ASource, AEncoding);
  Request.SourceStream := Source;
  Result := StartAsync(Callback, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: TStrings; const AResponseContent: TStream; const AEncoding: TEncoding;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('POST', AURL);
  Headers := FormHeaders(AHeaders, AEncoding);
  Source := FormBody(ASource, AEncoding);
  Request.SourceStream := Source;
  Result := StartAsync(nil, Callback, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPost(const AURL: string; const ASource: TMultipartFormData; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('POST', AURL);
  If ASource = nil then
    raise EArgumentNilException.Create('Multipart body cannot be nil');
  Request.SourceStream := ASource.Stream;
  Result := StartAsync(nil, nil, Request, AResponseContent, MultipartHeaders(AHeaders, ASource));
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallback; const AURL: string; const ASource: TMultipartFormData; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('POST', AURL);
  If ASource = nil then
    raise EArgumentNilException.Create('Multipart body cannot be nil');
  Request.SourceStream := ASource.Stream;
  Result := StartAsync(Callback, nil, Request, AResponseContent, MultipartHeaders(AHeaders, ASource));
end;

function THTTPClient.BeginPost(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: TMultipartFormData; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('POST', AURL);
  If ASource = nil then
    raise EArgumentNilException.Create('Multipart body cannot be nil');
  Request.SourceStream := ASource.Stream;
  Result := StartAsync(nil, Callback, Request, AResponseContent, MultipartHeaders(AHeaders, ASource));
end;

function THTTPClient.BeginPut(const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PUT', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(nil, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallback; const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PUT', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(Callback, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PUT', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(nil, Callback, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPut(const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('PUT', AURL);
  Headers := AHeaders;
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  Request.SourceStream := Source;
  Result := StartAsync(nil, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallback; const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('PUT', AURL);
  Headers := AHeaders;
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  Request.SourceStream := Source;
  Result := StartAsync(Callback, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('PUT', AURL);
  Headers := AHeaders;
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  Request.SourceStream := Source;
  Result := StartAsync(nil, Callback, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPut(const AURL: string; const ASource: TStrings; const AResponseContent: TStream; const AEncoding: TEncoding;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('PUT', AURL);
  Headers := FormHeaders(AHeaders, AEncoding);
  Source := FormBody(ASource, AEncoding);
  Request.SourceStream := Source;
  Result := StartAsync(nil, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallback; const AURL: string; const ASource: TStrings; const AResponseContent: TStream; const AEncoding: TEncoding;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('PUT', AURL);
  Headers := FormHeaders(AHeaders, AEncoding);
  Source := FormBody(ASource, AEncoding);
  Request.SourceStream := Source;
  Result := StartAsync(Callback, nil, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: TStrings; const AResponseContent: TStream; const AEncoding: TEncoding;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
  Headers: TNetHeaders;
  Source: TStream;
begin
  Request := GetRequest('PUT', AURL);
  Headers := FormHeaders(AHeaders, AEncoding);
  Source := FormBody(ASource, AEncoding);
  Request.SourceStream := Source;
  Result := StartAsync(nil, Callback, Request, AResponseContent, Headers, Source);
end;

function THTTPClient.BeginPut(const AURL: string; const ASource: TMultipartFormData; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PUT', AURL);
  If ASource = nil then
    raise EArgumentNilException.Create('Multipart body cannot be nil');
  Request.SourceStream := ASource.Stream;
  Result := StartAsync(nil, nil, Request, AResponseContent, MultipartHeaders(AHeaders, ASource));
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallback; const AURL: string; const ASource: TMultipartFormData; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PUT', AURL);
  If ASource = nil then
    raise EArgumentNilException.Create('Multipart body cannot be nil');
  Request.SourceStream := ASource.Stream;
  Result := StartAsync(Callback, nil, Request, AResponseContent, MultipartHeaders(AHeaders, ASource));
end;

function THTTPClient.BeginPut(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: TMultipartFormData; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PUT', AURL);
  If ASource = nil then
    raise EArgumentNilException.Create('Multipart body cannot be nil');
  Request.SourceStream := ASource.Stream;
  Result := StartAsync(nil, Callback, Request, AResponseContent, MultipartHeaders(AHeaders, ASource));
end;

function THTTPClient.BeginPatch(const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PATCH', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(nil, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPatch(const Callback: TAsyncCallback; const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PATCH', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(Callback, nil, Request, AResponseContent, AHeaders);
end;

function THTTPClient.BeginPatch(const Callback: TAsyncCallbackEvent; const AURL: string; const ASource: TStream; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest('PATCH', AURL);
  Request.SourceStream := ASource;
  Result := StartAsync(nil, Callback, Request, AResponseContent, AHeaders);
end;
