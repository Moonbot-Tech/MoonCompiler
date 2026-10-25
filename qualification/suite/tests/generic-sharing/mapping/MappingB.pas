unit MappingB;
{$mode delphi}
interface
uses MappingCore;
function AliasClass: TClass;
function AliasInfo: Pointer;
function StringClass: TClass;
function MakeString: IValue<UnicodeString>;
implementation
function AliasClass:TClass;
begin
  Result:=TBox<TIntAlias>;
end;
function AliasInfo:Pointer;
begin
  Result:=TypeInfo(IIntAlias);
end;
function StringClass:TClass;
begin
  Result:=TBox<UnicodeString>;
end;
function MakeString:IValue<UnicodeString>;
begin
  Result:=TBox<UnicodeString>.Create('shared string');
end;
end.