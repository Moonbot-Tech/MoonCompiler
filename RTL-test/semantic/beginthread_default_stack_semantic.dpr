program beginthread_default_stack_semantic;
{ %TARGET=linux }
{$IFDEF FPC}{$mode delphi}{$ENDIF}
uses SysUtils;
var
  Calls: Integer;
  Id, H: TThreadID;

function Worker(P: Pointer): Integer;
var
  Data: array[0..8191] of Byte;
begin
  FillChar(Data, SizeOf(Data), 37);
  If (Data[0] <> 37) or (Data[High(Data)] <> 37) then Halt(11);
  Inc(Calls);
  Result := 57;
end;

procedure Start(StackSize: NativeUInt);
begin
  H := BeginThread(nil, StackSize, @Worker, nil, 0, Id);
  If (H = 0) or (Id = 0) then Halt(12);
  If WaitForThreadTerminate(H, 5000) <> 57 then Halt(13);
  CloseThread(H);
end;

begin
  Start(0);
  Start(1 shl 20);
  If Calls <> 2 then Halt(14);
  H := BeginThread(nil, 1, @Worker, nil, 0, Id);
  If (H <> 0) or (Id <> 0) or (Calls <> 2) then Halt(15);
  WriteLn('BEGINTHREAD_DEFAULT_STACK_SEMANTIC_PASS');
end.
