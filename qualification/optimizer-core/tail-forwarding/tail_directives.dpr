program tail_directives;
{$mode delphi}
{$inline off}
{$asmmode intel}
uses SysUtils;
type
  TBox = class
    function Value: NativeInt; virtual;
  end;
function TBox.Value: NativeInt;
begin
  Result := 73;
end;
function PointerSink(P: Pointer): Pointer; noinline;
begin
  Result := P;
end;
{$push}{$stackframes on}
function KeepFrame(B: TBox): NativeInt; noinline;
begin
  Result := B.Value;
end;
{$pop}
{$push}{$S+}
function CheckStack(B: TBox): NativeInt; noinline;
begin
  Result := B.Value;
end;
{$pop}
function ObserveFrame: Pointer; noinline;
begin
  Result := PointerSink(Get_Frame);
end;
function ObserveCaller: Pointer; noinline;
begin
  Result := PointerSink(Get_Caller_Addr(Get_Frame));
end;
{$ifdef MSWINDOWS}
procedure ClobberResult; assembler; nostackframe;
asm
  mov eax, $80004005
end;
{$push}{$implicitexceptions off}
procedure SafeForward; safecall; noinline;
begin
  ClobberResult;
end;
{$pop}
{$endif}
var
  B: TBox;
begin
  B := TBox.Create;
  If KeepFrame(B) <> 73 then Halt(1);
  If CheckStack(B) <> 73 then Halt(2);
  If ObserveFrame = nil then Halt(3);
  If ObserveCaller = nil then Halt(4);
{$ifdef MSWINDOWS}
  SafeForward;
{$endif}
  B.Free;
  Writeln('TAIL_DIRECTIVES_PASS');
end.
