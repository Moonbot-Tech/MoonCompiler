unit uarrayinit1;

{$mode delphi}

interface

var
  InitializeCount: Integer;

type
  TManaged = record
    State: Word;
    class operator Initialize(var Value: TManaged);
  end;
  TManagedArray = array[1..2] of TManaged;
  TWrapper = record
    Values: TManagedArray;
  end;

var
  Direct: TManagedArray;
  Wrapped: TWrapper;

implementation

class operator TManaged.Initialize(var Value: TManaged);
begin
  Inc(InitializeCount);
  Value.State := $4145;
end;

end.
