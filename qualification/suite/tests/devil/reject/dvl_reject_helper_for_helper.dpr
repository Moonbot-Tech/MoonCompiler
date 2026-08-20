program dvl_reject_helper_for_helper;
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
type
  TBox = record
    Slot: Integer;
  end;
  TBoxHelper = record helper for TBox
    function Ask: Integer;
  end;
  TSecond = record helper for TBoxHelper
    function Ask2: Integer;
  end;

function TBoxHelper.Ask: Integer;
begin
  Result := 1;
end;

function TSecond.Ask2: Integer;
begin
  Result := 2;
end;

begin
  WriteLn('done');
end.
