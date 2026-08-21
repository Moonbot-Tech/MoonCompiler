program dvl_stress_012_huge_offsets;
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
  TWide = record
    Head: Int64;
    Filler: array[0..262143] of Byte;
    Tail: Int64;
    Deep: array[0..32767] of Int64;
    Last: Int64;
  end;

var
  R: TWide;
  Sum: Int64;

begin
  FillChar(R, SizeOf(R), 0);
  R.Head := 1;
  R.Tail := 2;
  R.Last := 3;
  R.Deep[High(R.Deep)] := 4;
  Sum := R.Head + R.Tail + R.Last + R.Deep[High(R.Deep)];
  WriteLn(Sum, ' ', SizeOf(R));
end.
