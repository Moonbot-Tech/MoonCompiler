program dvl_stress_019_inline_chain;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
function F0(X: Integer): Integer; inline;
begin
  Result := X + 0;
end;
function F1(X: Integer): Integer; inline;
begin
  Result := F0(X) + 1;
end;
function F2(X: Integer): Integer; inline;
begin
  Result := F1(X) + 2;
end;
function F3(X: Integer): Integer; inline;
begin
  Result := F2(X) + 3;
end;
function F4(X: Integer): Integer; inline;
begin
  Result := F3(X) + 4;
end;
function F5(X: Integer): Integer; inline;
begin
  Result := F4(X) + 5;
end;
function F6(X: Integer): Integer; inline;
begin
  Result := F5(X) + 6;
end;
function F7(X: Integer): Integer; inline;
begin
  Result := F6(X) + 7;
end;
function F8(X: Integer): Integer; inline;
begin
  Result := F7(X) + 8;
end;
function F9(X: Integer): Integer; inline;
begin
  Result := F8(X) + 9;
end;
function F10(X: Integer): Integer; inline;
begin
  Result := F9(X) + 10;
end;
function F11(X: Integer): Integer; inline;
begin
  Result := F10(X) + 11;
end;
function F12(X: Integer): Integer; inline;
begin
  Result := F11(X) + 12;
end;
function F13(X: Integer): Integer; inline;
begin
  Result := F12(X) + 13;
end;
function F14(X: Integer): Integer; inline;
begin
  Result := F13(X) + 14;
end;
function F15(X: Integer): Integer; inline;
begin
  Result := F14(X) + 15;
end;
function F16(X: Integer): Integer; inline;
begin
  Result := F15(X) + 16;
end;
function F17(X: Integer): Integer; inline;
begin
  Result := F16(X) + 17;
end;
function F18(X: Integer): Integer; inline;
begin
  Result := F17(X) + 18;
end;
function F19(X: Integer): Integer; inline;
begin
  Result := F18(X) + 19;
end;
function F20(X: Integer): Integer; inline;
begin
  Result := F19(X) + 20;
end;
function F21(X: Integer): Integer; inline;
begin
  Result := F20(X) + 21;
end;
function F22(X: Integer): Integer; inline;
begin
  Result := F21(X) + 22;
end;
function F23(X: Integer): Integer; inline;
begin
  Result := F22(X) + 23;
end;
function F24(X: Integer): Integer; inline;
begin
  Result := F23(X) + 24;
end;
function F25(X: Integer): Integer; inline;
begin
  Result := F24(X) + 25;
end;
function F26(X: Integer): Integer; inline;
begin
  Result := F25(X) + 26;
end;
function F27(X: Integer): Integer; inline;
begin
  Result := F26(X) + 27;
end;
function F28(X: Integer): Integer; inline;
begin
  Result := F27(X) + 28;
end;
function F29(X: Integer): Integer; inline;
begin
  Result := F28(X) + 29;
end;
function F30(X: Integer): Integer; inline;
begin
  Result := F29(X) + 30;
end;
function F31(X: Integer): Integer; inline;
begin
  Result := F30(X) + 31;
end;

var
  R: Integer;
begin
  R := F31(1);
  WriteLn(R);
end.
