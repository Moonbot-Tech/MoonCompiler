{ %OPT=-O3 }
program tmoontextpointer1;
{$ifdef FPC}{$mode delphiunicode}{$endif}

uses
{$if defined(FPC) and defined(UNIX) and defined(MOONCOMPILER_VANILLA_RUNTIME)}
  { Only the explicitly vanilla IDE profile needs its own Unicode manager. }
  cwstring,
{$endif}
  SysUtils, Classes;

type
  TWidePointer = type PWideChar;
const
  NewLine: UnicodeString = sLineBreak;
  { UTF-8 bytes of the complete output, including field padding. }
  Expected: array[0..62] of Byte = (
    97,115,99,105,105,124,97,206,169,122,124,97,206,169,122,124,
    97,206,169,122,124,97,206,169,122,124,124,
    32,32,32,32,32,124,32,32,32,32,32,124,
    32,32,32,32,32,124,32,32,32,32,32,124,
    32,32,97,98,99,124,97,206,169,122,13,10);
var
  Calls, I, BodyLength: Integer;
  Wide, EmptyUnicode: UnicodeString;
  EmptyWide: WideString;
  EmptyBuffer: array[0..0] of WideChar;
  Narrow: AnsiString;
  F: TextFile;
  Actual: array of Byte;
  Stream: TFileStream;
  R: record
    P: PWideChar;
  end;

function NextPointer: PWideChar;
begin
  Inc(Calls);
  Result := PWideChar(Wide);
end;

begin
  Wide := 'a' + WideChar($03a9) + 'z'#0'ignored';
  Narrow := 'ascii'#0'ignored';
  EmptyUnicode := '';
  EmptyWide := '';
  EmptyBuffer[0] := #0;
  R.P := PWideChar(Wide);
  AssignFile(F, 'textpointer.tmp');
  Rewrite(F);
  try
    SetTextCodePage(F, 65001);
    Write(F, PAnsiChar(Narrow), '|');
    Write(F, R.P, '|');
    Write(F, NextPointer, '|');
    Write(F, TWidePointer(R.P):1, '|');
    Write(F, PChar(Wide), '|');
    Write(F, PWideChar(nil), '|');
    Write(F, PWideChar(nil):5, '|');
    Write(F, EmptyUnicode:5, '|');
    Write(F, EmptyWide:5, '|');
    Write(F, PWideChar(@EmptyBuffer[0]):5, '|');
    Write(F, PWideChar('abc'):5, '|');
    try
      Inc(Calls);
    finally
      WriteLn(F, NextPointer);
    end;
  finally
    CloseFile(F);
  end;
  try
    { Check the actual bytes, not a readback through the same text decoder. }
    Stream := TFileStream.Create('textpointer.tmp', fmOpenRead);
    try
      SetLength(Actual, Stream.Size);
      if Length(Actual) > 0 then
        Stream.ReadBuffer(Actual[0], Length(Actual));
    finally
      Stream.Free;
    end;
    BodyLength := Length(Expected) - 2;
    if (Length(Actual) <> BodyLength + Length(NewLine)) or (Calls <> 3) then
      Halt(1);
    for I := 0 to BodyLength - 1 do
      if Actual[I] <> Expected[I] then
        Halt(2);
    for I := 1 to Length(NewLine) do
      if Actual[BodyLength + I - 1] <> Ord(NewLine[I]) then
        Halt(3);
  finally
    DeleteFile('textpointer.tmp');
  end;
  Writeln('ok');
end.
