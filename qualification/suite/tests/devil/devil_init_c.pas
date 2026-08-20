unit devil_init_c;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, devil_runtime;

type
  TDvlCHolder = class
  public
    class var Stamp: Integer;
    class constructor Create;
    class destructor Destroy;
  end;

var
  DvlCMark: Integer;
  DvlCText: AnsiString;

implementation

class constructor TDvlCHolder.Create;
begin
  Stamp := 1;
  DevilUnitTrailAdd('C');
end;

class destructor TDvlCHolder.Destroy;
begin
  Stamp := 0;
end;

initialization
  DevilUnitTrailAdd('c');
  DvlCMark := 10;
  DvlCText := 'ccc';

finalization
  DevilUnitTrailAdd('C');
  { finalization runs in reverse, so the unit that was ready first shuts down last }
  DevilCheckTrail('dvl-init-shutdown-trail', DevilUnitTrail, 'CcBbAayxABC');

end.
