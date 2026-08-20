unit devil_scope_b;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}

interface

function DvlScopePick: Integer;

implementation

function DvlScopePick: Integer;
begin
  Result := 2;
end;

end.
