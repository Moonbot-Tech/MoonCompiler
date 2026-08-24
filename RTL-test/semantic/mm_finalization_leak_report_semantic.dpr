program mm_finalization_leak_report_semantic;

{ A leak gate is useful only if it proves that the final MM census actually
  ran.  This program deliberately loses one small allocation.  The runner
  requires both the exact leak line and the completed-report marker. }

{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm
  {$ifdef UNIX}
  , cthreads
  {$endif UNIX};

var
  P: Pointer;

begin
  GetMem(P, 41);
  PByte(P)^ := 1;
  P := nil;
  WriteLn('MM_FINALIZATION_LEAK_REPORT_OK');
end.
