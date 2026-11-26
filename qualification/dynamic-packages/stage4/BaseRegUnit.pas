unit BaseRegUnit;

{ Lives in BasePkg and has a Register of its own. RegPkg requires BasePkg and
  uses this unit, so it appears in RegPkg's used_units -- but it must NOT show
  up in RegPkg's REGPROCS. Each unit belongs to exactly one table: the one for
  the package that contains it. }

{$mode delphi}

interface

uses
  Classes;

type
  TBaseThing = class(TComponent)
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterClass(TBaseThing);
end;

end.
