{ %OPT=-O3 -OoNOAUTOINLINE }
{$mode delphi}
program trecordloop2;

type
  TState = record
    Value: Byte;
    Count: LongInt;
  end;

procedure SetTrue(var Value: Boolean);
begin
  Value := True;
end;

function Run: LongInt;
var
  State: TState;
  I: Integer;
begin
  State.Value := 0;
  State.Count := 0;
  for I := 1 to 10 do
  begin
    SetTrue(Boolean(State.Value));
    Inc(State.Count);
  end;
  Result := State.Value + State.Count;
end;

begin
  If Run <> 11 then
    Halt(1);
end.
