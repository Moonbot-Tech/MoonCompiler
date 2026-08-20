program try_finally_paths_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the inline-finally normal path on Win64 SEH: the
  finalizer must run exactly once on every road out of the try block -
  normal fall-through, exception unwind (single and nested), break,
  continue and exit - and call-bearing finalizers keep the funclet path. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef linux}
  cthreads,
  {$endif}
  {$endif}
  SysUtils;

var
  Trace: array[0..63] of Integer;
  TraceCount: Integer;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

procedure Mark(Value: Integer);
begin
  If TraceCount > High(Trace) then
    Fail('trace overflow');
  Trace[TraceCount] := Value;
  Inc(TraceCount);
end;

procedure ResetTrace;
begin
  TraceCount := 0;
end;

procedure CheckTrace(const Expected: array of Integer; const Msg: string);
var
  I: Integer;
begin
  If TraceCount <> Length(Expected) then
    Fail(Msg + ': trace length ' + IntToStr(TraceCount));
  for I := 0 to High(Expected) do
    If Trace[I] <> Expected[I] then
      Fail(Msg + ': trace at ' + IntToStr(I));
end;

{ call-free finalizer: the inline-copy candidate }
function NormalPath(A, B: Integer): Integer;
var
  Cleanup: Integer;
begin
  Cleanup := 0;
  try
    Result := A + B;
  finally
    Cleanup := Cleanup + 1;
  end;
  Result := Result * 10 + Cleanup;
end;

{ finalizer with a call keeps the funclet }
function CallPath(A: Integer): Integer;
begin
  try
    Result := A * 2;
  finally
    Mark(100 + A);
  end;
end;

procedure ExceptionalPath;
var
  Cleanup: Integer;
begin
  Cleanup := 0;
  try
    try
      Mark(1);
      raise Exception.Create('boom');
    finally
      Cleanup := Cleanup + 7;
      Mark(2);
    end;
    Mark(3); { must not run }
  except
    on E: Exception do
      Mark(4);
  end;
  If Cleanup <> 7 then
    Fail('exceptional cleanup value');
end;

procedure NestedException;
begin
  try
    try
      try
        Mark(10);
        raise Exception.Create('inner');
      finally
        Mark(11);
      end;
    finally
      Mark(12);
    end;
  except
    Mark(13);
  end;
end;

procedure LoopEscapes;
var
  I, Sum, Fin: Integer;
begin
  Sum := 0;
  Fin := 0;
  for I := 1 to 10 do
    try
      If I = 3 then
        continue;
      If I = 5 then
        break;
      Sum := Sum + I;
    finally
      Fin := Fin + 1;
    end;
  If (Sum <> 1 + 2 + 4) or (Fin <> 5) then
    Fail(Format('loop escapes sum=%d fin=%d', [Sum, Fin]));
end;

function ExitFromTry(A: Integer): Integer;
var
  Fin: Integer;
begin
  Fin := 0;
  try
    If A > 0 then
    begin
      Result := A;
      exit;
    end;
    Result := -1;
  finally
    Fin := Fin + 1;
    Mark(200 + Fin);
  end;
  Result := Result - 1000; { must not run when A > 0 }
end;

var
  I, V: Integer;
begin
  { normal path many times: finalizer once per pass }
  V := 0;
  for I := 1 to 1000 do
    V := NormalPath(I, I + 1);
  If V <> (1000 + 1001) * 10 + 1 then
    Fail('normal path value');

  ResetTrace;
  V := CallPath(5);
  If (V <> 10) or (TraceCount <> 1) or (Trace[0] <> 105) then
    Fail('call path');

  ResetTrace;
  ExceptionalPath;
  CheckTrace([1, 2, 4], 'exceptional path');

  ResetTrace;
  NestedException;
  CheckTrace([10, 11, 12, 13], 'nested exception');

  LoopEscapes;

  ResetTrace;
  V := ExitFromTry(42);
  If (V <> 42) then
    Fail('exit from try result');
  CheckTrace([201], 'exit from try finalizer');

  ResetTrace;
  V := ExitFromTry(0);
  If (V <> -1001) then
    Fail('no-exit fall-through result');
  CheckTrace([201], 'fall-through finalizer');

  WriteLn('TRY_FINALLY_PATHS_OK');
end.
