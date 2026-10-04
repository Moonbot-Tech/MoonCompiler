program inline_forward;
{$mode delphi}
{ Delphi accepts "inline; forward;": a forward declaration that carries inline,
  body below, calls after the body inlined. }

function Twice(X: Integer): Integer; inline; forward;
function Thrice(X: Integer): Integer; forward; inline;

function UseBefore(X: Integer): Integer;
begin
  { called before the body is known: an ordinary call }
  Result := Twice(X) + Thrice(X);
end;

function Twice(X: Integer): Integer;
begin
  Result := X * 2;
end;

function Thrice(X: Integer): Integer;
begin
  Result := X * 3;
end;

function UseAfter(X: Integer): Integer;
begin
  { called after the body is known: inlined at -O2/-O3 }
  Result := Twice(X) + Thrice(X);
end;

var
  V: Integer;
begin
  V := 0;
  V := V + UseBefore(7) + UseAfter(11);
  If V <> 35 + 55 then begin
    WriteLn('FAIL ', V);
    Halt(1);
  end;
  WriteLn('INLINE_FORWARD_OK');
end.
