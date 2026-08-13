program tracker_qp_45;

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
  TPayload<T> = packed record
    Marker: Byte;
    Value: T;
    Tail: Word;
    class operator Equal(const Left, Right: TPayload<T>): Boolean;
  end;
class operator TPayload<T>.Equal(const Left, Right: TPayload<T>): Boolean;
begin Result := (Left.Marker = Right.Marker) and (Left.Value = Right.Value) and (Left.Tail = Right.Tail); end;

procedure Run;
begin
var List := TList<TPayload<Integer>>.Create;
  try
    for var I := 1 to 8 do
    begin
      var Item: TPayload<Integer>;
      Item.Marker := I; Item.Value := I * 10; Item.Tail := 1000 + I;
      List.Add(Item);
    end;
    while List.Count > 0 do
    begin
      var Item := List[List.Count div 2];
      Check(List.Remove(Item) >= 0, 'remove');
    end;
    Check(List.Count = 0, 'empty');
  finally List.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-45');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-45: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
