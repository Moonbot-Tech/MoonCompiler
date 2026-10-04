program managed_result_getter_throw_semantic;
{$IFDEF FPC}{$mode delphi}{$modeswitch advancedrecords}{$ENDIF}
uses SysUtils, semtrack;
type
  TManaged = record
    Token: IToken;
    Value: Integer;
    class operator Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TManaged);
    class operator Finalize(var Dest: TManaged);
  end;
  PManaged = ^TManaged;
var G: TManaged; GetterCalls, Calls: Integer;
class operator TManaged.Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TManaged);
begin
  Dest.Token := TToken.Create;
end;
class operator TManaged.Finalize(var Dest: TManaged);
begin
end;
function MakeValue: TManaged; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(Calls);
  Result.Value := 42;
end;
function Destination: PManaged; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(GetterCalls);
  raise Exception.Create('destination getter');
end;
procedure Transfer;
begin
  Destination^ := MakeValue;
end;
begin
  try
    Transfer;
    Halt(71);
  except
    on E: Exception do If E.Message <> 'destination getter' then raise;
  end;
  WriteLn('GETTER_OWNER ', Created, ' ', Destroyed, ' ', GetterCalls, ' ', Calls);
  If (Created <> 2) or (Destroyed <> 1) or (GetterCalls <> 1) or (Calls <> 0) then Halt(72);
  If G.Token.Value <> 42 then Halt(73);
  WriteLn('MANAGED_RESULT_GETTER_THROW_PASS');
end.
