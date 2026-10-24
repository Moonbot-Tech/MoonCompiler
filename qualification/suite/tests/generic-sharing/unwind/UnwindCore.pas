unit UnwindCore;
interface
uses System.SysUtils;
type
  TWork<T> = class
    class function Leaf(X: Integer): Integer; static;
    class function Checked(X: Integer): Integer; static;
  end;
var Finalized: Integer;
implementation
class function TWork<T>.Leaf(X: Integer): Integer;
begin Result := X + SizeOf(T); end;
class function TWork<T>.Checked(X: Integer): Integer;
var S: UnicodeString;
begin
  S := IntToStr(X) + ': managed payload';
  try
    if X < 0 then raise Exception.Create(S);
    Result := Length(S) + SizeOf(T);
  finally Inc(Finalized); end;
end;
end.
