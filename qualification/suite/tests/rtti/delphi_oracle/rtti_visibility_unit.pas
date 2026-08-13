unit rtti_visibility_unit;

interface

uses
  System.Rtti;

type
  {$RTTI EXPLICIT FIELDS([vcPrivate,vcPublic])}

  TInterfaceType = class
  end;

  TOuterType = class
  public type
    TNestedType = class
    end;
  end;

function TouchVisibilityTypes: Boolean;

implementation

type
  {$RTTI EXPLICIT FIELDS([vcPrivate,vcPublic])}

  TImplementationType = class
  end;

function TouchVisibilityTypes: Boolean;
begin
  Result:=
    TInterfaceType.InheritsFrom(TObject) and
    TOuterType.TNestedType.InheritsFrom(TObject) and
    TImplementationType.InheritsFrom(TObject);
end;

end.
