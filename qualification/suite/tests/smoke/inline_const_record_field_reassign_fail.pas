program inline_const_record_field_reassign_fail;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

type
  TValue = record
    Number: Integer;
  end;

function MakeValue: TValue;
begin
  Result.Number:=1;
end;

begin
  const Value: TValue=MakeValue;
  Value.Number:=2;
end.
