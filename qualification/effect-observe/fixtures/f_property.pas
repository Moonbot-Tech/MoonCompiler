unit f_property;

{ Property access: getters and setters are calls with a side-effect budget
  of their own - two reads never fold, and the model reports the property
  origin of the call. }

interface

type
  TP = class
  private
    FV: Integer;
    function GetV: Integer;
    procedure SetV(x: Integer);
  public
    property V: Integer read GetV write SetV;
  end;

procedure PropUse(o: TP);

implementation

function TP.GetV: Integer;
begin
  Result := FV;
end;

procedure TP.SetV(x: Integer);
begin
  FV := x;
end;

// EXPECT: proc=PropUse ie=st reason=property_access
procedure PropUse(o: TP);
begin
  o.V := o.V + 1;
end;

end.
