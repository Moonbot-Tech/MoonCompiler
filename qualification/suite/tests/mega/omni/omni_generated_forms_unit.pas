unit omni_generated_forms_unit;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$define HAS_ANON}
  {$ifdef HAS_INLINEVAR}
    {$modeswitch inlinevars}
  {$endif}
{$else}
  {$define HAS_ANON}
  {$define HAS_INLINEVAR}
{$endif}
{$Q-}{$R-}

interface

type
  TGeneratedCheckU = procedure(const Name: AnsiString;
    Actual, Expected: UInt64);

procedure InstallGeneratedFormsCheck(Check: TGeneratedCheckU);
procedure RunGeneratedForms;

implementation

uses
  SysUtils;

var
  CheckU: TGeneratedCheckU;
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
  if not Assigned(CheckU) then
    raise Exception.Create('generated forms check is not installed');
  CheckU(Name, Actual, Expected);
end;

procedure InstallGeneratedFormsCheck(Check: TGeneratedCheckU);
begin
  CheckU := Check;
end;

{$I omni_generated_forms.inc}

end.
