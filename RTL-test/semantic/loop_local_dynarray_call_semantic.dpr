program loop_local_dynarray_call_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

var
  NoiseState: Integer;

function Noise(Value: Integer): Integer; noinline;
begin
  NoiseState:=NoiseState xor Value;
  Result:=Value and 1;
end;

function SumLocal(Count: Integer): Int64; noinline;
var
  Data: array of Integer;
  I: Integer;
begin
  SetLength(Data,Count);
  for I:=0 to Count-1 do
    Data[I]:=I*3+1;
  Result:=0;
  for I:=0 to Count-1 do
    Result:=Result+Data[I]+Noise(I);
end;

begin
  NoiseState:=0;
  If SumLocal(1000)<>1500000 then
    Halt(1);
  WriteLn('LOOP_LOCAL_DYNARRAY_CALL_OK');
end.
