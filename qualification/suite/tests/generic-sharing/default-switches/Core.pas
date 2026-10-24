unit Core;
interface
type TBox<T>=class class function AddOne(X:Integer):Integer;static;class function ReadAt(I:Integer):T;static;end;
implementation
class function TBox<T>.AddOne(X:Integer):Integer;begin Result:=X+1;end;
class function TBox<T>.ReadAt(I:Integer):T;var A:array[0..0] of T;begin A[0]:=Default(T);Result:=A[I];end;
end.
