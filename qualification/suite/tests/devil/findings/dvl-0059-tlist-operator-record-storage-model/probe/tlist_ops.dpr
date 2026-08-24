program tlist_ops;
{$APPTYPE CONSOLE}
uses SysUtils, Generics.Collections;

var
  Trace: string;

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
  Dest.Slot := Src.Slot + 1;
  Trace := Trace + 'a';
end;

procedure Scenario;
var
  L: TList<TRes>;
  R: TRes;
  Pair: array[0..1] of TRes;
  V: TRes;
begin
  R.Slot := 5;
  Pair[0].Slot := 20;
  Pair[1].Slot := 30;
  L := TList<TRes>.Create;
  try
    Trace := Trace + '|add:';
    L.Add(R);
    Trace := Trace + '|ins:';
    L.Insert(0, R);
    Trace := Trace + '|rng:';
    L.InsertRange(1, Pair);
    Trace := Trace + '|=' + IntToStr(L[0].Slot) + ':' + IntToStr(L[1].Slot) + ':' + IntToStr(L[2].Slot) + ':' + IntToStr(L[3].Slot);
    Trace := Trace + '|get:';
    V := L[1];
    Trace := Trace + '=' + IntToStr(V.Slot);
    Trace := Trace + '|del:';
    L.Delete(0);
    Trace := Trace + '|clr:';
    L.Clear;
    Trace := Trace + '|';
  finally
    L.Free;
    Trace := Trace + '$';
  end;
end;

begin
  Trace := '';
  Scenario;
  WriteLn('tlist ', Trace);
end.
