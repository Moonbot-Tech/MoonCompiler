program dvl_stress_015_overload_set;
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
function Pick(X: ShortInt): Integer; overload;
begin
  Result := 0;
end;
function Pick(X: Byte): Integer; overload;
begin
  Result := 1;
end;
function Pick(X: SmallInt): Integer; overload;
begin
  Result := 2;
end;
function Pick(X: Word): Integer; overload;
begin
  Result := 3;
end;
function Pick(X: Integer): Integer; overload;
begin
  Result := 4;
end;
function Pick(X: Cardinal): Integer; overload;
begin
  Result := 5;
end;
function Pick(X: Int64): Integer; overload;
begin
  Result := 6;
end;
function Pick(X: UInt64): Integer; overload;
begin
  Result := 7;
end;
function Pick(X: Single): Integer; overload;
begin
  Result := 8;
end;
function Pick(X: Double): Integer; overload;
begin
  Result := 9;
end;
function Pick(X: Currency): Integer; overload;
begin
  Result := 10;
end;
function Pick(X: string): Integer; overload;
begin
  Result := 11;
end;
function Pick(X: AnsiString): Integer; overload;
begin
  Result := 12;
end;
function Pick(X: Boolean): Integer; overload;
begin
  Result := 13;
end;
function Pick(X: AnsiChar): Integer; overload;
begin
  Result := 14;
end;
function Pick(X: WideChar): Integer; overload;
begin
  Result := 15;
end;

var
  I: Integer;
begin
  I := 1;
  WriteLn(Pick(I));
end.
