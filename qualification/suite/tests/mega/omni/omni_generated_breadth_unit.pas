unit omni_generated_breadth_unit;

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

procedure InstallGeneratedBreadthCheck(Check: TGeneratedCheckU);
procedure RunGeneratedBreadthCoreForms;
procedure RunGeneratedBreadthModernForms;

implementation

uses
  SysUtils, Variants, Classes, TypInfo, Rtti, Generics.Defaults,
  Generics.Collections;

var
  CheckU: TGeneratedCheckU;
  RtZero: UInt64 = 0;

procedure GeneratedCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  if not Assigned(CheckU) then
    raise Exception.Create('generated breadth check is not installed');
  CheckU(Name, Actual, Expected);
end;

procedure InstallGeneratedBreadthCheck(Check: TGeneratedCheckU);
begin
  CheckU := Check;
end;

{$I omni_generated_breadth.inc}

end.
