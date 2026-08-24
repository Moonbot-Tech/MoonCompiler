{ Two residual canvas axes (values and balance agree byte for byte):
  - SinkMix carries a custom-Initialize LOCAL, so the psub gate keeps it
    a real call ("custom managed local initialization"); lifting that
    gate has a ready recipe - the same raw-byte-temp pattern the
    parameter copies use (see PENDING).
  - In the flat callee, DCC64 finalizes locals before parameter copies
    (inlmix: i|iiav56f56f6|f5), we finalize parameters first
    (i|iaiv56f6f56|f5); DCC also phases frame Initialize before Assign. }
program inlrec3;
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

procedure SinkMix(V: TRes); inline;
var
  M: TRes;
begin
  M.Slot := V.Slot + 50;
  Trace := Trace + 'v' + IntToStr(M.Slot);
end;

procedure MixSite;
var
  L: TRes;
begin
  L.Slot := 5;
  Trace := Trace + '|';
  SinkMix(L);
  Trace := Trace + '|';
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
  Trace := '';
  MixSite;
  WriteLn('inlmix    ', Trace);
end.
