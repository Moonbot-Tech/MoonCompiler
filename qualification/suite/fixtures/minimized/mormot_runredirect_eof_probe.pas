program mormot_runredirect_eof_probe;

{$mode delphiunicode}

uses
  mormot.core.fpcx64mm,
  cthreads,
  SysUtils,
  mormot.core.base,
  mormot.core.os;

var
  ExitCode: integer;
  Output: RawByteString;

begin
  Output := RunRedirect('/bin/printf moon-eof', @ExitCode);
  If (ExitCode <> 0) or (Output <> 'moon-eof') then
    Halt(1);
  Writeln('PASS mormot-runredirect-eof');
end.
