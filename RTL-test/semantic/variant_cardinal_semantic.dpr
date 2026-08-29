program variant_cardinal_semantic;

{ dvl-0061: Delphi converts Variant and OleVariant to Cardinal through the
  unsigned varLongWord domain.  Going through VarToInt first incorrectly
  raises above High(Integer).  With overflow/range checks disabled Delphi
  rounds floating values and applies the ordinary Cardinal modulo conversion
  to wider signed/unsigned values. }

{$APPTYPE CONSOLE}

{$ifdef FPC}
{$mode delphi}{$H+}
{$endif FPC}

{$Q-}{$R-}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils, Variants;

procedure CheckVariant(const Name: string; const V: Variant;
  Expected: Cardinal);
var
  Actual: Cardinal;
begin
  try
    Actual := V;
  except
    on E: Exception do
      raise Exception.CreateFmt('%s raised %s: %s',
        [Name, E.ClassName, E.Message]);
  end;
  If Actual <> Expected then
    raise Exception.CreateFmt('%s: %u expected %u',
      [Name, UInt64(Actual), UInt64(Expected)]);
end;

procedure CheckOleVariant(const Name: string; const V: OleVariant;
  Expected: Cardinal);
var
  Actual: Cardinal;
begin
  try
    Actual := V;
  except
    on E: Exception do
      raise Exception.CreateFmt('%s raised %s: %s',
        [Name, E.ClassName, E.Message]);
  end;
  If Actual <> Expected then
    raise Exception.CreateFmt('%s: %u expected %u',
      [Name, UInt64(Actual), UInt64(Expected)]);
end;

procedure CheckVariantMatrix;
var
  V: Variant;
begin
  V := Cardinal(0);             CheckVariant('v dword 0', V, 0);
  V := Cardinal($7fffffff);     CheckVariant('v signed max', V, $7fffffff);
  V := Cardinal($80000000);     CheckVariant('v signed edge', V, $80000000);
  V := Cardinal($fffffff0);     CheckVariant('v high', V, $fffffff0);
  V := Cardinal($ffffffff);     CheckVariant('v max', V, $ffffffff);
  V := Integer(-1);             CheckVariant('v integer -1', V, $ffffffff);
  V := Int64(-1);               CheckVariant('v int64 -1', V, $ffffffff);
  V := Int64($80000000);        CheckVariant('v int64 edge', V, $80000000);
  V := Int64($ffffffff);        CheckVariant('v int64 max', V, $ffffffff);
  V := Int64($100000000);       CheckVariant('v int64 modulo', V, 0);
  V := UInt64($ffffffff);       CheckVariant('v qword max', V, $ffffffff);
  V := UInt64($100000000);      CheckVariant('v qword modulo', V, 0);
  V := Double(4294967295.0);    CheckVariant('v double max', V, $ffffffff);
  V := Double(4294967296.0);    CheckVariant('v double modulo', V, 0);
  V := Double(-1.0);            CheckVariant('v double -1', V, $ffffffff);
  V := Double(1.5);             CheckVariant('v double round', V, 2);
  V := '4294967295';            CheckVariant('v string max', V, $ffffffff);
  V := '4294967296';            CheckVariant('v string modulo', V, 0);
  V := '-1';                    CheckVariant('v string -1', V, $ffffffff);
  V := '-2147483649';           CheckVariant('v string below int32', V, $7fffffff);
  V := '18446744073709551615';  CheckVariant('v string qword max', V, 0);
  V := '1.5';                   CheckVariant('v string round', V, 2);
  V := '-1.5';                  CheckVariant('v string negative round', V, $fffffffe);
end;

procedure CheckOleVariantMatrix;
var
  V: OleVariant;
begin
  V := Cardinal($80000000);     CheckOleVariant('ole signed edge', V, $80000000);
  V := Cardinal($ffffffff);     CheckOleVariant('ole max', V, $ffffffff);
  V := Int64(-1);               CheckOleVariant('ole int64 -1', V, $ffffffff);
  V := Int64($100000000);       CheckOleVariant('ole int64 modulo', V, 0);
  V := Double(4294967295.0);    CheckOleVariant('ole double max', V, $ffffffff);
  V := Double(1.5);             CheckOleVariant('ole double round', V, 2);
  V := '4294967295';            CheckOleVariant('ole string max', V, $ffffffff);
end;

begin
  try
    CheckVariantMatrix;
    CheckOleVariantMatrix;
    WriteLn('VARIANT_CARDINAL_OK');
  except
    on E: Exception do begin
      WriteLn('VARIANT_CARDINAL_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
