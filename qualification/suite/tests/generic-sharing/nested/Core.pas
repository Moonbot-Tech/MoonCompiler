unit Core;
interface
var Count, FinCount: Integer;
type TOuter<T> = class
  type TInner = class
    class var S: UnicodeString;
    class constructor Init;
    class destructor Fini;
  end;
end;
implementation
class constructor TOuter<T>.TInner.Init;
begin Inc(Count); S := 'ready'; end;
class destructor TOuter<T>.TInner.Fini;
begin Inc(FinCount); end;
initialization
finalization Writeln('FIN=',FinCount);
end.
