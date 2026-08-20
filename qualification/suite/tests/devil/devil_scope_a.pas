unit devil_scope_a;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}

interface

function DvlScopePick: Integer;

implementation

function DvlScopePick: Integer;
begin
  Result := 1;
end;

end.
