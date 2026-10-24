unit UnwindA;
interface
function GetClass: TClass;
function Leaf: Integer;
function Call(X: Integer): Integer;
implementation
uses UnwindCore;
function GetClass: TClass;
begin Result := TWork<Integer>; end;
function Leaf: Integer;
begin Result := TWork<Integer>.Leaf(5); end;
function Call(X: Integer): Integer;
begin Result := TWork<Integer>.Checked(X); end;
end.
