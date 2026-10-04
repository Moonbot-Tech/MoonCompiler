program managed_result_init_throw_semantic;
{$IFDEF FPC}{$mode delphi}{$modeswitch advancedrecords}{$ENDIF}
uses SysUtils, semtrack;
type
  TFirst = record
    Token: IToken;
    class operator Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TFirst);
    class operator Finalize(var Dest: TFirst);
  end;
  TLater = record
    Token: IToken;
    class operator Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TLater);
    class operator Finalize(var Dest: TLater);
  end;
  TOuter = record First: TFirst; Later: TLater; Value: Integer; end;
var FailInit: Boolean; G: TOuter; FirstFini, LaterFini, Calls: Integer;
class operator TFirst.Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TFirst);
begin
  Dest.Token := TToken.Create;
end;
class operator TFirst.Finalize(var Dest: TFirst);
begin
  Inc(FirstFini);
end;
class operator TLater.Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TLater);
begin
  Dest.Token := TToken.Create;
  If FailInit then raise Exception.Create('late initializer');
end;
class operator TLater.Finalize(var Dest: TLater);
begin
  Inc(LaterFini);
end;
function MakeValue: TOuter; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(Calls);
  Result.Value := 42;
end;
procedure Transfer;
begin
  G := MakeValue;
end;
begin
  FailInit := True;
  try
    Transfer;
    Halt(71);
  except
    on E: Exception do If E.Message <> 'late initializer' then raise;
  end;
  WriteLn('INIT_PREFIX ', Created, ' ', Destroyed, ' ', FirstFini, ' ', LaterFini, ' ', Calls);
  If (Created <> 4) or (Destroyed <> 2) or (FirstFini <> 1) or (LaterFini <> 0) or (Calls <> 0) then Halt(72);
  If (G.First.Token.Value <> 42) or (G.Later.Token.Value <> 42) then Halt(73);
  WriteLn('MANAGED_RESULT_INIT_THROW_PASS');
end.
