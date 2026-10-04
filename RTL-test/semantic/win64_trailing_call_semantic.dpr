program win64_trailing_call_semantic;

{ %TARGET=win64 }

{ An exception raised below a noreturn procedure whose last instruction is a
  call must reach the except of its caller.  Such a procedure never removes
  its frame, and the Win64 unwinder reads the code at the return address of
  that call: past the .pdata end (the tail CallRet2Call used to leave) it
  finds no function, on a ret it emulates an epilogue and takes a word of the
  frame for the caller's address.  Either way the process died with
  0xE0465043.  The compiler puts int3 behind the call; RTL-test/run.py checks
  every return address of the executable with
  qualification/build-driver/pdata_tail_gate.py.

  Both procedures are noinline: inlined, the wrapper has no call of its own
  to unwind through (the -O3 build passed without the repair). }

{$mode delphiunicode}{$H+}

uses
  SysUtils;

procedure AlwaysRaises; noinline;
begin
  raise Exception.Create('expected');
end;

{ a noreturn procedure may not raise itself: it ends with the call }
procedure NoReturnCaller; noreturn; noinline;
begin
  AlwaysRaises;
end;

var
  Caught: Boolean;
begin
  Caught := False;
  try
    NoReturnCaller;
  except
    on E: Exception do
      Caught := E.Message = 'expected';
  end;
  If not Caught then begin
    WriteLn('FAIL: the exception did not reach except');
    Halt(1);
  end;
  WriteLn('WIN64_TRAILING_CALL_PASS');
end.
