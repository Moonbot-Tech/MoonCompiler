program io_pending_error;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ An I/O error left pending (I/O checks off, IOResult not called) stops no
  I/O routine, as in Delphi 12.2: text files (write, read, Eof and Eoln,
  flush, close, the three opens, erase, rename), untyped and typed files,
  the directory routines and the console all do their work; the pending
  error survives every routine that succeeds, and an error of a routine
  that fails takes its place. The verdict is written with an error pending.
  One source for Delphi 12.2 and MoonCompiler. }
{$I-}
uses
  SysUtils{$IFDEF FPC}, Classes, StreamIO{$ENDIF};

var
  Dir, Fails: string;

procedure Fail(const What: string);
begin
  Fails := Fails + ' ' + What;
end;

{ InOutRes := 2, file not found, left pending }
procedure Pend;
var
  M: TextFile;
begin
  AssignFile(M, Dir + 'io_pending_error.no-such-file');
  Reset(M);
end;

{ the error made by Pend has to be the one pending after the routine }
procedure Kept(const What: string);
var
  R: Integer;
begin
  R := IOResult;
  If R <> 2 then
    Fail(What + '=' + IntToStr(R));
end;

procedure Expect(Ok: Boolean; const What: string);
begin
  If not Ok then
    Fail(What);
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

procedure TextFiles;
var
  F: TextFile;
  I: Integer;
  S: string;
begin
  AssignFile(F, Dir + 'io_pending_error.w');
  Rewrite(F);
  Pend; Write(F, 'a', 1, 'b'); Kept('write');
  Pend; Writeln(F, 'c'); Kept('writeln');
  Pend; Flush(F); Kept('flush');
  Expect(Content(Dir + 'io_pending_error.w') = 'a1bc' + sLineBreak, 'flush-content');
  Write(F, 'd');
  Pend; CloseFile(F); Kept('close');
  Expect(TTextRec(F).Mode = fmClosed, 'close-mode');
  Expect(Content(Dir + 'io_pending_error.w') = 'a1bc' + sLineBreak + 'd', 'close-content');
  MakeFile(Dir + 'io_pending_error.r', '12' + sLineBreak + 'line' + sLineBreak);
  AssignFile(F, Dir + 'io_pending_error.r');
  Reset(F);
  I := -1;
  Pend; Read(F, I); Kept('read');
  Expect(I = 12, 'read-value');
  Pend; Expect(Eoln(F), 'eoln-value'); Kept('eoln');
  Pend; Readln(F); Kept('readln');
  Pend; Expect(not Eof(F), 'eof-value'); Kept('eof');
  Pend; Expect(not SeekEof(F), 'seekeof-value'); Kept('seekeof');
  S := '';
  Pend; Readln(F, S); Kept('readln-string');
  Expect(S = 'line', 'readln-string-value');
  Pend; Expect(Eof(F), 'eof-end-value'); Kept('eof-end');
  CloseFile(F);
  AssignFile(F, Dir + 'io_pending_error.o');
  Pend; Rewrite(F); Kept('rewrite');
  Write(F, 'h');
  CloseFile(F);
  Pend; Append(F); Kept('append');
  Write(F, '2');
  CloseFile(F);
  S := '';
  Pend; Reset(F); Kept('reset');
  Readln(F, S);
  Expect(S = 'h2', 'open-content');
  CloseFile(F);
  Pend; Erase(F); Kept('erase');
  Expect(not FileExists(Dir + 'io_pending_error.o'), 'erase-done');
  AssignFile(F, Dir + 'io_pending_error.r');
  Pend; Rename(F, Dir + 'io_pending_error.n'); Kept('rename');
  Expect(FileExists(Dir + 'io_pending_error.n') and not FileExists(Dir + 'io_pending_error.r'), 'rename-done');
  { a failed open leaves the file closed and its own error in place }
  AssignFile(F, Dir + 'io_pending_error.no-such-file');
  Pend; Reset(F);
  Expect((IOResult <> 0) and (TTextRec(F).Mode = fmClosed), 'failed-reset');
  { a second error takes the place of the pending one }
  Pend; Write(F, 'x');
  Expect(IOResult = 103, 'second-error');
  DeleteFile(Dir + 'io_pending_error.w');
  DeleteFile(Dir + 'io_pending_error.n');
end;

procedure UntypedFiles;
var
  U: file;
  Buf: array[0..3] of AnsiChar;
  N: Integer;
begin
  AssignFile(U, Dir + 'io_pending_error.u');
  Rewrite(U, 1);
  Buf := 'ABCD';
  Pend; BlockWrite(U, Buf, 3); Kept('blockwrite');
  Pend; Expect(FilePos(U) = 3, 'filepos-value'); Kept('filepos');
  Pend; Expect(FileSize(U) = 3, 'filesize-value'); Kept('filesize');
  Pend; Seek(U, 1); Kept('seek');
  Pend; Truncate(U); Kept('truncate');
  Expect(FileSize(U) = 1, 'truncate-done');
  Pend; CloseFile(U); Kept('close-untyped');
  Expect(TFileRec(U).Mode = fmClosed, 'close-untyped-mode');
  Pend; Reset(U, 1); Kept('reset-untyped');
  Buf := '....';
  N := -1;
  Pend; BlockRead(U, Buf, 1, N); Kept('blockread');
  Expect((N = 1) and (Buf[0] = 'A'), 'blockread-value');
  Pend; Expect(Eof(U), 'eof-untyped-value'); Kept('eof-untyped');
  CloseFile(U);
  Pend; Erase(U); Kept('erase-untyped');
  Expect(not FileExists(Dir + 'io_pending_error.u'), 'erase-untyped-done');
end;

procedure TypedFiles;
var
  T: file of Integer;
  V: Integer;
begin
  AssignFile(T, Dir + 'io_pending_error.t');
  Rewrite(T);
  V := 77;
  Pend; Write(T, V); Kept('typed-write');
  CloseFile(T);
  Reset(T);
  V := -1;
  Pend; Read(T, V); Kept('typed-read');
  Expect(V = 77, 'typed-read-value');
  CloseFile(T);
  Erase(T);
end;

procedure Directories;
var
  Here, D: string;
begin
  D := Dir + 'io_pending_error.d';
  RemoveDir(D);
  Pend; MkDir(D); Kept('mkdir');
  Expect(DirectoryExists(D), 'mkdir-done');
  Here := GetCurrentDir;
  { a successful ChDir leaves the pending code as it is }
  Pend; ChDir(D); Kept('chdir');
  Expect(GetCurrentDir <> Here, 'chdir-done');
  SetCurrentDir(Here);
  Pend; RmDir(D); Kept('rmdir');
  Expect(not DirectoryExists(D), 'rmdir-done');
end;

{$IFDEF FPC}
type
  TTwo = (twoA, twoB);

{ Write of an enumeration value, which Delphi does not have }
procedure Enumeration;
var
  F: TextFile;
begin
  AssignFile(F, Dir + 'io_pending_error.e');
  Rewrite(F);
  Pend; Write(F, twoB); Kept('write-enum');
  CloseFile(F);
  Expect(Content(Dir + 'io_pending_error.e') = 'twoB', 'write-enum-content');
  Erase(F);
end;

{ a text file over a stream (AssignStream), which Delphi does not have }
procedure StreamText;
var
  F: TextFile;
  M: TMemoryStream;
begin
  M := TMemoryStream.Create;
  AssignStream(F, M);
  Rewrite(F);
  Pend; Writeln(F, 'x'); Kept('stream-writeln');
  Pend; Flush(F); Kept('stream-flush');
  Pend; CloseFile(F); Kept('stream-close');
  Expect(M.Size = 1 + Length(sLineBreak), 'stream-content');
  M.Free;
end;
{$ENDIF}

begin
  Dir := ExtractFilePath(ParamStr(0));
  TextFiles;
  UntypedFiles;
  TypedFiles;
  Directories;
  {$IFDEF FPC}
  Enumeration;
  StreamText;
  {$ENDIF}
  { the console: the verdict is written with an error pending, and a write
    that reaches the file leaves it pending }
  Pend;
  Write('IO_PENDING_ERROR_');
  Flush(Output);
  Kept('console');
  Pend;
  If Fails = '' then
    Writeln('OK')
  else
    Writeln('FAIL', Fails);
end.
