program tracker_qp_23;

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
  TMultiSetEntry<T> = record
    Value: T;
  end;
  TMultiSet<T> = class
  public type
    TEntry = TMultiSetEntry<T>;
  private
    FEntries: TArray<TEntry>;
  public
    procedure FillAndSort(const A, B, C: T);
    function At(Index: Integer): T;
  end;
procedure TMultiSet<T>.FillAndSort(const A, B, C: T);
begin
  SetLength(FEntries, 3);
  FEntries[0].Value := A; FEntries[1].Value := B; FEntries[2].Value := C;
  TArray.Sort<TEntry>(FEntries,
    TComparer<TEntry>.Construct(
      function(const Left, Right: TEntry): Integer
      begin Result := TComparer<T>.Default.Compare(Left.Value, Right.Value); end));
end;
function TMultiSet<T>.At(Index: Integer): T;
begin Result := FEntries[Index].Value; end;

procedure Run;
begin
var Values := TMultiSet<Integer>.Create;
  try
    Values.FillAndSort(3, 1, 2);
    Check((Values.At(0) = 1) and (Values.At(1) = 2) and (Values.At(2) = 3), 'sorted');
  finally Values.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-23');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-23: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
