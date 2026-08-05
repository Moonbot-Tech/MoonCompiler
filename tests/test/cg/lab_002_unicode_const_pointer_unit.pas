unit lab_002_unicode_const_pointer_unit;

{$H-}{$X+}{$inline on}

interface

type
  TCollection = object
    procedure AtInsert(Item: Pointer);
  end;

  TUnicodeCollection = object(TCollection)
    procedure AtInsert(const Item: UnicodeString);
  end;

implementation

procedure TCollection.AtInsert(Item: Pointer);
begin
end;

procedure TUnicodeCollection.AtInsert(const Item: UnicodeString);
var
  Temp: Pointer;
begin
  Temp := nil;
  UnicodeString(Temp) := Item;
  TCollection.AtInsert(Pointer(Item));
end;

end.
