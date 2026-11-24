{ Native unsigned parsing returns a full-width value and updates a packed end-pointer cell. }

{$ifdef MSWINDOWS}
function BreadthCUnsigned(Text: PAnsiChar; out EndAt: PAnsiChar; Radix: Integer): UInt64;
  cdecl; external 'msvcrt.dll' name '_strtoui64';
{$else}
function BreadthCUnsigned(Text: PAnsiChar; out EndAt: PAnsiChar; Radix: Integer): UInt64;
  cdecl; external 'c' name 'strtoull';
{$endif}

procedure RunBreadthUnsignedCParse;
var
  Text: AnsiString;
  Frame: packed record
    Before: Byte;
    EndAt: PAnsiChar;
    After: Word;
  end;
  Value: UInt64;
begin
  Frame.Before := $83;
  Frame.After := $58AD;
  Frame.EndAt := nil;
  Text := '  +0xFEDCBA9876543210!tail';
  Value := BreadthCUnsigned(PAnsiChar(Text), Frame.EndAt, 0);
  Check(Value = UInt64($FEDCBA9876543210), 'breadth-c-unsigned-autobase-preserves-all-return-bits');
  Check(Frame.EndAt = PAnsiChar(Text) + 21, 'breadth-c-unsigned-returns-pointer-to-first-unparsed-character');

  Text := 'z-unparsed';
  Value := BreadthCUnsigned(PAnsiChar(Text), Frame.EndAt, 16);
  Check((Value = 0) and (Frame.EndAt = PAnsiChar(Text)), 'breadth-c-unsigned-no-digits-preserves-start-as-end-pointer');
  Check((Frame.Before = $83) and (Frame.After = $58AD), 'breadth-c-unsigned-packed-end-pointer-keeps-neighboring-fields');
end;
