{ %OPT=-Mdelphi -O2 -dMOONCOMPILER_UNICODE_DEFAULT }
program tmoonunicodeparamstr1;

var
  UnicodeCalls: Integer;
  AnsiCalls: Integer;
  Expected: UnicodeString;

procedure Accept(const Value: UnicodeString); overload;
begin
  Inc(UnicodeCalls);
end;

procedure Accept(const Value: AnsiString); overload;
begin
  Inc(AnsiCalls);
end;

begin
  Expected := WideChar($041F) + WideChar($0440) + WideChar($0438) +
    WideChar($0432) + WideChar($0435) + WideChar($0442);
  Accept(ParamStr(0));
  if (UnicodeCalls <> 1) or (AnsiCalls <> 0) or
     (ParamStr(1) <> Expected) or (ParamStr(-1) <> '') then
    Halt(1);
end.
