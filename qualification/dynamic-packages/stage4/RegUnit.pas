unit RegUnit;

{$mode delphi}

interface

uses
  Classes,
  BaseRegUnit;

type
  { Derives from a class in a required package, so BaseRegUnit really is in
    RegPkg's used_units and the skip rule has something to skip. }
  TRegDemo = class(TBaseThing)
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterClass(TRegDemo);
end;

end.
