program tracker_mb_04;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch inlinevars}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

var RuntimeBoundZero: UInt64 = 0;
function OpaqueBound(Value: Int64): Int64;
begin
  Result := Int64(UInt64(Value) xor RuntimeBoundZero);
end;
procedure CheckAscending;
var K, LowBound, HighBound, Count, Sum: Integer;
begin
  LowBound := 0;
  HighBound := 0;
  Count := 0;
  Sum := 0;
  for K := Integer(OpaqueBound(Int64(LowBound))) to
      Integer(OpaqueBound(Int64(HighBound))) do
  begin
    Inc(Count);
    Inc(Sum, K);
  end;
  Check((Count = 1) and (Sum = 0),
    'ascending-' + IntToStr(Count) + '-' + IntToStr(Sum));
end;
procedure CheckDescending;
var K, LowBound, HighBound, Count, Sum: Integer;
begin
  LowBound := 0;
  HighBound := 0;
  Count := 0;
  Sum := 0;
  for K := Integer(OpaqueBound(Int64(LowBound))) downto
      Integer(OpaqueBound(Int64(HighBound))) do
  begin
    Inc(Count);
    Inc(Sum, K);
  end;
  Check((Count = 1) and (Sum = 0),
    'descending-' + IntToStr(Count) + '-' + IntToStr(Sum));
end;

procedure Run;
begin
CheckAscending;
  CheckDescending;
end;

begin
  try
    Run;
    WriteLn('PASS MB-04');
  except
    on E: Exception do
    begin
      WriteLn('FAIL MB-04: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
