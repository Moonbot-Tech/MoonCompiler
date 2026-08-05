{ %OPT=-O3 }
{ %RECOMPILE }
program tautoinline5;

uses
  lab_002_unicode_const_pointer_unit;

var
  Collection: TUnicodeCollection;
begin
  Collection.AtInsert(UnicodeString('value'));
end.
