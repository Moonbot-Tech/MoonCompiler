unit uinlineblock1;

{$mode delphi}
{$inline on}

interface

type
  TShrinkProc = function(ARequired: LongInt): LongInt;

  TFallback = object
    class function Shrink(const ARequired, ACurrent: LongInt): LongInt; static; inline;
  end;

  TWrapper = object
    Callback: TShrinkProc;
    Fallback: TFallback;
    function Shrink(const ARequired, ACurrent: LongInt): LongInt; inline;
  end;

implementation

class function TFallback.Shrink(const ARequired, ACurrent: LongInt): LongInt;
begin
  if Int64(ARequired) * 4 < ACurrent then
    Result := ARequired * 2
  else
    Result := -1;
end;

function TWrapper.Shrink(const ARequired, ACurrent: LongInt): LongInt;
begin
  if Assigned(Callback) then
    Result := Callback(ARequired)
  else
    Result := Fallback.Shrink(ARequired, ACurrent);
end;

end.
