program dictionary_string_lookup_unicode_semantic;

{$mode delphiunicode}
{$codepage utf8}

uses {$ifdef UNIX}cthreads, cwstring,{$endif} SysUtils, Generics.Defaults, Generics.Collections;

type TKey = UnicodeString;

{$i support/dictionary_string_lookup.inc}

begin
  RunStringDictionaryChecks;
  WriteLn('DICTIONARY_STRING_LOOKUP_UNICODE_OK');
end.
