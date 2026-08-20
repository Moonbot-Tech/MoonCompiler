unit devil_init_b;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, devil_runtime, devil_init_c;

type
  TDvlBHolder = class
  public
    class var Stamp: Integer;
    class constructor Create;
    class destructor Destroy;
  end;

var
  DvlBMark: Integer;
  DvlBText: AnsiString;

implementation

class constructor TDvlBHolder.Create;
begin
  Stamp := 2;
  DevilUnitTrailAdd('B');
end;

class destructor TDvlBHolder.Destroy;
begin
  Stamp := 0;
end;

initialization
  DevilUnitTrailAdd('b');
  DvlBMark := 20;
  DvlBText := 'bbb';
  { a unit sees its dependency already initialized }
  DvlBMark := DvlBMark + DvlCMark;

finalization
  DevilUnitTrailAdd('B');

end.
