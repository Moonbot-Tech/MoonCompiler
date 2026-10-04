unit Moon.Diagnostics.Http;

{$mode delphiunicode}{$H+}

interface

procedure InitializeDiagnosticHttp(UseTLS: Boolean);
function PostDiagnosticFile(const FileName, URL, FieldName, SuccessText: string;
  TimeoutMS: LongInt; out StatusCode: LongInt): string;

implementation

uses SysUtils, Classes, mormot.core.base, mormot.core.unicode,
  mormot.net.sock, mormot.net.client, MoonORMot.Need
  {$ifdef LINUX}, mormot.lib.openssl11{$endif};

type
  TReplyStream = class(TMemoryStream)
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

function TReplyStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  If Size + Count > 65536 then raise EWriteError.Create('Diagnostic HTTP reply exceeds 64 KiB');
  Result := inherited Write(Buffer, Count);
end;

procedure InitializeDiagnosticHttp(UseTLS: Boolean);
begin
  {$ifdef LINUX}
  If UseTLS and not OpenSslIsAvailable then raise Exception.Create('Diagnostic HTTPS requires OpenSSL');
  {$endif}
end;

function PostDiagnosticFile(const FileName, URL, FieldName, SuccessText: string;
  TimeoutMS: LongInt; out StatusCode: LongInt): string;
var
  Uri: TUri;
  Options: THttpRequestExtendedOptions;
  Client: THttpClientSocket;
  Body: THttpMultiPartStream;
  Reply: TReplyStream;
  Text: RawUtf8;
begin
  StatusCode := 0;
  try
    If not Uri.From(StringToUtf8(URL)) then raise Exception.Create('Invalid diagnostic POST URL');
    Options.Init;
    Options.CreateTimeoutMS := TimeoutMS;
    Client := THttpClientSocket.OpenOptions(Uri, Options);
    try
      Body := THttpMultiPartStream.Create;
      try
        Body.AddFile(StringToUtf8(FieldName), FileName, 'application/zip');
        Body.Flush;
        Reply := TReplyStream.Create;
        try
          { retry=True marks the request as already retried: never replay a POST. }
          StatusCode := Client.Request(Uri.Address, 'POST', 0, '', '',
            Body.MultipartContentType, True, Body, Reply);
          If (StatusCode < 200) or (StatusCode >= 300) then
            raise Exception.Create('HTTP status ' + IntToStr(StatusCode));
          If SuccessText <> '' then begin
            SetString(Text, PAnsiChar(Reply.Memory), Reply.Size);
            If Pos(StringToUtf8(SuccessText), Text) = 0 then
              raise Exception.Create('Required receiver acknowledgement missing');
          end;
          Result := '';
        finally
          Reply.Free;
        end;
      finally
        Body.Free;
      end;
    finally
      Client.Free;
    end;
  except
    on E: Exception do Result := E.Message;
  end;
end;
end.
