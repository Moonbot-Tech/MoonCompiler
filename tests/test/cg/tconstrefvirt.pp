{ %OPT=-O3 }
{$mode delphi}
program tconstrefvirt;
type
  PLongInt = ^LongInt;
  TInfo = record
    A: LongInt;
    C: LongInt;
  end;
  TBase = class
    procedure Observe(constref X: LongInt); virtual;
  end;
  TSaver = class(TBase)
    Saved: PLongInt;
    Hits: LongInt;
    procedure Observe(constref X: LongInt); override;
  end;
procedure TBase.Observe(constref X: LongInt);
begin
end;
procedure TSaver.Observe(constref X: LongInt);
begin
  Saved := @X;
  Inc(Hits);
  If Hits = 5 then
    Saved^ := 1000;
end;
function Run(Obj: TBase; N: Integer): LongInt;
var
  Info: TInfo;
  I: Integer;
begin
  Info.A := 0;
  Info.C := 0;
  for I := 1 to N do
  begin
    Inc(Info.C);
    Obj.Observe(Info.C);
    Inc(Info.A);
  end;
  Result := Info.C;
end;
var
  Obj: TBase;
begin
  Obj := TSaver.Create;
  if Run(Obj, 10) <> 1005 then
  begin
    WriteLn('FAIL kept address lost');
    Halt(1);
  end;
  Obj.Free;
end.
