unit funcref_value_units_class_unit;
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$ENDIF}
{ The class and the routines of funcref_value_units that other units give to
  "reference to".  The initialization gives a method of this class, declared
  in the interface of the unit, to a reference; the object is a variable of
  the unit nothing else reads, which -O2 may keep in a register there. }
interface

type
  TIntProc = reference to procedure(Step: Integer);
  TStrProc = reference to procedure(const S: string);
  TMethodProc = procedure(Step: Integer) of object;

  TCounter = class
    Count: Integer;
    procedure Step(Amount: Integer);
    procedure Put(A: Integer); overload;
    procedure Put(const S: string); overload;
  end;

procedure PutValue(A: Integer); overload;
procedure PutValue(const S: string); overload;

var
  PutTotal: Integer;
  InitA, InitB: TCounter;
  InitResult: Integer;

implementation

var
  InitC: TCounter;
  InitP: TIntProc;

procedure TCounter.Step(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure TCounter.Put(A: Integer);
begin
  Inc(Count, A);
end;

procedure TCounter.Put(const S: string);
begin
  Inc(Count, Length(S) * 1000);
end;

procedure PutValue(A: Integer);
begin
  Inc(PutTotal, A);
end;

procedure PutValue(const S: string);
begin
  Inc(PutTotal, Length(S) * 1000);
end;

initialization
  InitA := TCounter.Create;
  InitB := TCounter.Create;
  InitC := InitA;
  InitP := InitC.Step;
  InitC := InitB;
  InitP(1);
  InitResult := InitA.Count * 100 + InitB.Count;
finalization
  InitP := nil;
  InitA.Free;
  InitB.Free;
end.
