program text_io_contract_semantic;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
uses SysUtils;

var
  F: File of Integer;
  T: Text;
  Checks: Integer;
  GetterCalls: Integer;

function Destination:PText; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(GetterCalls);
  Result:=@T;
end;

procedure Check(Value: Boolean);
begin
  Inc(Checks);
  If not Value then begin
    WriteLn('IO_CONTRACT_FAIL ', Checks);
    Halt(1);
  end;
end;

procedure TypedWrite(Code: Integer);
var N, Error: Integer; Caught: Boolean;
begin
  N := 7;
  {$I-}
  Write(F, N);
  Error := IOResult;
  {$I+}
  Check(Error = Code);
  Caught := False;
  try
    Write(F, N);
  except
    on E: EInOutError do begin
      Caught := True;
      Check(E.ErrorCode = Code);
    end;
  end;
  Check(Caught);
  Check(IOResult = 0);
end;

procedure TextRead(Code: Integer);
var N, Error, Operation: Integer; B, Caught: Boolean; S: string;
begin
  for Operation := 0 to 6 do begin
    {$I-}
    case Operation of
      0: B := Eof(T);
      1: B := Eoln(T);
      2: B := SeekEof(T);
      3: B := SeekEoln(T);
      4: Read(T, N);
      5: Readln(T, S);
      6: Readln(T);
    end;
    Error := IOResult;
    {$I+}
    Check(Error = Code);
    Caught := False;
    try
      case Operation of
        0: B := Eof(T);
        1: B := Eoln(T);
        2: B := SeekEof(T);
        3: B := SeekEoln(T);
        4: Read(T, N);
        5: Readln(T, S);
        6: Readln(T);
      end;
    except
      on E: EInOutError do begin
        Caught := True;
        Check(E.ErrorCode = Code);
      end;
    end;
    Check(Caught);
    Check(IOResult = 0);
  end;
end;

const
  ClosedWrite = 5;
  InputWrite = 5;
  ClosedRead = 104;
var N, Error,Operation: Integer; S: string; B,Caught: Boolean;
begin
  AssignFile(F, 'typed.dat');
  TypedWrite(ClosedWrite);
  Rewrite(F);
  N := 42;
  Write(F, N);
  CloseFile(F);
  TypedWrite(ClosedWrite);
  FileMode := 0;
  Reset(F);
  TypedWrite(InputWrite);
  Read(F, N);
  Check(N = 42);
  Check(Eof(F));
  CloseFile(F);
  Erase(F);
  FileMode := 2;
  {$I-}
  Reset(F);
  Error := IOResult;
  {$I+}
  Check(Error <> 0);
  TypedWrite(ClosedWrite);
  {$I-}
  B := Eof(F);
  Error := IOResult;
  {$I+}
  Check(B and (Error = 103));
  AssignFile(T, 'text.dat');
  TextRead(ClosedRead);
  for Operation:=0 to 3 do begin
    Caught:=False;
    try
      case Operation of
        0:B:=Eof(Destination^);
        1:B:=Eoln(Destination^);
        2:B:=SeekEof(Destination^);
        3:B:=SeekEoln(Destination^);
      end;
    except
      on E:EInOutError do begin
        Caught:=True;
        Check(E.ErrorCode=ClosedRead);
      end;
    end;
    Check(Caught and (IOResult=0) and (GetterCalls=Operation+1));
  end;
  Rewrite(T);
  TextRead(104);
  WriteLn(T, '  42');
  WriteLn(T, 'tail');
  CloseFile(T);
  TextRead(ClosedRead);
  Reset(T);
  AssignFile(F,'not-open.dat');
  for Operation := 0 to 3 do begin
    N:=1;
    {$I-} Write(F,N); {$I+}
    Caught:=False;
    try
      case Operation of
        0:B:=Eof(T);
        1:B:=Eoln(T);
        2:B:=SeekEof(T);
        3:B:=SeekEoln(T);
      end;
    except
      on E:EInOutError do begin
        Caught:=True;
        Check(E.ErrorCode=5);
      end;
    end;
    Check(Caught and (IOResult=0));
  end;
  Check(not SeekEof(T));
  Readln(T, N);
  Check(N = 42);
  Readln(T, S);
  Check(S = 'tail');
  Check(Eof(T));
  CloseFile(T);
  Erase(T);
  {$I-}
  Reset(T);
  Error := IOResult;
  {$I+}
  Check(Error <> 0);
  TextRead(ClosedRead);
  WriteLn('TEXT_IO_CONTRACT_PASS');
end.
