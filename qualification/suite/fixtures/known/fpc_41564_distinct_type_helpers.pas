program Fpc41564DistinctTypeHelpers;

{$mode objfpc}
{$modeswitch advancedrecords}

type
  TFoo = record end;
  TBar = type TFoo;
  TBaz = type TFoo;

  TBarHelper = record helper for TBar
    function Marker: LongInt;
  end;

  TBazHelper = record helper for TBaz
    function Marker: LongInt;
  end;

function TBarHelper.Marker: LongInt;
begin
  Result := 1;
end;

function TBazHelper.Marker: LongInt;
begin
  Result := 2;
end;

var
  Value: TBar;
begin
  if Value.Marker <> 1 then
    Halt(1);
end.
