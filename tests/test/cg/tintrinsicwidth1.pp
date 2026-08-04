{ %OPT=-O2 }
program tintrinsicwidth1;

{ The Delphi computation model must not leak into other modes: outside it
  a narrow intrinsic keeps its operand type, which is what lets the x86
  backend use SSE for it at all.  Widening here would silently move the
  operation onto the 80-bit x87 path. }

{$mode objfpc}
{$excessprecision off}

var
  S: Single;
  D: Double;
  Wide: Double;
begin
  S := 2.0;
  D := Sqrt(S);
  { the single-wide root, widened only by the assignment }
  Wide := Single(1.4142135623730951);
  if D <> Wide then
    begin
      WriteLn('FAIL sqrt widened outside mode Delphi');
      Halt(1);
    end;

  S := 16777215.0;
  D := Sqr(S);
  Wide := Single(281474943156225.0);
  if D <> Wide then
    begin
      WriteLn('FAIL sqr widened outside mode Delphi');
      Halt(2);
    end;
end.
