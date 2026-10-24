program Life;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} Ledger, StateA, StateB;
begin
  Mark('M');
  Writeln('SHARED=', StateA.GetClass = StateB.GetClass);
  Writeln('TEXT_A=', StateA.GetText);
  Writeln('TEXT_B=', StateB.GetText);
end.
