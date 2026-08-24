program container_owned_initialize_semantic;

{ A capacity slot is a live value, not padding.  This probe gives every
  Initialize a real heap allocation, so a byte-wise overwrite of an idle slot
  becomes an observable leak instead of being hidden by nil strings. }

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
  LiveResources: Integer;
  BaselineResources: Integer;

type
  TOwned = record
    Data: Pointer;
    Value: Integer;
    class operator Initialize(out Dest: TOwned);
    class operator Finalize(var Dest: TOwned);
    class operator Assign(var Dest: TOwned; const [ref] Src: TOwned);
  end;

class operator TOwned.Initialize(out Dest: TOwned);
begin
  GetMem(Dest.Data, 1);
  Inc(LiveResources);
  Dest.Value := 0;
end;

class operator TOwned.Finalize(var Dest: TOwned);
begin
  { A discarded managed-record function result may be fresh storage in the
    current ABI; this probe is about ownership leaks, not that separate
    function-result canvas. }
  If Dest.Data = nil then
    Exit;
  FreeMem(Dest.Data);
  Dest.Data := nil;
  Dec(LiveResources);
end;

class operator TOwned.Assign(var Dest: TOwned; const [ref] Src: TOwned);
var
  NewData: Pointer;
begin
  GetMem(NewData, 1);
  Inc(LiveResources);
  { Assignment may also materialize a function result directly into fresh
    storage.  Only an already live destination owns an old resource. }
  If Dest.Data <> nil then begin
    FreeMem(Dest.Data);
    Dec(LiveResources);
  end;
  Dest.Data := NewData;
  Dest.Value := Src.Value;
end;

procedure ListInsertShifts;
var
  L: TList<TOwned>;
  R: TOwned;
begin
  R.Value := 7;
  L := TList<TOwned>.Create;
  try
    L.Capacity := 8;
    L.Add(R);
    L.Insert(0, R);
    L.InsertRange(1, [R, R]);
  finally
    L.Free;
  end;
end;

procedure QueueRepack;
var
  Q: TQueue<TOwned>;
  R: TOwned;
  K, BeforeRepack, OldCapacity, ExpectedDrop: Integer;
begin
  Q := TQueue<TOwned>.Create;
  try
    for K := 1 to 5 do begin
      R.Value := K;
      Q.Enqueue(R);
    end;
    Q.Dequeue;
    Q.Dequeue;
    OldCapacity := Q.Capacity;
    BeforeRepack := LiveResources;
    ExpectedDrop := OldCapacity - Q.Count;
    Q.TrimExcess;
    If LiveResources <> BeforeRepack - ExpectedDrop then
      raise Exception.CreateFmt(
        'queue repack leaked idle slots: live %d, expected %d',
        [LiveResources, BeforeRepack - ExpectedDrop]);
    Q.Clear;
  finally
    Q.Free;
  end;
end;

begin
  try
    { Generic specializations keep their Default(T) sentinel alive for the
      lifetime of the program.  It is not container-owned and is finalized by
      the unit/program finalizer, so leaks are measured relative to that
      stable baseline rather than against zero before finalization runs. }
    BaselineResources := LiveResources;
    ListInsertShifts;
    If LiveResources <> BaselineResources then
      raise Exception.CreateFmt('list leaked initialized capacity slots: %d',
        [LiveResources - BaselineResources]);
    QueueRepack;
    If LiveResources <> BaselineResources then
      raise Exception.CreateFmt('queue leaked initialized capacity slots: %d',
        [LiveResources - BaselineResources]);
    WriteLn('CONTAINER_OWNED_INITIALIZE_OK');
  except
    on E: Exception do begin
      WriteLn('CONTAINER_OWNED_INITIALIZE_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
