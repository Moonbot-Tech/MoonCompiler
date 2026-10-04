program managed_result_matrix_semantic;
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
  TPair = array[0..1] of TManaged;
var
  Initializations, Finalizations, GetterCalls: Integer;
  Alias: PManaged;
  RaisingFinalize: Boolean;
class operator TManaged.Initialize({$IFDEF FPC}var{$ELSE}out{$ENDIF} Dest: TManaged);
begin
  Inc(Initializations);
  Dest.Value := 0;
end;
class operator TManaged.Finalize(var Dest: TManaged);
begin
  Inc(Finalizations);
  If RaisingFinalize and (Dest.Value = -9) then begin
    RaisingFinalize := False;
    Dest.Token := nil;
    raise Exception.Create('finalize destination');
  end;
end;
function MakeValue(N: Integer; Fail: Boolean): TManaged; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result.Value := N;
  Result.Token := TToken.Create;
  If Fail then raise Exception.Create('return body');
end;
function MakeAlias: TManaged; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result.Value := Alias.Value + 1;
  Result.Token := TToken.Create;
  If Alias.Value <> 42 then Halt(81);
end;
function MakeInline(N: Integer): TManaged; inline;
begin
  Result.Value := N;
  Result.Token := TToken.Create;
end;
function MakePair(N: Integer): TPair; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result[0].Value := N;
  Result[0].Token := TToken.Create;
  Result[1].Value := N + 1;
  Result[1].Token := TToken.Create;
end;
function Destination: PManaged;
begin
  Inc(GetterCalls);
  Result := Alias;
end;
procedure Test;
var
  Holder: record Field: TManaged; end;
  Values: array[0..2] of TManaged;
  Pair: TPair;
begin
  Alias := @Holder.Field;
  Holder.Field.Value := 42;
  Holder.Field := MakeAlias;
  If Holder.Field.Value <> 43 then Halt(82);
  for var I := 0 to 7 do begin
    Destination^ := MakeValue(I, False);
    If Holder.Field.Value <> I then Halt(83);
    Values[I mod 3] := MakeInline(I + 10);
  end;
  If GetterCalls <> 8 then Halt(84);
  try
    Destination^ := MakeValue(99, True);
    Halt(85);
  except
    on E: Exception do If E.Message <> 'return body' then raise;
  end;
  If (GetterCalls <> {$IFDEF FPC}9{$ELSE}8{$ENDIF}) or (Holder.Field.Value <> 7) then Halt(86);
  Pair := MakePair(22);
  If (Pair[0].Value <> 22) or (Pair[1].Value <> 23) then Halt(87);
  {$IFDEF FPC}
  Holder.Field.Value := -9;
  RaisingFinalize := True;
  try
    Destination^ := MakeValue(100, False);
    Halt(88);
  except
    on E: Exception do If E.Message <> 'finalize destination' then raise;
  end;
  {$ENDIF}
end;
begin
  Test;
  WriteLn('MATRIX_VALUES_OK ', GetterCalls);
  {$IFDEF FPC}If Initializations <> Finalizations - 1 then Halt(89);{$ENDIF}
  WriteLn('MATRIX_OWNERS ', Created, ' ', Destroyed);
  If Created <> Destroyed then Halt(90);
  WriteLn('MANAGED_RESULT_MATRIX_PASS');
end.
