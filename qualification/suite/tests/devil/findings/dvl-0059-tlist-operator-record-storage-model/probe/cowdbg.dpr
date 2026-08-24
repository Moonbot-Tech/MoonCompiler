program cowdbg;
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

type
  PDynHdr = ^TDynHdr;
  TDynHdr = record
    RefCount: NativeInt;
    High: NativeInt;
  end;

function RC(const A: TArray<TRes>): NativeInt;
begin
  If Pointer(A) = nil then
    Result := -99
  else
    Result := (PDynHdr(PByte(Pointer(A)) - SizeOf(TDynHdr)))^.RefCount;
end;

{ mimic of the TList internals: FItems + grow + indexed write }
var
  FItems: TArray<TRes>;
  FLength: NativeInt;

procedure MimicAdd(const AValue: TRes);
begin
  If FLength > System.High(FItems) then
    SetLength(FItems, 4);
  FItems[FLength] := AValue;
  Inc(FLength);
end;

procedure Scenario;
var
  R: TRes;
begin
  R.Slot := 5;
  Trace := Trace + '|';
  MimicAdd(R);
  Trace := Trace + '(rc=' + IntToStr(RC(FItems)) + ')';
  Trace := Trace + '|';
  MimicAdd(R);
  Trace := Trace + '(rc=' + IntToStr(RC(FItems)) + ')';
  Trace := Trace + '|' + IntToStr(FItems[0].Slot) + ':' + IntToStr(FItems[1].Slot) + '|';
  FItems := nil;
  Trace := Trace + '|';
end;

begin
  Trace := '';
  Scenario;
  WriteLn('mimic ', Trace);
end.
