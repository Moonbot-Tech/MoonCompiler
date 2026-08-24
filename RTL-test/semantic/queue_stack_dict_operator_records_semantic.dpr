program queue_stack_dict_operator_records_semantic;

{ PENDING 10 (dvl-0059 model beyond TList): TQueue, TStack and
  TDictionary against operator records.  The internal canvases differ
  from Delphi by design - DCC64's queue is a ring buffer, ours is
  linear - so the pinned contract is semantic: the user's Finalize
  never receives a dead zero (every slot the storage buries carries a
  value some user operator produced), reads agree before and after a
  repack, and the dictionary hands back the byte-for-byte measured
  value on both compilers.  Our TQueue.MoveToFront used to FillChar the
  vacated tail - those zeroes reached the user's Finalize when the
  array died; the tail is born again instead (the dvl-0059 model), and
  the repack segment is pinned exactly on our side. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils, Generics.Collections;

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

procedure NoZeroBurials(const Name: string);
begin
  { IntToStr writes no leading zeroes, so "f0" can only be the burial
    of a dead zero no user operator ever produced }
  If Pos('f0', Trace) > 0 then
    raise Exception.CreateFmt('%s: zero burial in "%s"', [Name, Trace]);
end;

procedure QueueScenario;
var
  Q: TQueue<TRes>;
  R: TRes;
  K, V1, V2, V3: Integer;
begin
  Q := TQueue<TRes>.Create;
  try
    for K := 1 to 5 do
    begin
      R.Slot := K * 10;
      Q.Enqueue(R);
    end;
    Q.Dequeue;
    Q.Dequeue;
    { the repack: our linear queue shifts the live block to the front
      and re-births the vacated tail; the exact segment is pinned on our
      side as the regression for the FillChar hole }
    Trace := '';
    Q.TrimExcess;
    {$ifdef FPC}
    If Trace <> 'f101f101iif100f100f100f100f100' then
      raise Exception.CreateFmt('queue repack: "%s"', [Trace]);
    {$endif}
    { the copy canvas differs not just per compiler but per ELEMENT
      (DCC64's ring shrinks while dequeuing, so elements take different
      hop counts) - the canvas-proof contract is identity: each value
      stays inside its own decade (hops are far below 10), and the FIFO
      order survives the repack }
    V1 := Q.Dequeue.Slot;
    V2 := Q.Dequeue.Slot;
    V3 := Q.Dequeue.Slot;
    If (V1 < 30) or (V1 >= 40) or (V2 < 40) or (V2 >= 50) or
       (V3 < 50) or (V3 >= 60) then
      raise Exception.CreateFmt('queue order after repack: %d:%d:%d',
        [V1, V2, V3]);
  finally
    Q.Free;
  end;
end;

procedure StackScenario;
var
  S: TStack<TRes>;
  R: TRes;
  K, LBefore, LAfter: Integer;
begin
  S := TStack<TRes>.Create;
  try
    for K := 1 to 3 do
    begin
      R.Slot := K * 10;
      S.Push(R);
    end;
    S.Pop;
    S.TrimExcess;
    { identity by decade, canvas-proof (see the queue axis) - LIFO
      order 20,10 survives the trim }
    LBefore := S.Pop.Slot;
    LAfter := S.Pop.Slot;
    If (LBefore < 20) or (LBefore >= 30) or (LAfter < 10) or (LAfter >= 20) then
      raise Exception.CreateFmt('stack order after trim: %d:%d',
        [LBefore, LAfter]);
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
    D.Remove(1);
    { measured byte-for-byte on both compilers: the stored value took
      one Assign hop in, the read takes one hop out }
    If D[2].Slot <> 22 then
      raise Exception.CreateFmt('dict value: %d', [D[2].Slot]);
  finally
    D.Free;
  end;
end;

begin
  try
    Trace := '';
    QueueScenario;
    NoZeroBurials('queue');

    Trace := '';
    StackScenario;
    NoZeroBurials('stack');

    Trace := '';
    DictScenario;
    NoZeroBurials('dict');

    WriteLn('QUEUE_STACK_DICT_OPERATOR_RECORDS_OK');
  except
    on E: Exception do begin
      WriteLn('QUEUE_STACK_DICT_OPERATOR_RECORDS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
