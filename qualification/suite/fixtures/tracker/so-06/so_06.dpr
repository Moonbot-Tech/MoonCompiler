program tracker_so_06;

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
  TManaged = record
    Value: string;
    class var InitCount, FinalCount: Integer;
    {$ifdef FPC}class operator Initialize(var Dest: TManaged); class operator Copy(constref Src: TManaged; var Dest: TManaged);
    {$else}class operator Initialize(out Dest: TManaged); class operator Assign(var Dest: TManaged; const [ref] Src: TManaged);
    {$endif}class operator Finalize(var Dest: TManaged);
  end;
{$ifdef FPC}class operator TManaged.Initialize(var Dest: TManaged); begin Inc(InitCount); end;
class operator TManaged.Copy(constref Src: TManaged; var Dest: TManaged); begin Dest.Value := Src.Value; end;
{$else}class operator TManaged.Initialize(out Dest: TManaged); begin Inc(InitCount); end;
class operator TManaged.Assign(var Dest: TManaged; const [ref] Src: TManaged); begin Dest.Value := Src.Value; end;
{$endif}class operator TManaged.Finalize(var Dest: TManaged); begin Inc(FinalCount); end;

procedure Run;
begin
var Dictionary := TDictionary<Integer,TManaged>.Create;
  try var Value: TManaged; Value.Value := 'payload'; Dictionary.Add(7, Value);
    var ReadValue: TManaged; Check(Dictionary.TryGetValue(7, ReadValue) and (ReadValue.Value = 'payload'), 'payload');
    Dictionary.Remove(7);
  finally Dictionary.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-06');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-06: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
