program mvprobe;

{ dvl-0059 meta-audit oracle for TList.Move: DCC64's Move segment is EMPTY
  (measured: byte-wise reorder, no user operator, no refcount traffic) -
  the value is an ownership transfer through a raw buffer.  Our old Move
  ran a typed temp copy, a Default reset and a FillChar+assign into dead
  zeroes; repaired to three System.Move calls, one model for all types. }
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
begin
  R.Slot := 5;
  L := TList<TRes>.Create;
  try
    L.Add(R);
    R.Slot := 40;
    L.Add(R);
    R.Slot := 70;
    L.Add(R);
    Trace := Trace + '|';
    L.Move(0, 2);
    Trace := Trace + '|';
    WriteLn('vals ', L[0].Slot, ':', L[1].Slot, ':', L[2].Slot);
    Trace := Trace + '|';
  finally
    L.Free;
  end;
end;

begin
  Trace := '';
  Scenario;
  WriteLn('trace ', Trace);
end.
