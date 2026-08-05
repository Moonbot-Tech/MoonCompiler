{ %OPT=-O3 }
program tdelphihelperinherited1;

{$mode delphi}

type
  TBase = class
  public
    function Value: Integer; virtual;
    function SelfValue: Integer;
  end;

  TChild = class(TBase)
  public
    function Value: Integer; override;
  end;

  TBaseHelper = class helper for TBase
  public
    function Value: Integer;
    function RealValue: Integer;
  end;

function TBase.Value: Integer;
begin
  Result := 1;
end;

function TBase.SelfValue: Integer;
begin
  Result := Value;
end;

function TChild.Value: Integer;
begin
  Result := 2;
end;

function TBaseHelper.Value: Integer;
begin
  Result := 100 + inherited Value;
end;

function TBaseHelper.RealValue: Integer;
begin
  Result := inherited Value;
end;

var
  Base: TBase;
begin
  Base := TChild.Create;
  If Base.Value <> 101 then Halt(1);
  If Base.RealValue <> 1 then Halt(2);
  If Base.SelfValue <> 101 then Halt(3);
  Base.Free;
end.
