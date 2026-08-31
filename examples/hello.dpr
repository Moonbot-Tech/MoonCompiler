program hello;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Generics.Collections;

begin
  var Prices := TList<Currency>.Create;
  try
    Prices.AddRange([1.55, 2.25, 3.10]);
    var Sum: Currency := 0;
    for var P in Prices do
      Sum := Sum + P;
    Writeln(Format('%d prices, sum = %s', [Prices.Count, CurrToStr(Sum)]));
  finally
    Prices.Free;
  end;
end.
