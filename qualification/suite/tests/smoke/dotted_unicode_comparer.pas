program dotted_unicode_comparer;

{$mode delphiunicode}

uses
{$ifdef UNIX}
  CWString,
{$endif}
  System.Generics.Defaults;

var
  Comparer: IComparer<UnicodeString>;

begin
  Comparer := TStringComparer.Ordinal;
  If Comparer.Compare(UnicodeString('a') + WideChar($03BB),
    UnicodeString('a') + WideChar($03BB)) <> 0 then
    Halt(1);
  WriteLn('DOTTED_UNICODE_COMPARER_OK');
end.
