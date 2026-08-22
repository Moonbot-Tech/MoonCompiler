program array_index_offset_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

type
  TTimings = array[0 .. 6] of UInt64;

procedure Sort(var Values: TTimings);
var
  I, J: Integer;
  Value: UInt64;
begin
  for I := 1 to High(Values) do
  begin
    Value := Values[I];
    J := I - 1;
    while (J >= 0) and (Values[J] > Value) do
    begin
      Values[J + 1] := Values[J];
      Dec(J);
    end;
    Values[J + 1] := Value;
  end;
end;

var
  Values: TTimings = (7, 6, 5, 4, 3, 2, 1);
begin
  Sort(Values);
  if (Values[0] <> 1) or (Values[1] <> 2) or
     (Values[2] <> 3) or (Values[3] <> 4) or
     (Values[4] <> 5) or (Values[5] <> 6) or
     (Values[6] <> 7) then
    Halt(1);
  WriteLn('ARRAY_INDEX_OFFSET_OK');
end.
