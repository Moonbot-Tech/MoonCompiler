program tail_semantic;
{$mode delphi}
{$inline off}
uses SysUtils;
type
  TBase = class
    function Value: NativeInt; virtual; abstract;
  end;
  TChild = class(TBase)
    function Value: NativeInt; override;
  end;
var
  ThrowNow: Boolean;
  Cleaned: Integer;
function TChild.Value: NativeInt;
begin
  If ThrowNow then
    raise Exception.Create('tail-marker');
  Result := 73;
end;
function Forwarded(B: TBase): NativeInt; noinline;
begin
  Result := B.Value;
end;
var
  B: TBase;
  S: NativeInt;
  I: Integer;
begin
  B := TChild.Create;
  S := Forwarded(B);
  If S <> 73 then Halt(1);
  ThrowNow := True;
  try
    try
      S := Forwarded(B);
      Halt(2);
    finally
      Inc(Cleaned);
    end;
  except
    on E: Exception do
    begin
      If E.Message <> 'tail-marker' then Halt(3);
      Writeln('TARGET_STACK_BEGIN');
      Writeln(BackTraceStrFunc(ExceptAddr));
      for I := 0 to ExceptFrameCount-1 do
        Writeln(BackTraceStrFunc(ExceptFrames[I]));
      Writeln('TARGET_STACK_END');
    end;
  end;
  B.Free;
  If Cleaned <> 1 then Halt(4);
  try
    S := Forwarded(nil);
    Halt(5);
  except
    on E: EAccessViolation do
      Inc(Cleaned);
  end;
  If Cleaned <> 2 then Halt(6);
  Writeln('TAIL_SEMANTIC_PASS');
end.
