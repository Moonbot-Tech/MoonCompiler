program tracker_qp_48;

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



procedure Run;
begin
var Dictionary := TDictionary<string,TObject>.Create;
  try
    var A := TObject.Create; var B := TObject.Create;
    Dictionary.Add('a', A); Dictionary.Add('b', B);
    var Seen := 0;
    for var Pair in Dictionary do
    begin Check(((Pair.Key = 'a') and (Pair.Value = A)) or ((Pair.Key = 'b') and (Pair.Value = B)), 'pair'); Inc(Seen); end;
    Check(Seen = 2, 'count');
    A.Free; B.Free;
  finally Dictionary.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-48');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-48: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
