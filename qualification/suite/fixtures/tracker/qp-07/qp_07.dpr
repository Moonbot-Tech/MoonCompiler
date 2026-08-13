program tracker_qp_07;

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
  TIntThunk = reference to function: Integer;
  TWrapper = record
    Kind: Integer;
    Value: Integer;
    Thunk: TIntThunk;
    class operator Implicit(const Source: TIntThunk): TWrapper;
    class operator Implicit(Source: Integer): TWrapper;
    function Evaluate: Integer;
  end;

class operator TWrapper.Implicit(const Source: TIntThunk): TWrapper;
begin
  Result.Kind := 1;
  Result.Value := 0;
  Result.Thunk := Source;
end;

class operator TWrapper.Implicit(Source: Integer): TWrapper;
begin
  Result.Kind := 2;
  Result.Value := Source;
  Result.Thunk := nil;
end;

function TWrapper.Evaluate: Integer;
begin
  if Assigned(Thunk) then
    Result := Thunk()
  else
    Result := Value;
end;

procedure Run;
begin
var Calls := 0;
  var Value: TWrapper :=
    function: Integer
    begin
      Inc(Calls);
      Result := 7;
    end;
  Check(Calls = 0, 'called-during-conversion');
  Check(Value.Kind = 1, 'wrong-overload');
  Check(Value.Evaluate = 7, 'evaluation');
  Check(Calls = 1, 'call-count');
end;

begin
  try
    Run;
    WriteLn('PASS QP-07');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-07: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
