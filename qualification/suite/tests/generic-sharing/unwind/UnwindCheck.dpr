program UnwindCheck;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils, lnfodwrf, UnwindCore, UnwindA, UnwindB;
var Caught, Symbolized: Integer;
procedure CheckLocation;
var F, S: ShortString; L: LongInt;
begin
  if not GetLineInfo(PtrUInt(ExceptAddr), F, S, L) or (Pos('Checked', F) = 0) or
     (ExtractFileName(string(S)) <> 'UnwindCore.pas') or (L < 18) or (L > 19) then Halt(7);
  Inc(Symbolized);
end;
begin
  Caught := 0;
  Symbolized := 0;
  Writeln('CLASS=', UnwindA.GetClass = UnwindB.GetClass);
  Writeln('LEAF=', (UnwindA.Leaf = 9) and (UnwindB.Leaf = 9));
  Writeln('NORMAL=', UnwindA.Call(1) = UnwindB.Call(1));
  try UnwindA.Call(-1); except on E: Exception do begin Inc(Caught); CheckLocation; end; end;
  try UnwindB.Call(-2); except on E: Exception do begin Inc(Caught); CheckLocation; end; end;
  Writeln('CAUGHT=', Caught);
  Writeln('FINALIZED=', Finalized);
  Writeln('SYMBOLIZED=', Symbolized);
end.
