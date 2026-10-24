program DwarfIntegerForms;
{$mode objfpc}{$H+}
uses lnfodwrf, SysUtils;
const
  MaximumUnsigned = QWord($FFFFFFFFFFFFFFFF);
  MinimumSigned = Low(Int64);
procedure Marker; noinline;
begin
  Writeln(MaximumUnsigned, MinimumSigned);
end;
var F,S: ShortString; L: LongInt;
begin
  if not GetLineInfo(PtrUInt(@Marker)+1,F,S,L) then Halt(3);
  if (Pos('Marker',F)=0) or (Pos('dwarf_integer_forms.pas',S)=0) then Halt(4);
  Writeln('INTEGER_FORMS=',F,'|',S,'|',L);
end.
