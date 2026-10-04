program trangecombineorientation1;

{$mode delphi}

function SplitAnd1(X: Integer): Boolean; noinline;
var
  A,B: Boolean;
begin
  A:=3<=X;
  B:=7<X;
  Result:=A and B;
end;

function DirectAnd1(X: Integer): Boolean; inline;
begin
  Result:=(3<=X) and (7<X);
end;

function SplitAnd2(X: Integer): Boolean; noinline;
var
  A,B: Boolean;
begin
  A:=X>=3;
  B:=X>7;
  Result:=A and B;
end;

function DirectAnd2(X: Integer): Boolean; inline;
begin
  Result:=(X>=3) and (X>7);
end;

function SplitOr1(X: Integer): Boolean; noinline;
var
  A,B: Boolean;
begin
  A:=3>X;
  B:=7>=X;
  Result:=A or B;
end;

function DirectOr1(X: Integer): Boolean; inline;
begin
  Result:=(3>X) or (7>=X);
end;

function SplitOr2(X: Integer): Boolean; noinline;
var
  A,B: Boolean;
begin
  A:=X<3;
  B:=X<=7;
  Result:=A or B;
end;

function DirectOr2(X: Integer): Boolean; inline;
begin
  Result:=(X<3) or (X<=7);
end;

var
  X: Integer;
begin
  for X:=-2 to 12 do
    begin
      if DirectAnd1(X)<>SplitAnd1(X) then Halt(1);
      if DirectAnd2(X)<>SplitAnd2(X) then Halt(2);
      if DirectOr1(X)<>SplitOr1(X) then Halt(3);
      if DirectOr2(X)<>SplitOr2(X) then Halt(4);
    end;
end.
