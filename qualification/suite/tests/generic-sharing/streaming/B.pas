unit B;
interface
uses System.Classes, Core;
function StoredClass: TComponentClass;
function CheckStored(C: TComponent): Boolean;
implementation
function StoredClass: TComponentClass;
begin
  Result := TStored<Integer>;
end;
function CheckStored(C: TComponent): Boolean;
begin
  Result := (C is TStored<Integer>) and (C.Name = 'Saved') and
    (TStored<Integer>(C).Number = 123456) and
    (TStored<Integer>(C).Caption = 'text '#$0416#$D83D#$DE00);
end;
end.
