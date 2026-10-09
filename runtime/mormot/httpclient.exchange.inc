{ One HTTP exchange. The shim owns retries and redirects; transport exceptions
  must reach it before the lower client turns them into HTTP_CLIENTERROR. HTTP
  framing, header parsing, chunk decoding and buffers remain mORMot's. }

class function TMoonHttpSocket.ReadText(var Buffer: TTextRec): Integer;
var
  Socket: TMoonHttpSocket;
  Count, Remaining: Integer;
  Code: TNetResult;
  Started: UInt64;
begin
  Socket := TMoonHttpSocket(PPointer(@Buffer.UserData)^);
  Buffer.BufPos := 0;
  Buffer.BufEnd := 0;
  Started := SysUtils.GetTickCount64;
  repeat
    Count := Buffer.BufSize;
    If not Socket.TrySockRecv(Buffer.BufPtr, Count, True, @Code) then
      raise ENetSock.CreateLastError('HTTP line read failed', [], Code);
    If Count > 0 then begin
      Buffer.BufEnd := Count;
      Exit(0);
    end;
    { TLS control records can consume TCP bytes without producing text. Zero
      application bytes are not an empty line or the final chunk. }
    Remaining := Socket.TimeOut - Integer(SysUtils.GetTickCount64 - Started);
    If Remaining <= 0 then
      raise ENetSock.CreateLastError('HTTP line timeout', [], nrTimeout);
    case Socket.SockReceivePending(Remaining) of
      cspDataAvailable, cspDataAvailableOnClosedSocket: ;
      cspNoData: raise ENetSock.CreateLastError('HTTP line timeout', [], nrTimeout);
    else
      raise ENetSock.CreateLastError('HTTP line connection closed', [], nrClosed);
    end;
  until False;
end;

function TMoonHttpSocket.FailureReason(E: Exception): TNetFailureReason;
begin
  Result := ExceptionFailureReason(E);
  If Result <> TNetFailureReason.Unknown then
    Exit;
  If not SockIsDefined then
    Exit(TNetFailureReason.ConnectionClosed);
  If E is EHttpSocket then
    Result := TNetFailureReason.Protocol;
end;

procedure TMoonHttpSocket.ReadCloseDelimitedBody(Destination: TStream);
var
  Buffer: array[0..65535] of Byte;
  Count: Integer;
  Code: TNetResult;
begin
  fBodyRetrieved := True;
  Http.Content := '';
  Count := TTextRec(SockIn^).BufEnd - TTextRec(SockIn^).BufPos;
  If Count > 0 then
    Http.Content := SockInRead(Count, True);
  while not Aborted do begin
    case SockReceivePending(TimeOut) of
      cspDataAvailable, cspDataAvailableOnClosedSocket: ;
      cspSocketClosed: Break;
      cspNoData:
        raise ENetSock.CreateLastError('Response body timed out', [], nrTimeout);
    else
      raise ENetSock.CreateLastError('Response body connection failed', [], nrUnknownError);
    end;
    Count := SizeOf(Buffer);
    If not TrySockRecv(@Buffer, Count, True, @Code) then begin
      If Code = nrClosed then
        Break;
      raise ENetSock.CreateLastError('Response body read failed', [], Code);
    end;
    If Length(Http.Content) + Int64(Count) > MaxHttpInMemSize then
      raise EHttpSocket.Create('Response body exceeds memory limit');
    Append(Http.Content, @Buffer, Count);
  end;
  Http.ContentLength := Length(Http.Content);
  If Destination <> nil then begin
    Destination.WriteBuffer(Pointer(Http.Content)^, Length(Http.Content));
    Http.Content := '';
  end;
end;

procedure TMoonHttpSocket.RequestInternal(var Context: THttpClientRequest);
var
  Data: RawByteString;
  ResponseBody: TStream;
  StatusText: string;
  StatusLine: RawUtf8;
begin
  FResponseReceived := False;
  Http.Content := '';
  If Aborted or not SockIsDefined then
    raise ENetSock.CreateLastError('Request connection is closed', [], nrClosed);
  If SockIn = nil then
    CreateSockIn;
  TTextRec(SockIn^).InOutFunc := @ReadText;
  { No catch/retry here: a send failure can already have reached the server. }
  RequestSendHeader(Context.Url, Context.Method);
  If Context.KeepAliveSec > 0 then
    SockSend(['Connection: Keep-Alive'#13#10'Keep-Alive: timeout=', Context.KeepAliveSec])
  else
    SockSend('Connection: Close');
  Data := Context.Data;
  If (Data <> '') or ((Context.Method <> 'GET') and (Context.Method <> 'HEAD')) then
    CompressDataAndWriteHeaders(Context.DataMimeType, Data, Context.InStream);
  If Context.Header <> '' then
    SockSend(Context.Header);
  If Http.CompressAcceptEncoding <> '' then
    SockSend(Http.CompressAcceptEncoding);
  SockSendCRLF;
  SockSendFlush(Data);
  If Context.InStream <> nil then begin
    Context.InStream.Position := 0;
    If SockSendStream(Context.InStream, 1 shl 20, False, True) = nrRetry then
      Include(Http.HeaderFlags, hfConnectionClose);
  end;
  case SockReceivePending(TimeOut) of
    cspDataAvailable: ;
    cspDataAvailableOnClosedSocket: Include(Http.HeaderFlags, hfConnectionClose);
    cspNoData:
      raise ENetSock.CreateLastError('Response headers timed out', [], nrTimeout);
  else
    raise ENetSock.CreateLastError('Response connection closed', [], nrClosed);
  end;
  { readln may resize its output before a transport exception. Publish the
    status line only after it was received, so failure classification cannot
    inspect an unfinished output string. }
  SockRecvLn(StatusLine);
  Http.CommandResp := StatusLine;
  StatusText := Utf8ToString(Http.CommandResp);
  If StatusText = '' then
    raise ENetSock.CreateLastError('No HTTP response', [], nrClosed);
  If (Length(StatusText) < 12) or
     ((Copy(StatusText, 1, 9) <> 'HTTP/1.0 ') and (Copy(StatusText, 1, 9) <> 'HTTP/1.1 ')) or
     not TryStrToInt(Copy(StatusText, 10, 3), Context.Status) or
     (Context.Status < 200) or (Context.Status > 599) or
     ((Length(StatusText) > 12) and (StatusText[13] <> ' ')) then
    raise EHttpSocket.Create('Invalid HTTP response status line');
  If not GetHeader(False) then
    raise EHttpSocket.Create('Invalid HTTP response headers');
  FResponseReceived := True;
  If (StatusText[8] = '0') and not (hfConnectionKeepAlive in Http.HeaderFlags) then
    Include(Http.HeaderFlags, hfConnectionClose);
  If (Context.Status <> 204) and (Context.Status <> 304) and not HttpMethodWithNoBody(Context.Method) then begin
    ResponseBody := Context.OutStream;
    If ResponseBody is TStreamRedirect then begin
      If (Context.Status = 200) or (Context.Status = 206) then begin
        If Http.ContentLength > 0 then
          TStreamRedirect(ResponseBody).ExpectedSize := RangeStart + Http.ContentLength;
      end else
        ResponseBody := nil;
    end;
    If (Http.ContentLength < 0) and not (hfTransferChunked in Http.HeaderFlags) then
      ReadCloseDelimitedBody(ResponseBody)
    else
      GetBody(ResponseBody);
  end;
  If Context.Status in HTTP_GET_OK then
    RequestClear;
  If hfConnectionClose in Http.HeaderFlags then
    Close;
end;
