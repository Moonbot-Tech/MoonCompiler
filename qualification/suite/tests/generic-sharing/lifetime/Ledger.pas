unit Ledger;
interface
var Ctors, Dtors, RecordInits, RecordFinals, RefCreates, RefFrees: Integer;
    Trace: UnicodeString;
procedure Mark(const S: UnicodeString);
implementation
procedure Mark(const S: UnicodeString);
begin Trace := Trace + S; end;
initialization
finalization
  Writeln('COUNTS=', Ctors, '/', Dtors, '/', RecordInits, '/', RecordFinals, '/', RefCreates, '/', RefFrees);
  Writeln('TRACE=', Trace);
end.
