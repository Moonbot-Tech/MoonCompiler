program Fpc41589RecordHelperProperty;

{$mode objfpc}
{$modeswitch advancedrecords}
{$modeswitch typehelpers}

type
  TPoint = record
    X, Y: LongInt;
  end;

  TPointHelper = record helper for TPoint
    procedure SetX(Value: LongInt);
  end;

  THolder = class
  private
    FPoint: TPoint;
  public
    property Point: TPoint read FPoint write FPoint;
  end;

procedure TPointHelper.SetX(Value: LongInt);
begin
  Self.X := Value;
end;

var
  Holder: THolder;
  P: TPoint;
begin
  Holder := THolder.Create;
  try
    P.X := 100;
    P.Y := 100;
    Holder.Point := P;
    Holder.Point.SetX(50);
    if Holder.Point.X <> 100 then
      Halt(1);
  finally
    Holder.Free;
  end;
end.
