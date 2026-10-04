program generic_inline_funcref;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$ENDIF}
{ An anonymous function held by a reference declared in a method of a generic
  class or in a generic method.  With a "reference to" type written in the var
  section itself (FPC syntax; Delphi 12.2 declares method reference types by
  name only, E2003) the specialization took the reference and the anonymous
  function for the same type: the conversion was dropped - the reference got
  the bytes of the code - and a call through the reference stopped the
  compiler.  The named types are the same forms in Delphi syntax: this part
  of the program is checked against Delphi 12.2, the inline part against the
  same program without generics. }
uses
  SysUtils;

type
  TIntFunc = reference to function: Integer;
  TIntArgFunc = reference to function(A: Integer): Integer;

  TBox<T> = class
  type
    TFuncT = reference to function: T;
  public
    Item: T;
    Base: Integer;
    function Constant: Integer;
    function Sized: Integer;
    function Assigned_: Integer;
    function Echo: T;
    function Captures: Integer;
    function Twice: Integer;
{$IFDEF FPC}
    function InlineConstant: Integer;
    function InlineSized: Integer;
    function InlineAssigned: Integer;
    function InlineEcho: T;
    function InlineCaptures: Integer;
    function InlineTwice: Integer;
{$ENDIF}
  end;

  THolder = class
    Base: Integer;
    function Generic<T>: Integer;
{$IFDEF FPC}
    function InlineGeneric<T>: Integer;
{$ENDIF}
  end;

var
  Failures: Integer;

function TBox<T>.Constant: Integer;
var
  F: TIntFunc;
begin
  F := function: Integer
    begin
      Result := 6;
    end;
  Result := F();
end;

function TBox<T>.Sized: Integer;
var
  F: TIntFunc;
begin
  F := function: Integer
    begin
      Result := SizeOf(T);
    end;
  Result := F();
end;

function TBox<T>.Assigned_: Integer;
var
  F: TIntFunc;
begin
  F := function: Integer
    begin
      Result := SizeOf(T);
    end;
  Result := 0;
  If Assigned(F) then
    Result := 1;
end;

function TBox<T>.Echo: T;
var
  F: TFuncT;
begin
  F := function: T
    begin
      Result := Item;
    end;
  Result := F();
end;

function TBox<T>.Captures: Integer;
var
  F: TIntArgFunc;
  K: Integer;
begin
  K := 10;
  F := function(A: Integer): Integer
    begin
      Result := A + K + Base + SizeOf(Item);
    end;
  K := 20;
  Result := F(1000);
end;

function TBox<T>.Twice: Integer;
var
  F, G: TIntFunc;
begin
  F := function: Integer
    begin
      Result := 1;
    end;
  G := function: Integer
    begin
      Result := F() + 1;
    end;
  Result := F() * 10 + G();
end;

function THolder.Generic<T>: Integer;
var
  F: TIntFunc;
begin
  F := function: Integer
    begin
      Result := Base + SizeOf(T);
    end;
  Result := F();
end;

{$IFDEF FPC}
function TBox<T>.InlineConstant: Integer;
var
  F: reference to function: Integer;
begin
  F := function: Integer
    begin
      Result := 6;
    end;
  Result := F();
end;

function TBox<T>.InlineSized: Integer;
var
  F: reference to function: Integer;
begin
  F := function: Integer
    begin
      Result := SizeOf(T);
    end;
  Result := F();
end;

function TBox<T>.InlineAssigned: Integer;
var
  F: reference to function: Integer;
begin
  F := function: Integer
    begin
      Result := SizeOf(T);
    end;
  Result := 0;
  If Assigned(F) then
    Result := 1;
end;

function TBox<T>.InlineEcho: T;
var
  F: reference to function: T;
begin
  F := function: T
    begin
      Result := Item;
    end;
  Result := F();
end;

function TBox<T>.InlineCaptures: Integer;
var
  F: reference to function(A: Integer): Integer;
  K: Integer;
begin
  K := 10;
  F := function(A: Integer): Integer
    begin
      Result := A + K + Base + SizeOf(Item);
    end;
  K := 20;
  Result := F(1000);
end;

function TBox<T>.InlineTwice: Integer;
var
  F, G: reference to function: Integer;
begin
  F := function: Integer
    begin
      Result := 1;
    end;
  G := function: Integer
    begin
      Result := F() + 1;
    end;
  Result := F() * 10 + G();
end;

function THolder.InlineGeneric<T>: Integer;
var
  F: reference to function: Integer;
begin
  F := function: Integer
    begin
      Result := Base + SizeOf(T);
    end;
  Result := F();
end;
{$ENDIF}

procedure Check(const Name: string; Got, Want: Integer);
begin
  If Got <> Want then begin
    WriteLn('FAIL ', Name, ': got ', Got, ', expected ', Want);
    Inc(Failures);
  end;
end;

procedure CheckStr(const Name, Got, Want: string);
begin
  If Got <> Want then begin
    WriteLn('FAIL ', Name, ': got ', Got, ', expected ', Want);
    Inc(Failures);
  end;
end;

var
  BI: TBox<Integer>;
  BS: TBox<string>;
  BL: TBox<Int64>;
  H: THolder;
begin
  Failures := 0;
  BI := TBox<Integer>.Create;
  BS := TBox<string>.Create;
  BL := TBox<Int64>.Create;
  H := THolder.Create;
  BI.Item := 8;
  BI.Base := 100;
  BL.Base := 200;
  BS.Item := 'abc';
  H.Base := 50;

  Check('constant', BI.Constant, 6);
  Check('sized-integer', BI.Sized, 4);
  Check('sized-int64', BL.Sized, 8);
  Check('assigned', BS.Assigned_, 1);
  Check('echo', BI.Echo, 8);
  CheckStr('echo-string', BS.Echo, 'abc');
  Check('captures-integer', BI.Captures, 1124);
  Check('captures-int64', BL.Captures, 1228);
  Check('twice', BI.Twice, 12);
  Check('generic-method', H.Generic<Int64>, 58);
{$IFDEF FPC}
  Check('inline-constant', BI.InlineConstant, 6);
  Check('inline-sized-integer', BI.InlineSized, 4);
  Check('inline-sized-int64', BL.InlineSized, 8);
  Check('inline-assigned', BS.InlineAssigned, 1);
  Check('inline-echo', BI.InlineEcho, 8);
  CheckStr('inline-echo-string', BS.InlineEcho, 'abc');
  Check('inline-captures-integer', BI.InlineCaptures, 1124);
  Check('inline-captures-int64', BL.InlineCaptures, 1228);
  Check('inline-twice', BI.InlineTwice, 12);
  Check('inline-generic-method', H.InlineGeneric<Int64>, 58);
{$ENDIF}
  If Failures = 0 then
    WriteLn('GENERIC_INLINE_FUNCREF_OK')
  else begin
    WriteLn('GENERIC_INLINE_FUNCREF_FAILED ', Failures);
    Halt(1);
  end;
end.
