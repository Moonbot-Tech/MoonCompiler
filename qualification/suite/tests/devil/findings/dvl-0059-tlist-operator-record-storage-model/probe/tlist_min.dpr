program tlist_min;
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

procedure AddAddClear;
var
  L: TList<TRes>;
  R: TRes;
begin
  R.Slot := 5;
  L := TList<TRes>.Create;
  try
    Trace := Trace + '|';
    L.Add(R);
    Trace := Trace + '|';
    L.Add(R);
    Trace := Trace + '|' + IntToStr(L[0].Slot) + ':' + IntToStr(L[1].Slot) + '|';
    L.Clear;
    Trace := Trace + '|';
  finally
    L.Free;
  end;
end;

procedure AddInsert;
var
  L: TList<TRes>;
  R: TRes;
begin
  R.Slot := 5;
  L := TList<TRes>.Create;
  try
    Trace := Trace + '|';
    L.Add(R);
    Trace := Trace + '|';
    L.Insert(0, R);
    Trace := Trace + '|' + IntToStr(L[0].Slot) + ':' + IntToStr(L[1].Slot) + '|';
  finally
    L.Free;
    Trace := Trace + '$';
  end;
end;

begin
  Trace := '';
  AddAddClear;
  WriteLn('addclear ', Trace);
  Trace := '';
  AddInsert;
  WriteLn('addins   ', Trace);
end.
