program Fpc41451StaticManagedRecordInit;

{$mode objfpc}
{$modeswitch advancedrecords}

var
  InitializeCount: LongInt;

type
  TFoo = record
    State: Word;
    procedure SetState(Value: Word);
    class operator Initialize(var Value: TFoo);
    class operator Finalize(var Value: TFoo);
  end;

class operator TFoo.Initialize(var Value: TFoo);
begin
  Inc(InitializeCount);
  Value.State := 0;
end;

class operator TFoo.Finalize(var Value: TFoo);
begin
end;

procedure TFoo.SetState(Value: Word);
begin
  State := Value;
end;

var
  One: TFoo;
  Many: array[0..5] of TFoo;
  I: Integer;
begin
  One.SetState(7);
  for I := Low(Many) to High(Many) do
    Many[I].SetState(I);
  if InitializeCount <> 7 then
    Halt(1);
end.
