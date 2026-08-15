program ice5;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
begin
  if Odd(UInt64($FFFFFFFFFFFFFFFE)) then
    WriteLn('odd')
  else
    WriteLn('even');
end.
