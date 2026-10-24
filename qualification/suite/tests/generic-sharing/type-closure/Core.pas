unit Core;
interface
uses System.SysUtils;
{$RTTI EXPLICIT FIELDS([vcPublic]) METHODS([vcPublic]) PROPERTIES([vcPublic])}
type
 TFn<T>=function:T;
 TBox<T>=class public Value:T;function Read:T;end;
 TContainer<T>=class
 public type
  TValues=TArray<T>;
  TPtr=^T;
  TClassRef=class of TObject;
  TCallback=function:T;
  TNested=class public Value:T;end;
 public
  Items:TValues;
  Ptr:TPtr;
  Cls:TClassRef;
  Callback:TCallback;
  Nested:TNested;
  function GetItems:TValues;
  function GetPtr:TPtr;
  function GetClass:TClassRef;
  function GetCallback:TCallback;
  function GetNested:TNested;
 end;
implementation
function TBox<T>.Read:T;begin Result:=Value;end;
function TContainer<T>.GetItems:TValues;begin Result:=Items;end;
function TContainer<T>.GetPtr:TPtr;begin Result:=Ptr;end;
function TContainer<T>.GetClass:TClassRef;begin Result:=Cls;end;
function TContainer<T>.GetCallback:TCallback;begin Result:=Callback;end;
function TContainer<T>.GetNested:TNested;begin Result:=Nested;end;
end.
