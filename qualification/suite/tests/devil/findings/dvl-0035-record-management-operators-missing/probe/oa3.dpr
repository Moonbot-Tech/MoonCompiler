{ A raising Assign in the middle of the parameter copy: DCC64 leaks the
  whole copy unfinalized (nothing of it is finalized, only the caller's
  locals unwind):  iii|iiiaA!f10f20f30X }
program oa3;
{$APPTYPE CONSOLE}
uses SysUtils;

var
  Trace: string;
  Boom: Integer;

type
  TRes = record
    Slot: Integer;
    class operator Initialize(out Dest: TRes);
    class operator Finalize(var Dest: TRes);
    class operator Assign(var Dest: TRes; const [ref] Src: TRes);
  end;

class operator TRes.Initialize(out Dest: TRes);
begin
  Dest.Slot := 100;
  Trace := Trace + 'i';
end;

class operator TRes.Finalize(var Dest: TRes);
begin
  Trace := Trace + 'f' + IntToStr(Dest.Slot);
end;

class operator TRes.Assign(var Dest: TRes; const [ref] Src: TRes);
begin
  Dec(Boom);
  If Boom = 0 then begin
    Trace := Trace + 'A!';
    raise Exception.Create('boom');
  end;
  Dest.Slot := Src.Slot + 1;
  Trace := Trace + 'a';
end;

procedure TakeAll(A: array of TRes);
begin
  Trace := Trace + 'y' + IntToStr(A[0].Slot);
end;

procedure Scenario;
var
  A: array[0..2] of TRes;
begin
  A[0].Slot := 10; A[1].Slot := 20; A[2].Slot := 30;
  Boom := 2;  { second Assign raises }
  Trace := Trace + '|';
  TakeAll(A);
  Trace := Trace + '|';
end;

begin
  Trace := '';
  try
    Scenario;
  except
    Trace := Trace + 'X';
  end;
  WriteLn('raise2nd ', Trace);
end.
