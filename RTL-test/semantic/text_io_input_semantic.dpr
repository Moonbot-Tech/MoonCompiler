program text_io_input_semantic;
{$mode delphi}
uses SysUtils;
var Cases:Integer;
procedure Check(Value:Boolean);
begin
  If not Value then Halt(1);
end;
{$I-}
function Unchecked(Operation:Integer):Boolean; inline;
begin
  case Operation of
    0:Result:=Eof;
    1:Result:=Eoln;
    2:Result:=SeekEof;
    3:Result:=SeekEoln;
  end;
end;
{$I+}
function Checked(Operation:Integer):Boolean; inline;
begin
  case Operation of
    0:Result:=Eof;
    1:Result:=Eoln;
    2:Result:=SeekEof;
    3:Result:=SeekEoln;
  end;
end;
procedure Run(Operation:Integer; Valid:Boolean);
var B,Caught:Boolean; Error:Integer;
begin
  If Valid then InOutRes:=5;
  B:=Unchecked(Operation);
  Error:=IOResult;
  If Valid then Check(Error=5) else Check(Error=104);
  If Valid then InOutRes:=5;
  Caught:=False;
  try
    B:=Checked(Operation);
  except
    on E:EInOutError do begin
      Caught:=True;
      Check(E.ErrorCode=Error);
    end;
  end;
  Check(Caught);
  Check(IOResult=0);
  Inc(Cases);
end;
var Operation:Integer;
begin
  AssignFile(Input,'input.dat');
  for Operation:=0 to 3 do Run(Operation,False);
  Rewrite(Input);
  WriteLn(Input,'x');
  CloseFile(Input);
  Reset(Input);
  for Operation:=0 to 3 do Run(Operation,True);
  Check(not Eof and not Eoln and not SeekEof and not SeekEoln);
  CloseFile(Input);
  Erase(Input);
  Check(Cases=8);
  WriteLn('TEXT_IO_INPUT_PASS',' ',Cases);
end.
