{ %CPU=i386,x86_64 }
{ %OPT=-O3 }

program tpeepholethreadvar1;

{$mode delphi}

uses
  upeepholethreadvar2;

procedure Check(const Name: ShortString; Actual, Expected: Int64);
begin
  if Actual <> Expected then
    begin
      WriteLn(Name, ': expected ', Expected, ', got ', Actual);
      Halt(1);
    end;
end;

var
  A, B, C: Int64;
begin
  { The threadvar address is calculated at run time.  Three inlined updates
    must preserve all returned values rather than re-read the final value. }
  A := StepThreadValue(5);
  B := StepThreadValue(7);
  C := StepThreadValue(9);
  Check('threadvar', A + B + C, 38);

  WriteLn('PEEPHOLE-THREADVAR:PASS');
end.
