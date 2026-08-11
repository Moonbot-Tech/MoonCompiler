program paszlib_delphi_unicode;

{$mode delphiunicode}

uses
  System.ZLib.Zbase;

begin
  If zError(Z_STREAM_ERROR) <> 'stream error' then
    Halt(1);
  If zError(123) <> 'Unknown zlib error 123' then
    Halt(2);
  WriteLn('PASZLIB_DELPHI_UNICODE_OK');
end.
