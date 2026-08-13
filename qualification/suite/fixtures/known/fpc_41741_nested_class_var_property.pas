program Fpc41741NestedClassVarProperty;

{$mode objfpc}

type
  TNested = object
    InstanceByte: Byte;
    class var SharedWord: Word;
  end;

  TOwner = class
  public
    Nested: TNested;
    property Shared: Word read Nested.SharedWord;
  end;

var
  Owner: TOwner;
begin
  Owner := TOwner.Create;
  try
    Owner.Nested.InstanceByte := 11;
    Owner.Nested.SharedWord := 12;
    if Owner.Shared <> 12 then
      Halt(1);
  finally
    Owner.Free;
  end;
end.
