program int64_vs_int_card;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, TypInfo, Rtti;

function Pick(const V: Integer): Integer; overload;
begin
  Result := 1;
end;

function Pick(const V: Cardinal): Integer; overload;
begin
  Result := 2;
end;

function Wide: Int64;
begin
  Result := 7;
end;

begin
  WriteLn('int64 arg -> ', Pick(Wide));
end.