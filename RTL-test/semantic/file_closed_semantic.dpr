program file_closed_semantic;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
{$APPTYPE CONSOLE}{$I-}
uses SysUtils;
var
  U: File;
  T: File of Integer;
  V: Integer;

procedure Check(Ok: Boolean; Code: Integer);
begin
  If not Ok then Halt(Code);
end;

procedure ClosedU;
begin
  Check(Eof(U), 11);
  Check(IOResult = 103, 12);
  Check(FilePos(U) = -1, 13);
  Check(IOResult = 103, 14);
  Check(FileSize(U) = -1, 15);
  Check(IOResult = 103, 16);
end;

procedure ClosedT;
begin
  Check(Eof(T), 21);
  Check(IOResult = 103, 22);
  Check(FilePos(T) = -1, 23);
  Check(IOResult = 103, 24);
  Check(FileSize(T) = -1, 25);
  Check(IOResult = 103, 26);
end;

begin
  AssignFile(U, 'file_closed_semantic.missing');
  AssignFile(T, 'file_closed_semantic.missing');
  ClosedU;
  ClosedT;
  Reset(U, 1);
  Check(IOResult = 2, 31);
  Reset(T);
  Check(IOResult = 2, 32);
  ClosedU;
  ClosedT;
  AssignFile(U, 'file_closed_semantic.bin');
  Rewrite(U, 1);
  Check(IOResult = 0, 33);
  Check(Eof(U) and (FilePos(U) = 0) and (FileSize(U) = 0), 34);
  V := 123;
  BlockWrite(U, V, SizeOf(V));
  Seek(U, 0);
  Check(not Eof(U) and (FilePos(U) = 0) and (FileSize(U) = SizeOf(V)), 35);
  Seek(U, SizeOf(V));
  Check(Eof(U), 36);
  CloseFile(U);
  Check(IOResult = 0, 37);
  ClosedU;
  AssignFile(T, 'file_closed_semantic.bin');
  Reset(T);
  Check(not Eof(T) and (FilePos(T) = 0) and (FileSize(T) = 1), 38);
  Read(T, V);
  Check((V = 123) and Eof(T) and (FilePos(T) = 1), 39);
  CloseFile(T);
  Check(IOResult = 0, 40);
  ClosedT;
  Erase(U);
  Check(IOResult = 0, 41);
  {$I+}
  try
    V := FilePos(U);
    Halt(42);
  except
    on E: EInOutError do Check(E.ErrorCode = 103, 43);
  end;
  try
    If Eof(T) then Halt(44);
    Halt(45);
  except
    on E: EInOutError do Check(E.ErrorCode = 103, 46);
  end;
  WriteLn('FILE_CLOSED_SEMANTIC_PASS');
end.
