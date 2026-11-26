unit HolderUnit;

{ Names a package class only in a published field: the field class table is
  the one reference to the package's VMT. }

{$mode delphi}

interface

uses
  BaseUnit;

type
  {$M+}
  THolder = class
  published
    Item: TBase;
  end;

implementation

end.
