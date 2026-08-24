program inlrec;
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

procedure SinkInline(V: TRes); inline;
begin
  V.Slot := V.Slot + 500;
  Trace := Trace + 'v' + IntToStr(V.Slot);
end;

procedure CallSite;
var
  L: TRes;
begin
  L.Slot := 5;
  Trace := Trace + '|';
  SinkInline(L);
  Trace := Trace + '|' + IntToStr(L.Slot) + '|';
end;

function MakeInline(X: Integer): TRes; inline;
begin
  Result.Slot := X;
end;

procedure ResultSite;
var
  L: TRes;
begin
  L.Slot := 3;
  L := MakeInline(9);
  Trace := Trace + '|' + IntToStr(L.Slot) + '|';
end;

begin
  Trace := '';
  CallSite;
  WriteLn('inlparam  ', Trace);
  Trace := '';
  ResultSite;
  WriteLn('inlresult ', Trace);
end.
