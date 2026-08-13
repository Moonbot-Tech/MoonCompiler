program omni_generated_oracle;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch INLINEVARS}
  {$define HAS_INLINEVAR}
{$else}
  {$define HAS_INLINEVAR}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  SysUtils;
{$else}
  System.SysUtils;
{$endif}

var
  RtZero: UInt64 = 0;

function OpaqueU(V: UInt64): UInt64;
begin
  Result := V xor RtZero;
end;

function OpaqueI(V: Int64): Int64;
begin
  Result := Int64(UInt64(V) xor RtZero);
end;

procedure GeneratedCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  WriteLn(string(Name), '=', IntToHex(Actual, 16));
end;

{$I omni_generated_forms.inc}

begin
  RunGeneratedForms;
end.
