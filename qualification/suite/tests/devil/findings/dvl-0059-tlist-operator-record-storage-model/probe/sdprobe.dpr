program sdprobe;

{ PENDING 10 witness: TStack and TDictionary against operator records are
  CLEAN on both compilers - no zero burials anywhere (the Default(T)
  slot reset is DCC64's own native form: an Assign from the
  operator-initialized Default variable into a live slot), and the
  dictionary value reads back byte-for-byte identical (22) on both. }
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

procedure StackScenario;
var
  S: TStack<TRes>;
  R: TRes;
  K: Integer;
begin
  S := TStack<TRes>.Create;
  try
    for K := 1 to 3 do
    begin
      R.Slot := K * 10;
      S.Push(R);
    end;
    Trace := Trace + '|';
    S.Pop;
    Trace := Trace + '|';
    S.TrimExcess;
    Trace := Trace + '|';
    WriteLn('stack count ', S.Count, ' top ', S.Peek.Slot);
  finally
    S.Free;
  end;
end;

procedure DictScenario;
var
  D: TDictionary<Integer, TRes>;
  R: TRes;
begin
  D := TDictionary<Integer, TRes>.Create;
  try
    R.Slot := 10;
    D.Add(1, R);
    R.Slot := 20;
    D.Add(2, R);
    Trace := Trace + '|';
    D.Remove(1);
    Trace := Trace + '|';
    WriteLn('dict count ', D.Count, ' v2 ', D[2].Slot);
  finally
    D.Free;
  end;
end;

begin
  Trace := '';
  StackScenario;
  WriteLn('stack trace ', Trace);
  Trace := '';
  DictScenario;
  WriteLn('dict trace ', Trace);
end.
