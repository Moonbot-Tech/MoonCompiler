program Probe;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} Core,A,B;
begin Writeln('COUNT=',Count); Writeln('S=',A.GetS,'/',B.GetS); Writeln('CLASS=',A.GetClass=B.GetClass); end.
