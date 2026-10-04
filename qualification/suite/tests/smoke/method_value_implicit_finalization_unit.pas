unit method_value_implicit_finalization_unit;
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
interface
var Last: Integer;
implementation
type
  TMethodProc = procedure(X: Integer) of object;
  TTracked = class(TInterfacedObject)
    destructor Destroy; override;
  end;
  TRec = record
    I: IInterface;
    V: Integer;
    procedure Step(X: Integer);
  end;
var M: TMethodProc;
destructor TTracked.Destroy;
begin
  WriteLn('IMPLICIT_FINALIZATION_OK');
  inherited;
end;
procedure TRec.Step(X: Integer);
begin
  Inc(V, X);
  Last := V;
end;
function MakeRec: TRec;
begin
  Result.I := TTracked.Create;
  Result.V := 1;
end;
initialization
  M := MakeRec.Step;
  M(2);
end.
