program cowdbg5;
{$APPTYPE CONSOLE}
uses SysUtils, miniunit;

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
  M: TMiniU<TRes>;
  R: TRes;
begin
  R.Slot := 5;
  M := TMiniU<TRes>.Create;
  try
    Trace := Trace + '|';
    M.Add(R);
    Trace := Trace + '|';
    M.Add(R);
    Trace := Trace + '|' + IntToStr(M.FItems[0].Slot) + ':' + IntToStr(M.FItems[1].Slot) + '|';
  finally
    M.Free;
    Trace := Trace + '$';
  end;
end;

begin
  Trace := '';
  Scenario;
  WriteLn('ppu-mimic ', Trace);
end.
