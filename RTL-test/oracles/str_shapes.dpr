program str_shapes;
{$mode delphi}{$H+}
uses SysUtils;
const Values: array[0..16] of Double=(0.0,-0.0,0.000001,0.00001,0.0001,
  0.001,0.1,1.0,1.25,12.5,123456.125,1e14,1e15,1e16,1e-10,1e100,-1.25);
var I: Integer; S: ShortString; F: TFormatSettings;
begin
  F:=TFormatSettings.Create('en-US'); F.DecimalSeparator:='.';
  for I:=Low(Values) to High(Values) do begin
    Str(Values[I]:22,S);
    WriteLn(I,#9,'[',S,']',#9,FloatToStr(Values[I],F));
  end;
end.
