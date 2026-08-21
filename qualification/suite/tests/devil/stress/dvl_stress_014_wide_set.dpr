program dvl_stress_014_wide_set;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
type
  TWide = set of Byte;

var
  A, B, C: TWide;
  I, Seen: Integer;

begin
  A := [];
  B := [];
  for I := 0 to 255 do
    if (I and 1) = 0 then
      Include(A, I)
    else
      Include(B, I);
  C := A + B;
  Seen := 0;
  for I := 0 to 255 do
    if I in C then
      Inc(Seen);
  WriteLn(Seen, ' ', SizeOf(C), ' ', Ord(A * B = []));
end.
