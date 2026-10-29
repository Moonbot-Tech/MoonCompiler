program dictionary_string_lookup_utf8_semantic;

{$mode delphiunicode}
{$codepage utf8}

uses {$ifdef UNIX}cthreads, cwstring,{$endif} SysUtils, Generics.Defaults, Generics.Collections;

type TKey = UTF8String;

{$i support/dictionary_string_lookup.inc}

begin
  RunStringDictionaryChecks;
  WriteLn('DICTIONARY_STRING_LOOKUP_UTF8_OK');
end.
