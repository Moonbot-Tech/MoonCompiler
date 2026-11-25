{ Statements carry consistent signs, units, and regional separators. }

procedure RunBreadthStatementFormat;
const
  Pattern = '#,##0.00;(#,##0.00);"flat"';
var
  Settings: TFormatSettings;
  Delta: Currency;
  Amount, Debit: string;
begin
  Settings := Default(TFormatSettings);
  Settings.DecimalSeparator := ',';
  Settings.ThousandSeparator := '.';
  Settings.CurrencyString := 'EUR';
  Settings.CurrencyFormat := 3;
  Settings.NegCurrFormat := 0;
  Delta := Currency(OpaqueD(-1234.5));
  Amount := FormatFloat(Pattern, Delta, Settings);
  Check(Amount = '(1.234,50)', 'breadth-statement-format-localizes-debit-without-losing-sign');
  Check(FormatFloat(Pattern, -Delta, Settings) = '1.234,50', 'breadth-statement-format-credits-use-positive-section');
  Check(FormatFloat(Pattern, Delta + 1234.5, Settings) = 'flat', 'breadth-statement-format-zero-uses-literal-section');
  Debit := CurrToStrF(Delta, ffCurrency, 2, Settings);
  Check((Debit = '(EUR1.234,50)') and (CurrToStrF(-Delta, ffCurrency, 2, Settings) = '1.234,50 EUR'),
    'breadth-statement-format-uses-currency-placement-per-sign');
  Mix(UInt64(Length(Amount) * 100 + Length(Debit)));
end;
