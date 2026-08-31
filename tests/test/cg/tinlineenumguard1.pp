{ %OPT=-O3 }
program tinlineenumguard1;

{$mode delphi}

type
  TAction = (a0, a1, a2, a3, a4, a5, a6, a7,
    a8, a9, a10, a11, a12, a13, a14, a15,
    a16, a17, a18, a19, a20, a21, a22, a23,
    a24, a25, a26, a27);
  TActionMap = array[a22..a27] of TAction;

const
  ActionMap: TActionMap = (a5, a4, a3, a2, a1, a0);

function Remap(AValue: TAction): TAction; inline;
begin
  If AValue in [Low(ActionMap)..High(ActionMap)] then
    AValue := ActionMap[AValue];
  Result := AValue;
end;

begin
  If Remap(a0) <> a0 then
    Halt(1);
  If Remap(a22) <> a5 then
    Halt(2);
  If Remap(a27) <> a0 then
    Halt(3);
end.
