{ Aggregates as open array elements, same phase model (DCC64):
  outer2 - record with an operator field:  ii|iiaay41:5f41f51|f40f50
  pair1  - static array as element type:   ii|iiaay61:71f61f71|f60f70 }
program oa2;
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

  TOuter = record
    Inner: TRes;
    Plain: Integer;
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

procedure TakeOuter(A: array of TOuter);
begin
  Trace := Trace + 'y' + IntToStr(A[0].Inner.Slot) + ':' + IntToStr(A[0].Plain);
end;

procedure TakePairs(A: array of TPair);
begin
  Trace := Trace + 'y' + IntToStr(A[0][0].Slot) + ':' + IntToStr(A[0][1].Slot);
end;

procedure OuterTwo;
var
  A: array[0..1] of TOuter;
begin
  A[0].Inner.Slot := 40; A[0].Plain := 5;
  A[1].Inner.Slot := 50; A[1].Plain := 6;
  Trace := Trace + '|';
  TakeOuter(A);
  Trace := Trace + '|';
end;

procedure PairOne;
var
  A: array[0..0] of TPair;
begin
  A[0][0].Slot := 60; A[0][1].Slot := 70;
  Trace := Trace + '|';
  TakePairs(A);
  Trace := Trace + '|';
end;

begin
  Trace := '';
  OuterTwo;
  WriteLn('outer2  ', Trace);
  Trace := '';
  PairOne;
  WriteLn('pair1   ', Trace);
end.
