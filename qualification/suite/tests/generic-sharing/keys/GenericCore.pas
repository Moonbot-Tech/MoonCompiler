unit GenericCore;
interface
uses System.SysUtils;
type
  TIntAlias = Integer;
  TIntDistinct = type Integer;
  IProbe = interface
    ['{0B519DE2-807D-49F5-BCBA-9ACEC773C988}']
    function ReadValue: Integer;
  end;
  TBox<T> = class
  public
    class var Counter: Integer;
    Value: T;
    class constructor Init;
    function Echo(const X: T): T;
    function Plus(X: Integer): Integer; virtual;
  end;
  TDerived<T> = class(TBox<T>)
  public
    function Plus(X: Integer): Integer; override;
  end;
  TPair<T,U> = record
    First: T;
    Second: U;
    function CopyFirst: T;
  end;
  TAdapter<T> = class(TInterfacedObject, IProbe)
    function ReadValue: Integer;
  end;
type
  TOuter<T> = class
  public type TNested = class
    function Value: Integer;
  end;
  end;
var Initializations: Integer;
implementation
function TOuter<T>.TNested.Value: Integer;
begin Result := SizeOf(T); end;
class constructor TBox<T>.Init;
begin Inc(Initializations); Counter := 4; end;
function TBox<T>.Echo(const X: T): T;
begin Value := X; Result := Value; end;
function TBox<T>.Plus(X: Integer): Integer;
begin Result := X + 7; end;
function TDerived<T>.Plus(X: Integer): Integer;
begin Result := inherited Plus(X) + 4; end;
function TPair<T,U>.CopyFirst: T;
begin Result := First; end;
function TAdapter<T>.ReadValue: Integer;
begin Result := SizeOf(T) + 31; end;
end.
