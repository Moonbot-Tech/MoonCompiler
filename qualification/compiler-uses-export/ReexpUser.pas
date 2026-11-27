unit ReexpUser;

{ uses the bundle only; its interface depends on ReexpA through it }
{$mode unleashed}

interface

uses
  ReexpBundle;

function Make: TReexpA;

implementation

function Make: TReexpA;
begin
  Result.X := 3;
end;

end.
