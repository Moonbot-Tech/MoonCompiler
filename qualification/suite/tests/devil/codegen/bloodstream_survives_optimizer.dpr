program bloodstream_survives_optimizer;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
var
  Sink: UInt64;

procedure Feed(Value: UInt64);
begin
  Sink := (Sink xor Value) * 1099511628211;
end;

var
  I: Integer;
begin
  Sink := 14695981039346656037;
  for I := 1 to 8 do
    Feed(UInt64(I));
  WriteLn(Sink);
end.
