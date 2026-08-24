{ A class whose field is a static ARRAY of records with management
  operators: the mop-offset init table used to skip such fields, so the
  elements were never Initialize'd at Create while CleanupInstance still
  Finalize'd them through full RTTI.  Measured DCC64:
  |iii|100:100:100|f100f100f100|   (ours before the repair:
  |i|100:0:0|f0f0f100| - born dead, buried honestly). }
program classarr;
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

  { direct record field AND a static-array field of operator records }
  TBox = class
  public
    Direct: TRes;
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

procedure Scenario;
var
  B: TBox;
begin
  Trace := Trace + '|';
  B := TBox.Create;
  Trace := Trace + '|' + IntToStr(B.Direct.Slot) + ':' + IntToStr(B.Arr[0].Slot) + ':' + IntToStr(B.Arr[1].Slot) + '|';
  B.Free;
  Trace := Trace + '|';
end;

begin
  Trace := '';
  Scenario;
  WriteLn('classarr ', Trace);
end.
