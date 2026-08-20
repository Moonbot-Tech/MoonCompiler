unit devil_init_a;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, devil_runtime, devil_init_b;

type
  TDvlAHolder = class
  public
    class var Stamp: Integer;
    class constructor Create;
    class destructor Destroy;
  end;

var
  DvlAMark: Integer;
  DvlAText: AnsiString;

implementation

class constructor TDvlAHolder.Create;
begin
  Stamp := 3;
  DevilUnitTrailAdd('A');
end;

class destructor TDvlAHolder.Destroy;
begin
  Stamp := 0;
end;

initialization
  DevilUnitTrailAdd('a');
  DvlAMark := 30;
  DvlAText := 'aaa';
  { a unit sees its dependency already initialized }
  DvlAMark := DvlAMark + DvlBMark;

finalization
  DevilUnitTrailAdd('A');

end.
