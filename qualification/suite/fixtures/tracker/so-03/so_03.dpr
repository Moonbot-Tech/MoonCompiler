program tracker_so_03;

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
  TEntityBase = class Base: NativeInt; end;
  TEntity<TKey> = class(TEntityBase) Key: TKey; end;
  TMyEntity2 = class;
  TMyEntity1 = class(TEntity<Integer>) Marker: NativeInt; end;
  TMyEntity2 = class(TEntity<Integer>) Other: NativeInt; end;

procedure Run;
begin
var Value := TMyEntity1.Create;
  try Value.Base := 11; Value.Key := 22; Value.Marker := 33;
    Check((Value.Base = 11) and (Value.Key = 22) and (Value.Marker = 33), 'layout');
  finally Value.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-03');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-03: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
