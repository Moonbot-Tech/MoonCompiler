program inlrec4;
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

procedure SinkTwoMix(A, B: TRes); inline;
var
  M: TRes;
begin
  M.Slot := A.Slot + B.Slot;
  Trace := Trace + 'v' + IntToStr(M.Slot);
end;

procedure TwoMixSite;
var
  X, Y: TRes;
begin
  X.Slot := 10;
  Y.Slot := 20;
  Trace := Trace + '|';
  SinkTwoMix(X, Y);
  Trace := Trace + '|';
end;

procedure SinkTwoLocals(V: TRes); inline;
var
  M, N: TRes;
begin
  M.Slot := V.Slot + 1000;
  N.Slot := V.Slot + 2000;
  Trace := Trace + 'v' + IntToStr(M.Slot) + ':' + IntToStr(N.Slot);
end;

procedure TwoLocalsSite;
var
  L: TRes;
begin
  L.Slot := 7;
  Trace := Trace + '|';
  SinkTwoLocals(L);
  Trace := Trace + '|';
end;

begin
  Trace := '';
  TwoMixSite;
  WriteLn('twomix    ', Trace);
  Trace := '';
  TwoLocalsSite;
  WriteLn('twolocals ', Trace);
end.
