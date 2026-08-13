program tracker_qp_14;

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
  TBase<T> = class
    BaseField: NativeInt;
  end;
  TLevel1<T> = class(TBase<T>)
    Level1Field: NativeInt;
  end;
  TLevel2<T> = class(TLevel1<T>)
    Level2Field: NativeInt;
  end;

procedure Run;
begin
var Value := TLevel2<Integer>.Create;
  try
    Value.BaseField := NativeInt($11111111);
    Value.Level1Field := NativeInt($22222222);
    Value.Level2Field := NativeInt($33333333);
    Check(Value.BaseField = NativeInt($11111111), 'base-field');
    Check(Value.Level1Field = NativeInt($22222222), 'level1-field');
    Check(Value.Level2Field = NativeInt($33333333), 'level2-field');
  finally
    Value.Free;
  end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-14');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-14: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
