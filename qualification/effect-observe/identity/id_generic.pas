unit id_generic;

{ PPU-identity workload: a generic declaration makes the scanner record a
  settings snapshot into the generic token buffer, which is serialized into
  the PPU.  The observe flag must not change a single byte of it. }

{$mode delphi}

interface

type
  TPair<T> = class
  public
    A, B: T;
    function Sum: T;
  end;

function UsePair(x, y: Integer): Integer;

implementation

function TPair<T>.Sum: T;
begin
  Result := A + B;
end;

function UsePair(x, y: Integer): Integer;
var
  p: TPair<Integer>;
begin
  p := TPair<Integer>.Create;
  try
    p.A := x;
    p.B := y;
    Result := p.Sum;
  finally
    p.Free;
  end;
end;

end.
