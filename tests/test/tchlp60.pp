program tchlp60;

{$mode delphi}

type
  TTarget=class
  end;

  TVisible=class helper for TTarget
    function Read: Integer;
  end;

  THolder=class
  strict private type
    THidden=class helper for TTarget
      function Read: Integer;
    end;
  end;

function TVisible.Read: Integer;
begin
  Result:=11;
end;

function THolder.THidden.Read: Integer;
begin
  Result:=22;
end;

var
  Target: TTarget;
begin
  Target:=TTarget.Create;
  try
    if Target.Read<>22 then
      Halt(1);
  finally
    Target.Free;
  end;
end.
