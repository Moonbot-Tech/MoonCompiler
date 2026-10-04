program format_runtime_semantic;
{$mode delphiunicode}
{$H+}
uses SysUtils;
var
  Settings: TFormatSettings;
  Checks: Integer;
  RuntimeFmt: UnicodeString;

procedure Check(const Name, Actual, Expected: UnicodeString);
begin
  Inc(Checks);
  if Actual <> Expected then
    raise Exception.Create('Format mismatch: ' + Name);
end;

procedure Bad(const Fmt: UnicodeString; const Args: array of const);
var S: UnicodeString;
begin
  try
    S := Format(Fmt, Args, Settings);
  except
    on E: EConvertError do begin
      Inc(Checks);
      Exit;
    end;
  end;
  raise Exception.Create('Expected Format error: ' + Fmt);
end;

var
  I: Integer;
  Wide: WideString;
  Ansi: AnsiString;
  Source, Other, Value: UnicodeString;
  S64: Int64;
  U64: QWord;
  Buffer: array[0..15] of UnicodeChar;
  Count: Cardinal;
begin
  Settings := TFormatSettings.Invariant;
  for I := -1234 to 1234 do begin
    RuntimeFmt := '%d';
    Check('runtime decimal', Format(RuntimeFmt, [I], Settings), IntToStr(I));
    Check('prefix decimal', Format('id=%d', [I], Settings), 'id=' + IntToStr(I));
  end;
  S64 := Low(Int64);
  U64 := High(QWord);
  Check('min int64', Format('%d', [S64], Settings), '-9223372036854775808');
  Check('max unsigned', Format('%u', [U64], Settings), '18446744073709551615');
  Check('signed qword', Format('%d', [U64], Settings), '-1');
  Check('width', Format('%10.5d', [42], Settings), '     00042');
  Check('left', Format('%-10d', [42], Settings), '42        ');
  Check('star', Format('%*.*d', [8, 4, 42], Settings), '    0042');
  Check('index', Format('%1:d/%0:s/%1:d', ['item', 42], Settings), '42/item/42');
  Check('float', Format('price=%.2f', [12.5], Settings), 'price=12.50');
  Settings.DecimalSeparator := ',';
  Check('settings', Format('price=%.2f', [12.5], Settings), 'price=12,50');
  Check('escape', Format('%%:%d:%%', [42], Settings), '%:42:%');
  Check('escape only', Format('%%', [], Settings), '%');
  Check('empty', Format('', [], Settings), '');
  Check('literal', Format('runtime plain message', [], Settings), 'runtime plain message');
  Check('literal extra args', Format('runtime plain message', [42], Settings), 'runtime plain message');
  Check('embedded nul', Format('a'#0'b=%d', [42], Settings), 'a'#0'b=42');
  Source := 'a'#0'b'#$D83D#$DE00#$D800;
  Check('unicode', Format('%s', [Source], Settings), Source);
  Check('general unicode', Format('<%s>', [Source], Settings), '<' + Source + '>');
  Value := Format('%s', [Source], Settings);
  Other := Value;
  Value[1] := 'q';
  Check('cow', Other, Source);
  Wide := 'BSTR';
  Check('wide argument', Format('%s', [Wide], Settings), 'BSTR');
  Ansi := 'ascii';
  Check('ansi argument', Format('%s', [Ansi], Settings), 'ascii');
  Check('default settings overload', Format('%d/%s', [42, Source]), '42/' + Source);
  Check('UnicodeFormat direct', UnicodeFormat('%10.5d', [42], Settings), '     00042');
  Check('WideFormat', UnicodeString(WideFormat(WideString('%s:%10.5d'), [Wide, 42], Settings)), 'BSTR:     00042');
  Check('Wide literal', UnicodeString(WideFormat(WideString('BSTR'#0'tail'), [], Settings)), 'BSTR'#0'tail');
  Check('Ansi Format', UnicodeString(Format(AnsiString('%s:%10.5d'), [Ansi, 42], Settings)), 'ascii:     00042');
  Check('Ansi literal', UnicodeString(Format(AnsiString('ascii'#0'tail'), [], Settings)), 'ascii'#0'tail');
  Value := 'old';
  UnicodeFmtStr(Value, '%d/%s', [42, Source], Settings);
  Check('UnicodeFmtStr', Value, '42/' + Source);
  FillChar(Buffer, SizeOf(Buffer), $55);
  RuntimeFmt := 'ab%d%%';
  Count := UnicodeFormatBuf(Buffer, 4, RuntimeFmt[1], Length(RuntimeFmt), [42], Settings);
  if (Count <> 4) or (Buffer[4] <> #$5555) then raise Exception.Create('FormatBuf bounds');
  SetString(Value, PWideChar(@Buffer[0]), Count);
  Check('UnicodeFormatBuf', Value, 'ab42');
  Bad('%d', []);
  Bad('%d', [Source]);
  Check('unknown format', Format('%q', [42], Settings), '');
  Bad('%2:d', [42]);
  If Checks<>4970 then raise Exception.Create('Format oracle coverage differs');
  WriteLn('FORMAT_RUNTIME_SEMANTIC_OK');
end.
