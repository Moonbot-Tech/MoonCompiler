{ %OPT=-O3 }
program tmoonwithcapturemapping1;
{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}
type
  TPair = record
    A, B: Integer;
  end;
  TProc = reference to procedure;
var
  First, Second: TProc;
  SeenA, SeenB: Integer;

function MakePair: TPair;
begin
  Result.A := 17;
  Result.B := 29;
end;

procedure Capture;
begin
  with MakePair do
    begin
      First := procedure begin SeenA := A; end;
      Second := procedure begin SeenB := B; end;
    end;
end;

begin
  Capture;
  First();
  Second();
  if (SeenA <> 17) or (SeenB <> 29) then Halt(1);
  First := nil;
  Second := nil;
  Writeln('ok');
end.
