{ %target=win64 }
{ %opt=-Xe }
program texternalwinunwind;
{$mode delphi}

uses SysUtils;

var
  Cleanups, Catches: Integer;

procedure RaiseThroughFrames(Depth: Integer);
var
  Saved: string;
begin
  Saved:=IntToStr(Depth);
  try
    If Depth=0 then
      StrToInt('not an integer')
    else
      RaiseThroughFrames(Depth-1);
  finally
    If Saved<>IntToStr(Depth) then
      Halt(1);
    Inc(Cleanups);
  end;
end;

begin
  Cleanups:=0;
  Catches:=0;
  try
    RaiseThroughFrames(8);
  except
    on E: EConvertError do
      Inc(Catches);
  end;
  If (Cleanups<>9) or (Catches<>1) then
    Halt(2);
  Writeln('EXTERNAL_WIN_UNWIND_OK');
end.
