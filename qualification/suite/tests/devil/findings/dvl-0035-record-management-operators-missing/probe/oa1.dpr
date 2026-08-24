{ Open array of Assign-records by value: the DCC64 copy model.
  static3  - phases at the array level (all Initialize, then all Assign),
             copy finalized in direct order before returning:
             iii|iiiaaay3:11:31f11f21f31|f10f20f30
  emptydyn - an empty dynamic array calls nothing:        |y0|
  dyn2     - dynamic array source, same operator copy:    ii|iiaay2:8:9f8f9|f7f8
  slice2   - Slice() source:                              iii|iiaay2:2:3f2f3|f1f2f3 }
program oa1;
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

procedure TakeAll(A: array of TRes);
begin
  Trace := Trace + 'y' + IntToStr(Length(A));
  If Length(A) > 0 then
    Trace := Trace + ':' + IntToStr(A[0].Slot) + ':' + IntToStr(A[High(A)].Slot);
end;

procedure StaticThree;
var
  A: array[0..2] of TRes;
begin
  A[0].Slot := 10; A[1].Slot := 20; A[2].Slot := 30;
  Trace := Trace + '|';
  TakeAll(A);
  Trace := Trace + '|';
end;

procedure EmptyDyn;
var
  D: TArray<TRes>;
begin
  D := nil;
  Trace := Trace + '|';
  TakeAll(D);
  Trace := Trace + '|';
end;

procedure DynTwo;
var
  D: TArray<TRes>;
begin
  SetLength(D, 2);
  D[0].Slot := 7; D[1].Slot := 8;
  Trace := Trace + '|';
  TakeAll(D);
  Trace := Trace + '|';
end;

procedure OpenSlice;
var
  A: array[0..2] of TRes;
begin
  A[0].Slot := 1; A[1].Slot := 2; A[2].Slot := 3;
  Trace := Trace + '|';
  TakeAll(Slice(A, 2));
  Trace := Trace + '|';
end;

begin
  Trace := '';
  StaticThree;
  WriteLn('static3  ', Trace);
  Trace := '';
  EmptyDyn;
  WriteLn('emptydyn ', Trace);
  Trace := '';
  DynTwo;
  WriteLn('dyn2     ', Trace);
  Trace := '';
  OpenSlice;
  WriteLn('slice2   ', Trace);
end.
