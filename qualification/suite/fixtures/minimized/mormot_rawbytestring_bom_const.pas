program mormot_rawbytestring_bom_const;

{$ifdef FPC}
  {$mode delphiunicode}
  {$codepage utf8}
{$endif}
{$h+}

const
  BOM_UTF8_CHARS: RawByteString =
    AnsiChar($ef) + AnsiChar($bb) + AnsiChar($bf);

begin
  if (Length(BOM_UTF8_CHARS) <> 3) or
     (Byte(BOM_UTF8_CHARS[1]) <> $ef) or
     (Byte(BOM_UTF8_CHARS[2]) <> $bb) or
     (Byte(BOM_UTF8_CHARS[3]) <> $bf) then
    Halt(1);
  WriteLn('PASS mormot-rawbytestring-bom-const');
end.
