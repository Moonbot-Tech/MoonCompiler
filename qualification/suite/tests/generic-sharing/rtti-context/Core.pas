unit Core;
interface
uses System.SysUtils;
type TMarkAttribute=class(TCustomAttribute) end;
{$RTTI EXPLICIT FIELDS([vcPublic]) METHODS([vcPublic]) PROPERTIES([])}
type
 [TMark]
 TBox<T>=class
 private
  Hidden:T;
  function HiddenMethod:T;
 public
  [TMark]
  Visible:T;
  [TMark]
  function VisibleMethod:T;
  property VisibleProperty:T read Visible;
  type TInner=class public Visible:T; end;
 end;
type TRec<T>=record private Hidden:T; public Visible:T; end;
implementation
function TBox<T>.HiddenMethod:T;begin Result:=Hidden;end;
function TBox<T>.VisibleMethod:T;begin Result:=Visible;end;
end.
