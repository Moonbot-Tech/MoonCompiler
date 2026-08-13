program tracker_so_16;

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

type
  TShort255=string[255];
  TGenericEcho<T> = class class function Echo(const Value:T):T; static; inline; end;
class function TGenericEcho<T>.Echo(const Value:T):T; begin Result:=Value; end;

procedure Run;
begin
var A:TShort255:='abc'; var B:=TGenericEcho<TShort255>.Echo(A); Check(B=A,'short-echo');
  A:=StringOfChar('x',255); B:=TGenericEcho<TShort255>.Echo(A); Check(B=A,'short-max');
end;

begin
  try
    Run;
    WriteLn('PASS SO-16');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-16: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
