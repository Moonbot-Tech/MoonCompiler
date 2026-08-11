unit uimpfuncspez38b;

{$mode Delphi}

interface

function Test<T>(const A: TArray<T>): Integer; overload;

implementation

function Test<T>(const A: TArray<T>): Integer;
begin
  Result:=2;
end;

end.
