{ %OPT=-O2 }
program tmooncollectionreset1;

{$mode delphi}

uses
  Classes;

var
  Collection: TCollection;
begin
  Collection := TCollection.Create(TCollectionItem);
  try
    if Collection.Add.ID <> 0 then
      Halt(1);
    if Collection.Add.ID <> 1 then
      Halt(2);
    Collection.ClearAndResetID;
    if Collection.Add.ID <> 0 then
      Halt(3);
  finally
    Collection.Free;
  end;
end.
