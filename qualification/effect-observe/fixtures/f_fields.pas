unit f_fields;

{ Record/object fields: a field of a value record is the record variable
  itself (descend to the base symbol); a field of a heap instance is escaped
  memory with an implicit nil trap. }

interface

type
  TRec = record
    A, B: Integer;
  end;

  TObj = class
  public
    F: Integer;
  end;

function RecLocal(x: Integer): Integer;
function ObjField(o: TObj): Integer;

implementation

// EXPECT: proc=RecLocal r=L w=L ie=- temps=0 reasons=-
function RecLocal(x: Integer): Integer;
var
  t: TRec;
begin
  t.A := x;
  t.B := t.A * 2;
  Result := t.A + t.B;
end;

// EXPECT: proc=ObjField r=LE w=LE ie=t reasons=may_trap:2
function ObjField(o: TObj): Integer;
begin
  o.F := 5;
  Result := o.F;
end;

end.
