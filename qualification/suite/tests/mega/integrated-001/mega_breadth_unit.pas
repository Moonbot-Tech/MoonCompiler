unit mega_breadth_unit;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

interface

type
  TBreadthUnitCode = type SmallInt;

  TBreadthUnitStamp = record
    Data: Int64;
    LabelText: AnsiString;
  end;

var
  BreadthUnitCoefficient: Integer;

procedure BreadthChangeCoefficient(Delta: Integer);
function BreadthUnitDecode(Value: Int64): TBreadthUnitCode; inline;
procedure BreadthResetSequence(Initial: Integer);
function BreadthReadSequence: Integer;
function BreadthAdvanceSequence(Delta: Integer): Integer;
function BreadthNextStamp(const Prefix: AnsiString; Delta: Integer): TBreadthUnitStamp; inline;

implementation

var
  Sequence: Integer;

procedure BreadthChangeCoefficient(Delta: Integer);
begin
  Inc(BreadthUnitCoefficient, Delta);
end;

function BreadthUnitDecode(Value: Int64): TBreadthUnitCode;
begin
  Result := TBreadthUnitCode(Value);
end;

procedure BreadthResetSequence(Initial: Integer);
begin
  Sequence := Initial;
end;

function BreadthReadSequence: Integer;
begin
  Result := Sequence;
end;

function BreadthAdvanceSequence(Delta: Integer): Integer;
begin
  Inc(Sequence, Delta);
  Result := Sequence;
end;

function BreadthNextStamp(const Prefix: AnsiString; Delta: Integer): TBreadthUnitStamp;
begin
  Result.Data := Int64(BreadthAdvanceSequence(Delta)) * 1000000007 + Delta;
  Result.LabelText := Prefix + '!';
end;

end.
