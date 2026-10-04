{ %OPT=-O3 }
program tforunrollnestedfinally1;

{$mode delphi}

var
  Total: Integer;

procedure Sink(const Value: Integer); noinline;
begin
  Inc(Total,Value);
end;

procedure Probe;
var
  Index: Integer;
begin
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
  try Sink(0); finally
    for Index:=1 to 3 do
      Sink(Index);
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
  end;
end;

begin
  Total:=0;
  Probe;
  if Total<>6 then
    Halt(1);
end.
