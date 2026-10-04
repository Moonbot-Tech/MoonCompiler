program tcdeclarrayconstmismatch1;

{$mode objfpc}

uses
  ucdeclopenarray1;

type
  TCArrayConst = function(const Values: array of const): NativeInt; cdecl;

var
  Proc: TCArrayConst;
begin
  Proc:=@ConstHigh;
  Writeln(Proc([]));
end.
