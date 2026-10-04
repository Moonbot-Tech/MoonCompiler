program method_value_lifetime;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ A method pointer to a method of a value that is no variable
  (M := MakeRecI(1).Step) points into a temporary Delphi keeps until the
  routine that made it ends - a routine, the main block; that of the
  initialization of a unit lives with the variables of the unit - one per
  place in the source, so that taking the pointer again there replaces the
  value; the value is finalized then, here counted by the destructor of the
  object in its interface field. One source for Delphi 12.2 and
  MoonCompiler; the finalization of the unit prints the verdict. }
uses
  method_value_lifetime_unit;

procedure Routine;
var
  M: TMethodProc;
begin
  M := MakeRecI(1).Step;
  M(2);
  Check('routine-alive', Destroyed, 1);
end;

procedure Loop;
var
  Ms: array[1..3] of TMethodProc;
  I: Integer;
begin
  for I := 1 to 3 do
    Ms[I] := MakeRecI(I * 10).Step;
  Check('loop-replaced', Destroyed, 4);
  Ms[1](1);
  Check('loop-one-value', Last, 31);
end;

var
  M: TMethodProc;
begin
  { the inline variable of the initialization is finalized, its value not }
  Check('initialization-inline-finalized', Destroyed, 1);
  Routine;
  Check('routine-finalized', Destroyed, 2);
  Loop;
  Check('loop-finalized', Destroyed, 5);
  M := MakeRecI(1).Step;
  M(2);
  Check('main-block-alive', Destroyed * 10 + Last, 53);
end.
