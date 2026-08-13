program omni_generated_breadth_oracle;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch INLINEVARS}
  {$modeswitch advancedrecords}
  {$define HAS_ANON}
  {$define HAS_INLINEVAR}
{$else}
  {$APPTYPE CONSOLE}
  {$define HAS_ANON}
  {$define HAS_INLINEVAR}
{$endif}
{$Q-}{$R-}

uses
{$ifdef FPC}
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Variants, Classes, TypInfo, Rtti, Generics.Defaults,
  Generics.Collections;
{$else}
  System.SysUtils, System.Variants, System.Classes, System.TypInfo,
  System.Rtti, System.Generics.Defaults, System.Generics.Collections;
{$endif}

var
  RtZero: UInt64 = 0;

procedure GeneratedCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  WriteLn(string(Name), '=', IntToHex(Actual, 16));
end;

{$I omni_generated_breadth.inc}

begin
  RunGeneratedBreadthCoreForms;
  RunGeneratedBreadthModernForms;
end.
