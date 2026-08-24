program qprobe2;

{ PENDING 10 witness: TQueue<TRes> with Dequeue displacement and
  TrimExcess.  Before the repair our MoveToFront FillChar'ed the vacated
  tail - the trim segment showed f0f0 (the user's Finalize receiving dead
  zeroes); DCC64 shows none on any path.  After the repair the tail is
  born again: trim segment iif100f100f100f100f100, no zero ever reaches
  a user operator.  DCC64's queue is a ring buffer with per-element copy
  canvases - canvases are not the contract, the zero-free burials and
  FIFO identity are. }
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
  Q: TQueue<TRes>;
  R: TRes;
  K: Integer;
begin
  Q := TQueue<TRes>.Create;
  try
    for K := 1 to 5 do
    begin
      R.Slot := K * 10;
      Q.Enqueue(R);
    end;
    Trace := Trace + '|';
    Q.Dequeue;
    Q.Dequeue;
    Trace := Trace + '|';
    Q.TrimExcess;
    Trace := Trace + '|';
    WriteLn('count ', Q.Count, ' front ', Q.Peek.Slot);
    Trace := Trace + '|';
    while Q.Count <> 0 do
    begin
      Trace := Trace + '<';
      Q.Dequeue;
      Trace := Trace + '>';
    end;
    Trace := Trace + '|';
  finally
    Q.Free;
  end;
end;

begin
  Trace := '';
  Scenario;
  WriteLn('trace ', Trace);
end.
