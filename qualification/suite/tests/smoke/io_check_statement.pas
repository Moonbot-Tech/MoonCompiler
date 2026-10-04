program io_check_statement;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ With I/O checks on, a Read or Write statement does all its items and only
  then raises EInOutError, as in Delphi 12.2: every item is written or read
  when an error was left pending before the statement, a number read into a
  byte is stored, and the next statement goes on after the line the
  statement read. Text and typed files. One source for Delphi 12.2 and
  MoonCompiler. }
{$I+}
uses
  SysUtils;

var
  Dir, Fails: string;
  Counter: Integer;

function Next: Integer;
begin
  Inc(Counter);
  Result := Counter;
end;

procedure Fail(const What: string);
begin
  Fails := Fails + ' ' + What;
end;

procedure Expect(Ok: Boolean; const What: string);
begin
  If not Ok then
    Fail(What);
end;

{ InOutRes := 2, file not found, left pending }
procedure Pend;
var
  M: TextFile;
begin
  AssignFile(M, Dir + 'io_check_statement.no-such-file');
  {$I-}
  Reset(M);
  {$I+}
end;

function Content(const Name: string): AnsiString;
var
  H: THandle;
  Buf: array[0..255] of AnsiChar;
  N: Integer;
begin
  Result := '';
  H := FileOpen(Name, fmOpenRead or fmShareDenyNone);
  If H = THandle(-1) then
    Exit;
  N := FileRead(H, Buf, SizeOf(Buf));
  FileClose(H);
  If N > 0 then
    SetString(Result, PAnsiChar(@Buf[0]), N);
end;

procedure MakeFile(const Name: string; const Data: AnsiString);
var
  H: THandle;
begin
  H := FileCreate(Name);
  FileWrite(H, Data[1], Length(Data));
  FileClose(H);
end;

procedure TextWrite;
var
  F: TextFile;
  Code: Integer;
begin
  AssignFile(F, Dir + 'io_check_statement.w');
  Rewrite(F);
  Pend;
  Code := 0;
  try
    Write(F, 'a', 1, 'b');
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect(Code = 2, 'write-raised');
  Expect(IOResult = 0, 'write-cleared');
  Pend;
  Code := 0;
  try
    Writeln(F, 'c', 'd');
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect(Code = 2, 'writeln-raised');
  CloseFile(F);
  Expect(Content(Dir + 'io_check_statement.w') = 'a1bcd' + sLineBreak, 'write-content');
  DeleteFile(Dir + 'io_check_statement.w');
end;

procedure TextRead;
var
  G: TextFile;
  I, J, Code: Integer;
  B: Byte;
begin
  MakeFile(Dir + 'io_check_statement.r', '5 6' + sLineBreak + '7 8' + sLineBreak);
  AssignFile(G, Dir + 'io_check_statement.r');
  Reset(G);
  I := -1;
  J := -1;
  Pend;
  Code := 0;
  try
    Readln(G, I, J);
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect(Code = 2, 'readln-raised');
  Expect((I = 5) and (J = 6), 'readln-values');
  B := 0;
  Pend;
  Code := 0;
  try
    Read(G, B);
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect(Code = 2, 'read-byte-raised');
  Expect(B = 7, 'read-byte-value');
  CloseFile(G);
  DeleteFile(Dir + 'io_check_statement.r');
end;

procedure TypedFile;
var
  T: file of Integer;
  A, B, C, Code: Integer;
begin
  AssignFile(T, Dir + 'io_check_statement.t');
  Rewrite(T);
  A := 1;
  B := 2;
  C := 3;
  Pend;
  Code := 0;
  try
    Write(T, A, B, C);
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect(Code = 2, 'typed-write-raised');
  Expect(FileSize(T) = 3, 'typed-write-count');
  CloseFile(T);
  Reset(T);
  A := 0;
  B := 0;
  Pend;
  Code := 0;
  try
    Read(T, A, B);
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect(Code = 2, 'typed-read-raised');
  Expect((A = 1) and (B = 2), 'typed-read-values');
  CloseFile(T);
  Erase(T);
end;

procedure FailureDuringStatement;
var
  F: TextFile;
  T: file of Integer;
  Values: array[1..2] of Integer;
  Code: Integer;
begin
  AssignFile(F, Dir + 'io_check_statement.missing');
  Counter := 0;
  Code := 0;
  try
    Write(F, Next, Next);
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect((Counter = 2) and (Code <> 0), 'text-failed-first-item');

  AssignFile(T, Dir + 'io_check_statement.missing');
  Values[1] := 1;
  Values[2] := 2;
  Counter := 0;
  Code := 0;
  try
    Write(T, Values[Next], Values[Next]);
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect((Counter = 2) and (Code <> 0), 'typed-failed-first-item');
end;

{$IFDEF FPC}
procedure StringReadWrite;
var
  S: string;
  A, B, Code: Integer;
begin
  S := '';
  Pend;
  Code := 0;
  try
    WriteStr(S, 'a', 1, 'b');
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect((S = 'a1b') and (Code = 2), 'writestr');
  Expect(IOResult = 0, 'writestr-cleared');

  A := -1;
  B := -1;
  Pend;
  Code := 0;
  try
    ReadStr('12 34', A, B);
  except
    on E: EInOutError do
      Code := E.ErrorCode;
  end;
  Expect((A = 12) and (B = 34) and (Code = 2), 'readstr');
  Expect(IOResult = 0, 'readstr-cleared');
end;
{$ENDIF}

begin
  Dir := ExtractFilePath(ParamStr(0));
  TextWrite;
  TextRead;
  TypedFile;
  FailureDuringStatement;
  {$IFDEF FPC}
  StringReadWrite;
  {$ENDIF}
  If Fails = '' then
    Writeln('IO_CHECK_STATEMENT_OK')
  else
    Writeln('IO_CHECK_STATEMENT_FAIL', Fails);
end.
