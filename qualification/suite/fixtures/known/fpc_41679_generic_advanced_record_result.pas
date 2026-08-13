program Fpc41679GenericAdvancedRecordResult;

{$mode objfpc}
{$modeswitch advancedrecords}

type
  generic TGeneric<T> = record
    type
      TSubtype = record
        A: Integer;
        B: T;
      end;
    function Build: TSubtype;
  end;

  TTest = record
    type
      TSecondary = specialize TGeneric<TTest>;
    var
    Data: PtrUInt;
  end;

function TGeneric.Build: TSubtype;
begin
  Result := Default(TSubtype);
end;

begin
end.
