program tracker_mb_06;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}

var
  Value: Int64;

begin
  Value := Random(High(UInt64)) + 1;
  WriteLn(Value);
end.
