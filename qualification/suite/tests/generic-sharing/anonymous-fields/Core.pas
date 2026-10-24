unit Core;interface {$RTTI EXPLICIT FIELDS([vcPublic])}
type TBox<T>=class public
 Items:array of T;
 OtherItems:array of T;
 Matrix:array of array of T;
 Extra:record Item:T;More:array of T;end;
 end;
implementation end.
