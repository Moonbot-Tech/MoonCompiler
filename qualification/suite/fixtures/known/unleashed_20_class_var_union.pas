program unleashed_20_class_var_union;

{$mode unleashed}

type
  TFoo = record
    class var
      union Raw: DWord; packed record LowByte, MiddleByte, HighByte: Byte; end; end;
  end;

var
  A, B: TFoo;
begin
  if SizeOf(TFoo) <> 0 then Halt(1);
  A.Raw := $00445566;
  if B.LowByte <> $66 then Halt(2);
  if TFoo.MiddleByte <> $55 then Halt(3);
  B.HighByte := $77;
  if A.Raw <> $00775566 then Halt(4);
  WriteLn('PASS unleashed-20');
end.
