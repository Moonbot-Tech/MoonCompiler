unit PkgUnit;

{$mode delphi}

interface

function Hello: string;

implementation

function Hello: string;
begin
  Result := 'hello from package';
end;

end.
