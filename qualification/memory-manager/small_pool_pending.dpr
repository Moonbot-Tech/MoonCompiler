program SmallPoolPending;
{$mode delphi}{$H+}
uses mormot.core.fpcx64mm, Classes, SysUtils, Windows;

type
  TFreer = class(TThread)
    P: Pointer;
    procedure Execute; override;
  end;

procedure TFreer.Execute;
begin
  FreeMem(P);
end;

procedure Require(B: Boolean; const Text: string);
begin
  If not B then begin
    WriteLn('PENDING_FAIL ', Text);
    Halt(1);
  end;
end;

var
  Held: array[0..1023] of Pointer;
  Count, I: Integer;
  P, Q, R, OldPool, Pool, BlockType, Target: Pointer;
  Freer: TFreer;
  Started: QWord;
  Multi: Boolean;
begin
  Multi := ParamStr(1) = 'multi';
  Freer := TFreer.Create(True);
  GetMem(Held[0], 1500);
  OldPool := Fpcx64mmTestSmallPool(Held[0]);
  Count := 1;
  repeat
    GetMem(P, 1500);
    Pool := Fpcx64mmTestSmallPool(P);
    If Pool <> OldPool then Break;
    Require(Count < Length(Held), 'fill bound');
    Held[Count] := P;
    Inc(Count);
  until False;
  Require(Count > 2, 'multi-member pool required');
  for I := 1 to 12 do begin
    FreeMem(P);
    GetMem(P, 1500);
  end;
  Pool := Fpcx64mmTestSmallPool(P);
  BlockType := Fpcx64mmTestSmallBlockType(P);
  Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = 8, 'pool not hot');
  PByte(Held[2])^ := $A7;
  Q := Held[0];
  Fpcx64mmTestLockSmallBlockType(Q, True);
  FreeMem(Q);
  Fpcx64mmTestLockSmallBlockType(P, False);
  Require(Fpcx64mmTestSmallLastFreeCount(P) = 1, 'one pending item required');
  Target := P;
  If Multi then Target := Held[1];
  Freer.P := Target;
  PolicyArm(Target);
  Freer.Start;
  Started := GetTickCount64;
  while PolicyStage <> 1 do begin
    Require(GetTickCount64 - Started < 5000, 'hook timeout');
    Sleep(0);
  end;
  // Consume the queue under LastFreeLocked while the freer owns class Locked.
  // The original reason for entering UnlockSlow must survive this interleaving.
  GetMem(R, 1500);
  Require(R = Q, 'deferred item was not consumed');
  Require(Fpcx64mmTestSmallLastFreeCount(P) = 0, 'queue was not emptied');
  PolicyRelease;
  Freer.WaitFor;
  Require(Fpcx64mmTestSmallRetainedPool(BlockType) = Pool, 'retention policy changed');
  Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = 8, 'reuse score changed');
  Require(PByte(Held[2])^ = $A7, 'live neighbour corrupted');
  Require(Fpcx64mmTestSmallPool(Held[2]) = OldPool, 'live pool changed');
  Held[0] := R;
  If Multi then begin
    Held[1] := nil;
    FreeMem(P);
  end;
  for I := 0 to Count - 1 do
    If Held[I] <> nil then FreeMem(Held[I]);
  Freer.Free;
  Require(CurrentHeapFragmentationStatus.Errors = 0, 'heap topology');
  WriteLn('PENDING_PASS multi=', Ord(Multi), ' held=', Count);
end.
