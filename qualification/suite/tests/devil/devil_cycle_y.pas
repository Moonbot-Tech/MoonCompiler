unit devil_cycle_y;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, devil_runtime;

function DvlYStep(Depth: Integer): Integer;

var
  DvlYReady: Integer;

implementation

uses
  devil_cycle_x;

function DvlYStep(Depth: Integer): Integer;
begin
  If Depth <= 0 then
    Result := 4
  else
    { the call goes to the other unit, which calls back here }
    Result := 4 + DvlXStep(Depth - 1);
end;

initialization
  DevilUnitTrailAdd('y');
  DvlYReady := 4;

end.
