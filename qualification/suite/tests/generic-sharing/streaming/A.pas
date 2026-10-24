unit A;
interface
uses System.Classes, Core;
function StoredClass: TComponentClass;
function MakeStored: TComponent;
implementation
function StoredClass: TComponentClass;
begin
  Result := TStored<Integer>;
end;
function MakeStored: TComponent;
var C: TStored<Integer>;
begin
  C := TStored<Integer>.Create(nil);
  C.Name := 'Saved';
  C.Number := 123456;
  C.Caption := 'text '#$0416#$D83D#$DE00;
  Result := C;
end;
end.
