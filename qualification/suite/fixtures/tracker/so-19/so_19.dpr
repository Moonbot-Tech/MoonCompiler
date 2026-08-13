program tracker_so_19;

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

type TIntFunc=reference to function:Integer;
function Invoke(const Func:TIntFunc):Integer; inline; begin Result:=Func(); end;

procedure Run;
begin
for var I:=1 to 64 do begin var A:=Invoke(function:Integer begin Result:=11+I; end); var B:=Invoke(function:Integer begin Result:=101+I; end); Check(A=11+I,'first'); Check(B=101+I,'second'); end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-19');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-19: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
