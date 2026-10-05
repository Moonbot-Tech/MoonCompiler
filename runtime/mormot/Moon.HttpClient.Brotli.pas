{ Optional HTTP Brotli support. Add this unit to the application's uses clause
  to link the MIT-licensed decoder and enable Content-Encoding: br. }
unit Moon.HttpClient.Brotli;

{$mode delphi}{$H+}

interface

implementation

uses
  Classes, System.Net.HttpClient, Moon.Brotli;

procedure DecodeBrotli(Source, Destination: TStream; EncodedSize: Int64);
begin
  try
    BrotliDecompress(Source, Destination, EncodedSize);
  except
    on E: EBrotliError do
      raise ENetHTTPResponseException.Create(E.Message);
  end;
end;

initialization
  RegisterBrotliDecoder(DecodeBrotli);
finalization
  RegisterBrotliDecoder(nil);
end.
