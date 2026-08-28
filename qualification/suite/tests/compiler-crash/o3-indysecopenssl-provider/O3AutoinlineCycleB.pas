unit O3AutoinlineCycleB;

{$mode delphi}

interface

uses
  O3AutoinlineCycleA;

procedure TouchPrivateClassVar;

implementation

type
  THolder = class
  private
    class var FValue: Pointer;
  end;

procedure TouchPrivateClassVar;
begin
  If THolder.FValue = nil then
    THolder.FValue := Pointer(1);
end;

end.
