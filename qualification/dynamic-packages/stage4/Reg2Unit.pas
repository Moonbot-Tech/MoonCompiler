unit Reg2Unit;

{ Derives from BasePkg's TBaseThing just like RegUnit, but lives in a
  different package (Reg2Pkg). Having two packages share the same required
  package tests that "a dependency still referenced by another loaded
  package stays mapped". See host14. }

{$mode delphi}

interface

uses
  Classes,
  BaseRegUnit;

type
  TReg2Demo = class(TBaseThing)
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterClass(TReg2Demo);
end;

end.
