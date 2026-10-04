unit cyctypes;

{ The other half: declares the type, and its implementation inlines cycrel.Relation, whose
  result conversion names that type. }

{$mode delphi}

interface

type
  TRelation = -1..1;

  TSpan = record
    Low, High: Single;
    function IsEmpty: Boolean;
    function Width: Single;
  end;

implementation

uses
  cycrel;

function TSpan.IsEmpty: Boolean;
begin
  Result := Relation(High, Low) <= 0;
end;

function TSpan.Width: Single;
begin
  Result := Scaled(High - Low);
end;

end.
