unit umoontinyfinally1;

{$mode delphiunicode}
{$inline on}

interface

function InlineCleanup(Value: Integer; var Visits: Integer): Integer; inline;

implementation

function InlineCleanup(Value: Integer; var Visits: Integer): Integer;
begin
  try
    Result := Value * 2;
  finally
    Inc(Visits);
  end;
end;

end.
