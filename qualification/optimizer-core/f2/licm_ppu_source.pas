unit licm_ppu_source;

{$mode unleashed}
{$Q-}
{$R-}

interface

type
  TScaleWorker<T> = class
  public
    class function Run(Scale: Int64; N: Integer): Int64; static;
  end;

implementation

class function TScaleWorker<T>.Run(Scale: Int64; N: Integer): Int64;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + Scale * 257 + I;
    Inc(I);
  end;
end;

end.
