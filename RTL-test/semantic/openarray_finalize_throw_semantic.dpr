program openarray_finalize_throw_semantic;

{ A failed open-array value copy owns its raw carrier.  User Finalize may
  itself raise while the helper unwinds a failed Assign; releasing the raw
  allocation therefore belongs in a finally.  The bundled MM shutdown census
  makes every skipped carrier release fail closed. }

{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

var
  FinalizeBoom: Boolean;

type
  TValue = record
    Number: Integer;
    class operator Initialize(out Dest: TValue);
    class operator Finalize(var Dest: TValue);
    class operator Assign(var Dest: TValue; const [ref] Src: TValue);
  end;

class operator TValue.Initialize(out Dest: TValue);
begin
  Dest.Number := 100;
end;

class operator TValue.Finalize(var Dest: TValue);
begin
  If FinalizeBoom then begin
    FinalizeBoom := False;
    raise Exception.Create('finalize boom');
  end;
end;

class operator TValue.Assign(var Dest: TValue; const [ref] Src: TValue);
begin
  If Src.Number = 20 then
    raise Exception.Create('assign boom');
  Dest.Number := Src.Number;
end;

procedure TakeValues(Values: array of TValue);
begin
  Halt(2);
end;

procedure FailCopy;
var
  Values: array[0..1] of TValue;
begin
  Values[0].Number := 10;
  Values[1].Number := 20;
  TakeValues(Values);
end;

var
  Round: Integer;
begin
  for Round := 1 to 64 do begin
    FinalizeBoom := True;
    try
      FailCopy;
      Halt(3);
    except
      on E: Exception do
        If E.Message <> 'finalize boom' then
          Halt(4);
    end;
  end;
  WriteLn('OPENARRAY_FINALIZE_THROW_OK');
end.
