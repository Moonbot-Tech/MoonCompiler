program fpc_41126_unsigned_empty_loop;

{$mode delphi}

type
  TRec = record
    EntryCount: SizeUInt;
  end;
  PRec = ^TRec;

function TestLoopUnsigned(Rec: PRec): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Rec^.EntryCount - 1 do
  begin
    Inc(Result);
    { Bound a miscompiled underflow loop so this regression test can never
      become a stress workload. }
    if Result > 4 then
      Exit;
  end;
end;

var
  Rec: TRec;
  N: SizeInt;
begin
  Rec.EntryCount := 0;
  N := TestLoopUnsigned(@Rec);
  if N <> 0 then
  begin
    WriteLn('FAIL fpc-41126 iterations=', N);
    Halt(1);
  end;
  WriteLn('PASS fpc-41126');
end.
