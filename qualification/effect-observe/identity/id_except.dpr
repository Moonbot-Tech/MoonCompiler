program id_except;

{ Identity-gate workload: classes, virtual calls, try/except/finally,
  raise across a frame. }

{$mode delphi}

type
  TBase = class
  public
    F: Integer;
    function Get: Integer; virtual;
  end;

  TDeriv = class(TBase)
  public
    function Get: Integer; override;
  end;

function TBase.Get: Integer;
begin
  Result := F;
end;

function TDeriv.Get: Integer;
begin
  Result := F * 2;
end;

function Risky(divisor: Integer): Integer;
begin
  Result := 100 div divisor;
end;

var
  o: TBase;
  total, i: Integer;
begin
  total := 0;
  o := TDeriv.Create;
  try
    o.F := 21;
    total := total + o.Get;
  finally
    o.Free;
  end;
  { ParamCount keeps the divisor out of constant propagation, so the zero
    divisor traps at run time instead of failing the compile at -O3 }
  for i := -2 to 2 do
    try
      total := total + Risky(i + ParamCount);
    except
      total := total + 1000;
    end;
  WriteLn('except:', total);
end.
