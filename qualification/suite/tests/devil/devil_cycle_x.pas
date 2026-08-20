unit devil_cycle_x;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, devil_runtime;

function DvlXStep(Depth: Integer): Integer;

var
  DvlXReady: Integer;

implementation

uses
  devil_cycle_y;

function DvlXStep(Depth: Integer): Integer;
begin
  If Depth <= 0 then
    Result := 3
  else
    { the call goes to the other unit, which calls back here }
    Result := 3 + DvlYStep(Depth - 1);
end;

initialization
  DevilUnitTrailAdd('x');
  DvlXReady := 3;

end.
