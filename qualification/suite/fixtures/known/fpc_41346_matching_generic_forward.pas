program Project1;

{$mode objfpc}

type
  generic TBar<A,B: TObject> = class;

  generic TBar<A, B: TObject> = class
    F:A;
    X:B;
  end;

begin
end.
