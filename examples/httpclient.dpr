program httpclient;

{$APPTYPE CONSOLE}

{ GET a URL with the Delphi HTTP client surface.  System.Net.HttpClient is
  compiled over mORMot (from the mormot directory next to toolchain);
  System.Net.URLClient is an installed unit of the toolchain. }

uses
  System.SysUtils,
  System.Net.URLClient,
  System.Net.HttpClient;

begin
  If ParamCount <> 1 then begin
    Writeln('usage: httpclient <url>');
    Halt(2);
  end;
  var Client := THTTPClient.Create;
  try
    Client.UserAgent := 'MoonCompiler example';
    Client.AcceptEncoding := 'gzip, deflate';
    var Response := Client.Get(ParamStr(1));
    Writeln(Response.StatusCode, ' ', Response.StatusText);
    for var Header in Response.Headers do
      Writeln(Header.Name, ': ', Header.Value);
    Writeln;
    Writeln(Copy(Response.ContentAsString, 1, 400));
  finally
    Client.Free;
  end;
end.
