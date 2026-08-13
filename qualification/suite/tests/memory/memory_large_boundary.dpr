program memory_large_boundary;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm;

const
  BoundarySizes: array[0..13] of PtrUInt = (
    264744, 264745,
    327640, 327641, 327642,
    655320, 655321, 655322,
    4194264, 4194265, 4194266,
    6291416, 6291417, 6291418);

function CheckAllocation(Requested: PtrUInt): Boolean;
var
  P: Pointer;
  Actual: PtrUInt;
begin
  Result := False;
  P := GetMem(Requested);
  if P = nil then
  begin
    WriteLn('MEMORY_LARGE_BOUNDARY_FAIL allocation-nil requested=', Requested);
    Exit;
  end;
  try
    Actual := MemSize(P);
    if Actual < Requested then
    begin
      WriteLn('MEMORY_LARGE_BOUNDARY_FAIL allocation requested=', Requested,
        ' actual=', Actual);
      Exit;
    end;
    PByte(P)^ := $5A;
    PByte(P)[Requested - 1] := $A5;
    Result := (PByte(P)^ = $5A) and (PByte(P)[Requested - 1] = $A5);
    if not Result then
      WriteLn('MEMORY_LARGE_BOUNDARY_FAIL content requested=', Requested);
  finally
    FreeMem(P);
  end;
end;

var
  I: Integer;
  Passed: Boolean;

begin
  Passed := True;
  for I := Low(BoundarySizes) to High(BoundarySizes) do
    if not CheckAllocation(BoundarySizes[I]) then
      Passed := False;
  if not Passed then
    Halt(10);
  WriteLn('MEMORY_LARGE_BOUNDARY_PASS cases=', Length(BoundarySizes));
end.
