{ A static ARRAY parameter (not open array) of Assign-records copies
  through the operators on the caller side (DCC64):
  ii|iiaay11:21f11f21|f10f20 }
program oa4;
{$APPTYPE CONSOLE}
uses SysUtils;

var
  Trace: string;

type
  TRes = record
    Slot: Integer;
    class operator Initialize(out Dest: TRes);
    class operator Finalize(var Dest: TRes);
    class operator Assign(var Dest: TRes; const [ref] Src: TRes);
  end;

  TPair = array[0..1] of TRes;

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

procedure TakePair(P: TPair);
begin
  Trace := Trace + 'y' + IntToStr(P[0].Slot) + ':' + IntToStr(P[1].Slot);
end;

procedure Scenario;
var
  P: TPair;
begin
  P[0].Slot := 10; P[1].Slot := 20;
  Trace := Trace + '|';
  TakePair(P);
  Trace := Trace + '|';
end;

begin
  Trace := '';
  Scenario;
  WriteLn('staticpair ', Trace);
end.
