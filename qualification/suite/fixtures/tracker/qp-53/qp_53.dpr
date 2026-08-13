program tracker_qp_53;

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
  TOuter<T> = class
  public type TInner<U> = record First: T; Second: U; end;
  end;
  TSpecial = TOuter<Integer>.TInner<string>;
  THolder = record Value: TSpecial; end;
  TObjectHolder = class Value: TSpecial; end;

procedure Run;
begin
var Local: TSpecial; Local.First := 7; Local.Second := 'seven';
  var ArrayValue: TArray<TSpecial> := [Local];
  var RecordValue: THolder; RecordValue.Value := Local;
  var ObjectValue := TObjectHolder.Create;
  try ObjectValue.Value := Local;
    Check((ArrayValue[0].Second = 'seven') and (RecordValue.Value.First = 7) and (ObjectValue.Value.Second = 'seven'), 'aggregate-forms');
  finally ObjectValue.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-53');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-53: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
