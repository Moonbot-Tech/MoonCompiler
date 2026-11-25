{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Append an export line to an existing UTF-16BE log without an extra byte-order mark. }

procedure RunBreadthEncodedLogAppend;
const
  First: UnicodeString = 'A' + #13#10;
  Suffix: UnicodeString = #$0416 + #0 + #$D83D#$DE80 + #10;
  Expected: array[0..17] of Byte = (
    $FE, $FF, 0, $41, 0, $0D, 0, $0A, $04, $16, 0, 0, $D8, $3D, $DE, $80, 0, $0A);
var
  LogName: string;
  Wire: TBytes;
begin
  LogName := TPath.GetTempFileName;
  try
    TFile.WriteAllBytes(LogName, [$FE, $FF, 0, $41, 0, $0D, 0, $0A]);
    TFile.AppendAllText(LogName, Suffix);
    Wire := TFile.ReadAllBytes(LogName);
    Check((Length(Wire) = SizeOf(Expected)) and CompareMem(Pointer(Wire), @Expected[0], SizeOf(Expected)),
      'breadth-encoded-log-append-respects-existing-byte-order-and-single-bom');
    Check(TFile.ReadAllText(LogName) = First + Suffix, 'breadth-encoded-log-readback-keeps-nul-and-utf16-surrogates');
    TFile.AppendAllText(LogName, '');
    Wire := TFile.ReadAllBytes(LogName);
    Check((Length(Wire) = SizeOf(Expected)) and CompareMem(Pointer(Wire), @Expected[0], SizeOf(Expected)),
      'breadth-encoded-log-empty-append-leaves-complete-file-identical');
    Mix(UInt64(Length(Wire)));
  finally
    TFile.Delete(LogName);
  end;
end;
{$endif}
