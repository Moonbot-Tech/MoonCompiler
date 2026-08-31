program ExeInfoElfHeaderSemantic;

{%TARGET=linux}

{$mode delphiunicode}

uses
  SysUtils;

procedure KnownFrame;
begin
end;

var
  Location: ShortString;
begin
  { BackTraceStrFunc reaches ExeInfo.GetExeInMemoryBaseAddr through the DWARF
    line-info hook.  Under a Unicode RTL the ELF magic must still be read as
    four bytes, not as two WideChar values. }
  Location := BackTraceStrFunc(@KnownFrame);
  If Pos('KnownFrame', string(Location)) = 0 then
    raise Exception.Create('DWARF backtrace did not resolve KnownFrame: ' +
      string(Location));
  If Pos('$0000000000000000', string(Location)) <> 0 then
    raise Exception.Create('DWARF backtrace resolved a nil address');
  WriteLn('EXEINFO_ELF_HEADER_PASS');
end.
