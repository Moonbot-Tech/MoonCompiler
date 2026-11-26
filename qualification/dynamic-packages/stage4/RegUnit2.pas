unit RegUnit2;

{ Second contained unit with a Register, so the REGPROCS walk is exercised
  with more than one entry. With a single-unit package a broken iteration
  would still have printed TableCount = 1. }

{$mode delphi}

interface

uses
  Classes;

type
  TRegDemo2 = class(TComponent)
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterClass(TRegDemo2);
end;

end.
