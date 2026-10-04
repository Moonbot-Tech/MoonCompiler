program managed_result_transfer_semantic;
{$IFDEF FPC}{$mode delphi}{$modeswitch advancedrecords}{$ENDIF}
uses SysUtils;
type
  TManaged = record
    Value: Integer;
    class operator Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TManaged);
    class operator Finalize(var Dest: TManaged);
  end;
  PManaged = ^TManaged;
var
  Initializations, Finalizations: Integer;
  Finished: Boolean;
  Alias: PManaged;
class operator TManaged.Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TManaged);
begin
  If Finished then raise Exception.Create('Initialize after transfer');
  Inc(Initializations);
  Dest.Value := 0;
end;
class operator TManaged.Finalize(var Dest: TManaged);
begin
  Inc(Finalizations);
end;
function MakeValue: TManaged; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result.Value := 42;
  Finished := True;
end;
procedure Test;
var
  X: TManaged;
begin
  Alias := @X;
  X := MakeValue;
  If X.Value <> 42 then Halt(71);
end;
begin
  try
    Test;
    WriteLn('TRANSFER_FINISHED');
  except
    on E: Exception do begin
      WriteLn('UNEXPECTED ', E.Message);
      Halt(72);
    end;
  end;
  WriteLn('LIFETIMES ', Initializations, ' ', Finalizations);
  If Initializations <> Finalizations then Halt(73);
  WriteLn('MANAGED_RESULT_TRANSFER_PASS');
end.
