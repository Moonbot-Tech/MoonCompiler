{ Default(T) of operator-record carriers, measured DCC64 vs ours.
  Values: DCC 101:100:100:101:0 (fresh Initialize'd source; the record
  assignment runs the user's Assign (+1), the ARRAY assignment moves the
  temporary without Assign), ours after the repair 101:101:101:101:0
  (source Initialize'd for every carrier, our array assignment still
  runs element-wise Assign - the move canvas is the pending cluster).
  Before the repair the array/aggregate sources were plain zeroes. }
program defval;
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

  THolder = record
    Arr: TPair;
    Plain: Integer;
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
  R: TRes;
  P: TPair;
  H: THolder;
begin
  R.Slot := 5;
  P[0].Slot := 6;
  P[1].Slot := 7;
  H.Arr[0].Slot := 8;
  H.Arr[1].Slot := 9;
  H.Plain := 3;
  Trace := Trace + '|';
  R := Default(TRes);
  P := Default(TPair);
  H := Default(THolder);
  Trace := Trace + '|' + IntToStr(R.Slot) + ':' + IntToStr(P[0].Slot) + ':' + IntToStr(P[1].Slot) + ':' + IntToStr(H.Arr[0].Slot) + ':' + IntToStr(H.Plain) + '|';
end;

begin
  Trace := '';
  Scenario;
  WriteLn('default ', Trace);
end.
