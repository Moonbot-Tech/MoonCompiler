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

  If BitsOf(-0.0) <> $8000000000000000 then
    Halt(1);
  If BitsOf(0.0 * -1.0) <> $8000000000000000 then
    Halt(2);
  If BitsOf(Neg) <> $8000000000000000 then
    Halt(3);
  If BitsOf(Prod) <> $8000000000000000 then
    Halt(4);
  WriteLn('done');
end.
