unit MappingCore;
{$mode delphi}
interface
uses SysUtils;
type
  IValue<T> = interface
    function Value: T;
    function Tag: Integer;
  end;
  IAlt<T> = interface
    function Value: T;
    function Tag: Integer;
  end;
  TBox<T> = class(TInterfacedObject,IValue<T>,IAlt<T>)
  private
    FValue: T;
    function MainValue: T;
    function AltValue: T;
    function MainTag: Integer;
    function AltTag: Integer;
    function IValue<T>.Value = MainValue;
    {$ifdef WRONG_MAPPING}
    function IValue<T>.Tag = AltTag;
    {$else}
    function IValue<T>.Tag = MainTag;
    {$endif}
    function IAlt<T>.Value = AltValue;
    function IAlt<T>.Tag = AltTag;
  public
    constructor Create(const V: T);
    destructor Destroy; override;
  end;
  TDerived<T> = class(TBox<T>);
  TIntAlias = Integer;
  IIntAlias = IValue<TIntAlias>;
  TFixed<T> = class(TInterfacedObject,IValue<Integer>)
    function GetValue: Integer;
    function GetTag: Integer;
    function IValue<TIntAlias>.Value = GetValue;
    function IIntAlias.Tag = GetTag;
  end;
var Destroyed: Integer;
implementation
constructor TBox<T>.Create(const V:T);
begin
  inherited Create;
  FValue:=V;
end;
destructor TBox<T>.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;
function TBox<T>.MainValue:T;
begin
  Result:=FValue;
end;
function TBox<T>.AltValue:T;
begin
  Result:=Default(T);
end;
function TBox<T>.MainTag:Integer;
begin
  Result:=11;
end;
function TBox<T>.AltTag:Integer;
begin
  Result:=29;
end;
function TFixed<T>.GetValue:Integer;
begin
  Result:=71;
end;
function TFixed<T>.GetTag:Integer;
begin
  Result:=83;
end;
end.