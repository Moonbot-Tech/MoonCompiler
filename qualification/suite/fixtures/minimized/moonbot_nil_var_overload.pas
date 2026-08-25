program moonbot_nil_var_overload;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

type
  TItem = record
    Value: Integer;
  end;
  PItem = ^TItem;
  PPItem = ^PItem;

function Pick(AValue: PPItem): Integer; overload;
begin
  Result := 11;
end;

function Pick(var AValue: PItem): Integer; overload;
begin
  Result := 22;
end;

begin
  if Pick(nil) <> 11 then
    Halt(1);
end.
