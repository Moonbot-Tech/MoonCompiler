{ A record whose ONLY operator carrier is a static-array field: the
  Delphi-assign property must be inherited through the array wrapping
  (DCC64):
  locals iiiiaa|11:21:7|f11f21f10f20
  param  ii|iiaav31f31f41|f30f40 }
program arrfield;
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

  { record whose ONLY operator carrier is a static-array field }
  THolder = record
    Arr: array[0..1] of TRes;
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

procedure Locals;
var
  A, B: THolder;
begin
  A.Arr[0].Slot := 10;
  A.Arr[1].Slot := 20;
  A.Plain := 7;
  B := A;
  Trace := Trace + '|' + IntToStr(B.Arr[0].Slot) + ':' + IntToStr(B.Arr[1].Slot) + ':' + IntToStr(B.Plain) + '|';
end;

procedure Sink(V: THolder);
begin
  Trace := Trace + 'v' + IntToStr(V.Arr[0].Slot);
end;

procedure Param;
var
  H: THolder;
begin
  H.Arr[0].Slot := 30;
  H.Arr[1].Slot := 40;
  H.Plain := 9;
  Trace := Trace + '|';
  Sink(H);
  Trace := Trace + '|';
end;

begin
  Trace := '';
  Locals;
  WriteLn('locals ', Trace);
  Trace := '';
  Param;
  WriteLn('param  ', Trace);
end.
