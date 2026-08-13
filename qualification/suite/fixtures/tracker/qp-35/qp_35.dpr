program tracker_qp_35;

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
  TCrud<T> = class
  public type
    TResultRecord = record
      ID: T;
    end;
    TReader = reference to function(const Value: TResultRecord): T;
    function Load(const Value: T): TResultRecord;
  end;
  TIntResult = TCrud<Integer>.TResultRecord;
  TIntResultHelper = record helper for TIntResult
    function ReadID: Integer;
  end;
function TCrud<T>.Load(const Value: T): TResultRecord;
begin Result.ID := Value; end;
function TIntResultHelper.ReadID: Integer;
begin Result := Self.ID; end;

procedure Run;
begin
var Crud := TCrud<Integer>.Create;
  try
    var Item := Crud.Load(73);
    var Reader: TCrud<Integer>.TReader :=
      function(const Value: TIntResult): Integer
      begin Result := Value.ReadID; end;
    Check(Reader(Item) = 73, 'nested-helper-callback');
  finally Crud.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-35');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-35: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
