program arrpair_wide;

{ dvl-0059 meta-audit oracle: TList<array[0..3] of TRes> - a wide managed
  static array, where DCC64 works and shows the canon: InsertRange runs the
  user operators per element (gap slots born, Assign per element, honest
  burials; measured vals 23:33/8:10).  The original LDirect gate excluded
  only tkRecord, so tkArray slipped into the byte-wise Move+addref arm and
  bypassed the operators - addref runs mop AddRef, and the Delphi Assign
  lives in RTTI as mop Copy. }
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

type
  TPair = array[0..3] of TRes;

procedure Scenario;
var
  L: TList<TPair>;
  P, Q: TPair;
begin
  P[0].Slot := 5;
  P[1].Slot := 7;
  Q[0].Slot := 20;
  Q[1].Slot := 30;
  WriteLn('step: create');
  L := TList<TPair>.Create;
  try
    WriteLn('step: add  trace=', Trace);
    L.Add(P);
    WriteLn('step: insertrange  trace=', Trace);
    L.InsertRange(0, [Q]);
    WriteLn('step: read  trace=', Trace);
    WriteLn('vals ', L[0][0].Slot, ':', L[0][1].Slot, '/', L[1][0].Slot, ':', L[1][1].Slot);
    WriteLn('step: free  trace=', Trace);
  finally
    L.Free;
  end;
  WriteLn('step: done  trace=', Trace);
end;

begin
  Trace := '';
  Scenario;
end.
