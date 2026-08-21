program negzero;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, Math;

type
  TDoubleBits = record
    case Boolean of
      False: (Value: Double);
      True: (Bits: UInt64);
  end;

function BitsOf(Value: Double): UInt64;
var
  Box: TDoubleBits;
begin
  Box.Value := Value;
  Result := Box.Bits;
end;

var
  Zero, Neg, Prod: Double;
begin
  WriteLn('bits of  0.0 literal      = ', IntToHex(BitsOf(0.0), 16));
  WriteLn('bits of -0.0 literal      = ', IntToHex(BitsOf(-0.0), 16));

  Zero := 0.0;
  Neg := -Zero;
  WriteLn('bits of -(variable 0.0)   = ', IntToHex(BitsOf(Neg), 16));

  Prod := 0.0 * -1.0;
  WriteLn('bits of 0.0 * -1.0        = ', IntToHex(BitsOf(Prod), 16));

  Zero := 0.0;
  Prod := Zero * -1.0;
  WriteLn('bits of var0 * -1.0       = ', IntToHex(BitsOf(Prod), 16));

  WriteLn('  -0.0 = 0.0              = ', -0.0 = 0.0);

  { Последствие: у деления на ноль знак берётся от знака нуля. }
  Prod := 0.0 * -1.0;
  WriteLn('  1/(const -0.0) bits     = ', IntToHex(BitsOf(1.0 / Prod), 16));
  Zero := 0.0;
  Prod := Zero * -1.0;
  WriteLn('  1/(runtime -0.0) bits   = ', IntToHex(BitsOf(1.0 / Prod), 16));
  WriteLn('  (+inf bits = 7FF0000000000000, -inf = FFF0000000000000)');
  WriteLn('done');
end.
