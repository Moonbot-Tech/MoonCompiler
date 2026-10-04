unit funcref_value_units_user_unit;
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$ENDIF}
{ Methods and overloaded routines of another unit given to "reference to"
  in a unit; the program gives the same method to references too. }
interface

uses
  funcref_value_units_class_unit;

function RunUser(A, B: TCounter): Integer;

implementation

function RunUser(A, B: TCounter): Integer;
var
  P, Q, PI: TIntProc;
  PS: TStrProc;
begin
  P := A.Step;
  Q := B.Step;
  PI := PutValue;
  PS := PutValue;
  P(1);
  Q(10);
  PI(5);
  PS('abc');
  Result := A.Count * 100 + B.Count;
end;

end.
