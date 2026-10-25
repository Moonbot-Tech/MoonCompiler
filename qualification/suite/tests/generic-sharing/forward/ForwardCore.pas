unit ForwardCore;
{$mode delphi}
interface
uses SysUtils;
type
  TForward<T> = class;
  IForward<T> = interface;
  TBridge<T> = class
    Typed:TForward<T>;
    TypedRef:IForward<T>;
    Number:TForward<Integer>;
    Text:TForward<UnicodeString>;
    NumberRef:IForward<Integer>;
    TextRef:IForward<UnicodeString>;
  end;
  IForward<T> = interface
    function GetValue:T;
  end;
  TForward<T> = class(TInterfacedObject,IForward<T>)
    Value:T;
    function GetValue:T;
    destructor Destroy; override;
  end;
var Finalized:Integer;
implementation
function TForward<T>.GetValue:T;
begin
  Result:=Value;
end;
destructor TForward<T>.Destroy;
begin
  Inc(Finalized);
  inherited;
end;
end.