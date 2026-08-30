program evalorder;
{$APPTYPE CONSOLE}
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
uses SysUtils;

var
  Trace: string;

function F(N: Integer): Integer;
begin
  Trace := Trace + IntToStr(N);
  Result := N;
end;

function G(N: Integer): Int64;
begin
  Trace := Trace + IntToStr(N);
  Result := N;
end;

procedure Two(A, B: Integer);
begin
end;

var
  X: Integer;
  Y: Int64;
begin
  Trace := ''; X := F(1) shr F(2);              WriteLn('shr:      ', Trace);
  Trace := ''; X := F(1) + F(2);                WriteLn('plus:     ', Trace);
  Trace := ''; X := F(1) - F(2);                WriteLn('minus:    ', Trace);
  Trace := ''; X := F(1) * F(2);                WriteLn('mul:      ', Trace);
  Trace := ''; X := F(4) div F(2);              WriteLn('div:      ', Trace);
  Trace := ''; Y := G(1) shl G(2);              WriteLn('shl64:    ', Trace);
  Trace := ''; X := F(1) or F(2);               WriteLn('or:       ', Trace);
  Trace := ''; Two(F(1), F(2));                 WriteLn('args:     ', Trace);
  Trace := ''; X := F(1) + F(2) * F(3);         WriteLn('mixed:    ', Trace);
  Trace := ''; if (F(1) = 1) and (F(2) = 2) then; WriteLn('and-bool: ', Trace);
end.
