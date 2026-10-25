program ProcessOutputContract;

{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes,
  {$IFDEF UNIT_NAMESPACED}
  Pipes, System.Process
    {$IFDEF UNIT_UNICODE}, System.Process.Unicode{$ENDIF}
  {$ELSE}
  Pipes, Process
    {$IFDEF UNIT_UNICODE}, ProcessUnicode{$ENDIF}
  {$ENDIF};

type
  ESinkFailure = class(Exception);

  TWriteProbeStream = class(TMemoryStream)
  public
    Mode, Calls: Integer;
    Failure: ESinkFailure;
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

  TObservedProcess = class(TProcess)
  public
    Handshake, MarkFirstByte, FailAfterRead, FailOnFinished: Boolean;
    ReadCalls, SuccessfulReads, IdleCalls, FinishedCalls, ExceptionCalls: Integer;
    constructor Create(AOwner: TComponent); override;
    function ReadInputStream(P: TInputPipeStream; var BytesRead, DataLength: Integer;
      var Data: string; MaxLoops: Integer = 10): Boolean; override;
    procedure Event(Sender, Context: TObject; Status: TRunCommandEventCode; const Message: string);
  end;

var
  Constructors, VirtualReads: Integer;

procedure Check(Value: Boolean; const Detail: string);
begin
  If not Value then
    raise Exception.Create(Detail);
end;

procedure EqualText(const Actual, Expected, Detail: string);
begin
  Check(Actual = Expected, Detail + ': length=' + IntToStr(Length(Actual)) +
    ' expected=' + IntToStr(Length(Expected)));
end;

function Utf8Text: string;
begin
  Result := 'A' + #$0416 + #$4E2D + #$D83D + #$DE42 + 'Z';
end;

function BinaryData(Count: Integer): RawByteString;
var I: Integer;
begin
  SetLength(Result, Count);
  for I := 1 to Count do
    Result[I] := AnsiChar((I * 73 + 19) and 255);
end;

function ChildBytes(const Mode: string): RawByteString;
begin
  If Mode = 'ascii' then Result := 'MoonBot!'
  else If Mode = 'even' then Result := 'ABCD'
  else If Mode = 'utf8' then Result := UTF8Encode(Utf8Text)
  else If Mode = 'nul' then Result := UTF8Encode('A' + #0 + Utf8Text + #0 + 'B')
  else If Mode = 'binary' then Result := BinaryData(777)
  else If Mode = 'binary-large' then Result := BinaryData(20003)
  else If Mode = 'stream-large' then Result := BinaryData(4097)
  else If Mode = 'staged' then Result := BinaryData(1 + 3 + 4099 + 65537 + 7)
  else If Mode = 'marker' then Result := 'abc'
  else If Mode = 'cp1251' then Result := 'A' + #$C6 + #$FF + 'Z'
  else If Mode = 'cwd' then Result := UTF8Encode(GetCurrentDir)
  else Result := '';
end;

procedure WriteRaw(Handle: THandle; const Data: RawByteString);
var Written, N: Integer;
begin
  Written := 0;
  while Written < Length(Data) do begin
    N := FileWrite(Handle, Data[Written + 1], Length(Data) - Written);
    If N <= 0 then Halt(91);
    Inc(Written, N);
  end;
end;

procedure WaitAck;
var B: Byte;
begin
  If FileRead(TTextRec(Input).Handle, B, 1) <> 1 then Halt(92);
end;

procedure Child;
const Sizes: array[0..4] of Integer = (1, 3, 4099, 65537, 7);
var Mode: string; Data: RawByteString; I, Offset: Integer;
begin
  Mode := ParamStr(2);
  If Mode = 'split' then begin
    Data := ChildBytes('utf8');
    for I := 1 to Length(Data) do begin
      WriteRaw(TTextRec(Output).Handle, Copy(Data, I, 1));
      WaitAck;
    end;
  end else If (Mode = 'staged') or (Mode = 'staged-err') then begin
    Data := ChildBytes('staged');
    Offset := 1;
    for I := Low(Sizes) to High(Sizes) do begin
      If Mode = 'staged' then
        WriteRaw(TTextRec(Output).Handle, Copy(Data, Offset, Sizes[I]))
      else
        WriteRaw(TTextRec(StdErr).Handle, Copy(Data, Offset, Sizes[I]));
      Inc(Offset, Sizes[I]);
      WaitAck;
    end;
  end else If Mode = 'large-both' then begin
    for I := 1 to 96 do begin
      WriteRaw(TTextRec(Output).Handle, RawByteString(StringOfChar('o', 4097)));
      WriteRaw(TTextRec(StdErr).Handle, RawByteString(StringOfChar('e', 4099)));
    end;
  end else If Mode = 'stderr-only' then
    WriteRaw(TTextRec(StdErr).Handle, 'ERR' + #0 + 'tail')
  else If Mode = 'stderr-waits-ack' then begin
    WriteRaw(TTextRec(StdErr).Handle, 'ERR' + #0 + 'tail');
    WaitAck;
  end else If Mode = 'binary-merged' then begin
    WriteRaw(TTextRec(Output).Handle, BinaryData(333));
    WriteRaw(TTextRec(StdErr).Handle, BinaryData(444));
  end
  else If Mode = 'stderr-utf8' then
    WriteRaw(TTextRec(StdErr).Handle, ChildBytes('utf8'))
  else If Mode = 'merged' then begin
    WriteRaw(TTextRec(Output).Handle, 'OUT:');
    WriteRaw(TTextRec(StdErr).Handle, 'ERR');
  end else If Mode = 'channels' then begin
    WriteRaw(TTextRec(Output).Handle, 'OUT12345');
    WriteRaw(TTextRec(StdErr).Handle, 'ERR!');
  end else If Mode = 'delay' then begin
    Sleep(120);
    WriteRaw(TTextRec(Output).Handle, ChildBytes('ascii'));
  end else begin
    WriteRaw(TTextRec(Output).Handle, ChildBytes(Mode));
  end;
  If ParamCount >= 3 then Halt(StrToInt(ParamStr(3)));
  Halt(0);
end;

constructor TObservedProcess.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Inc(Constructors);
end;

function TObservedProcess.ReadInputStream(P: TInputPipeStream; var BytesRead, DataLength: Integer;
  var Data: string; MaxLoops: Integer): Boolean;
var Before: Integer; B: Byte;
begin
  Inc(ReadCalls);
  Inc(VirtualReads);
  Before := BytesRead;
  Result := inherited ReadInputStream(P, BytesRead, DataLength, Data, MaxLoops);
  If BytesRead > Before then begin
    Inc(SuccessfulReads);
    If MarkFirstByte and (Before = 0) and (P = Output) then
      Data[1] := 'Z';
    If Handshake and (P = Output) then begin
      B := 1;
      Check(Input.Write(B, 1) = 1, 'handshake write');
    end;
    If FailAfterRead then
      raise Exception.Create('intentional read callback failure');
  end;
end;

procedure TObservedProcess.Event(Sender, Context: TObject; Status: TRunCommandEventCode;
  const Message: string);
begin
  Check(Sender = Self, 'callback sender');
  Check(Context = nil, 'callback context');
  case Status of
    RunCommandIdle: begin
      Inc(IdleCalls);
      Sleep(1);
    end;
    RunCommandFinished: begin
      Inc(FinishedCalls);
      If FailOnFinished then raise Exception.Create('intentional finished callback failure');
    end;
    RunCommandException: begin
      Inc(ExceptionCalls);
      Check(Message <> '', 'exception callback has message');
    end;
  end;
end;

procedure Setup(P: TProcess; const Mode: string);
begin
  P.Executable := ParamStr(0);
  P.Parameters.Clear;
  P.Parameters.Add('--child');
  P.Parameters.Add(Mode);
end;

procedure WaitData(P: TProcess; Stream: TInputPipeStream; Count: Integer = 1);
var Deadline: QWord;
begin
  Deadline := GetTickCount64 + 3000;
  while Stream.NumBytesAvailable < Count do begin
    Check(GetTickCount64 < Deadline, 'pipe data timeout');
    Sleep(1);
  end;
end;

procedure WaitDone(P: TProcess);
begin
  Check(P.WaitOnExit(3000), 'child exit timeout');
  Check(P.ExitCode = 0, 'child exit status=' + IntToStr(P.ExitCode));
end;

function StreamBytes(M: TMemoryStream): RawByteString;
begin
  SetLength(Result, M.Size);
  If M.Size > 0 then Move(M.Memory^, Result[1], M.Size);
end;

function TWriteProbeStream.Write(const Buffer; Count: Longint): Longint;
begin
  Inc(Calls);
  case Mode of
    0: Result := inherited Write(Buffer, 1);
    1: Result := 0;
    2: raise Failure;
  else
    raise Exception.Create('unknown write probe mode');
  end;
end;

procedure CheckByteUnits(const Data: string; Count: Integer; const Expected: RawByteString);
var I: Integer;
begin
  Check(Count = Length(Expected), 'legacy byte counter');
  Check(Length(Data) >= Count, 'legacy capacity');
  for I := 1 to Count do
    Check(Ord(Data[I]) = Byte(Expected[I]), 'legacy byte unit at ' + IntToStr(I));
end;

procedure ApiCase(const Name: string);
var S, Cmd, Dir: string; Status, RC: Integer; OK: Boolean;
begin
  Cmd := '"' + ParamStr(0) + '" --child ascii';
  Dir := ExtractFilePath(ParamStr(0));
  If Name = 'api-array' then
    OK := RunCommand(ParamStr(0), ['--child', 'ascii'], S)
  else If Name = 'api-cmdline' then
    OK := RunCommand(Cmd, S)
  else If Name = 'api-indir' then begin
    OK := RunCommandInDir(Dir, ParamStr(0), ['--child', 'cwd'], S);
    EqualText(S, ExcludeTrailingPathDelimiter(Dir), 'working directory');
    Check(OK, Name);
    Exit;
  end else If Name = 'api-indir-cmdline' then
    OK := RunCommandInDir(Dir, Cmd, S)
  else If Name = 'api-indir-exit' then begin
    RC := RunCommandInDir(Dir, ParamStr(0), ['--child', 'ascii', '37'], S, Status);
    Check(RC = 0, 'integer wrapper result');
    Check(Status <> 0, 'integer wrapper child exit');
    {$IFDEF WINDOWS}Check(Status = 37, 'Windows child exit value');{$ENDIF}
    EqualText(S, 'MoonBot!', 'integer wrapper text');
    Exit;
  end else If Name = 'api-forbidden-options' then
    OK := RunCommand(ParamStr(0), ['--child', 'ascii'], S, [poWaitOnExit, poRunSuspended])
  else If Name = 'api-merged' then begin
    OK := RunCommand(ParamStr(0), ['--child', 'merged'], S, [poStderrToOutput]);
    Check(OK, 'merged wrapper return');
    EqualText(S, 'OUT:ERR', 'merged wrapper text');
    Exit;
  end
  else If Name = 'api-nonzero' then begin
    OK := RunCommand(ParamStr(0), ['--child', 'ascii', '37'], S);
    Check(not OK, 'nonzero exit must return false');
    EqualText(S, 'MoonBot!', 'nonzero exit retains output');
    Exit;
  end else If Name = 'api-missing' then begin
    OK := RunCommand(ParamStr(0) + '.missing', [], S);
    Check(not OK, 'missing executable must return false');
    EqualText(S, '', 'missing executable output');
    Exit;
  end else If Name = 'api-indir-missing' then begin
    Status := -99;
    RC := RunCommandInDir(Dir, ParamStr(0) + '.missing', [], S, Status);
    Check(RC = 1, 'integer wrapper launch failure result');
    Check(Status = -1, 'integer wrapper launch failure exitstatus');
    EqualText(S, '', 'integer wrapper launch failure output');
    Exit;
  end else raise Exception.Create('unknown API case');
  Check(OK, Name + ' return');
  EqualText(S, 'MoonBot!', Name + ' text');
end;

procedure LoopCase(const Name: string);
var P: TObservedProcess; S, E, Expected, Mode: string; RC, Status: Integer;
begin
  P := TObservedProcess.Create(nil);
  try
    Mode := Copy(Name, 6, MaxInt);
    If Mode = 'ascii' then Expected := 'MoonBot!'
    else If Mode = 'even' then Expected := 'ABCD'
    else If (Mode = 'utf8') or (Mode = 'split') then Expected := Utf8Text
    else If Mode = 'nul' then Expected := 'A' + #0 + Utf8Text + #0 + 'B'
    else If Mode = 'virtual' then begin Mode := 'marker'; Expected := 'Zbc'; P.MarkFirstByte := True; end
    else If Mode = 'callback' then begin Mode := 'delay'; Expected := 'MoonBot!'; end
    else If Mode = 'exception' then begin Mode := 'utf8'; Expected := Utf8Text; P.FailAfterRead := True; end
    else If Mode = 'finished-failure' then begin
      Mode := 'utf8'; Expected := Utf8Text; P.FailOnFinished := True;
    end
    else Expected := '';
    Setup(P, Mode);
    P.Options := [poRunIdle];
    P.OnRunCommandEvent := P.Event;
    P.Handshake := Mode = 'split';
    If Mode = 'merged' then P.Options := P.Options + [poStderrToOutput];
    If Mode = 'missing' then P.Executable := ParamStr(0) + '.missing';
    S := 'stale stdout';
    E := 'stale stderr';
    Status := -99;
    RC := P.RunCommandLoop(S, E, Status);
    If (Mode = 'missing') or P.FailAfterRead or P.FailOnFinished then begin
      Check(RC = 1, 'loop error return');
      Check(P.ExceptionCalls = 1, 'exception callback once');
      Check(P.FinishedCalls = Ord(P.FailOnFinished), 'finished callback on error');
      If Mode = 'missing' then Check(Status = -1, 'launch failure exitstatus');
      EqualText(S, Expected, 'loop partial output on error');
      Exit;
    end;
    Check(RC = 0, 'loop return=' + IntToStr(RC));
    Check(Status = 0, 'loop child status');
    Check(P.FinishedCalls = 1, 'finished callback once');
    Check(P.ExceptionCalls = 0, 'unexpected exception callback');
    If Mode = 'large-both' then begin
      EqualText(S, StringOfChar('o', 96 * 4097), 'large stdout');
      EqualText(E, StringOfChar('e', 96 * 4099), 'large stderr');
    end else If Mode = 'stderr-only' then begin
      EqualText(S, '', 'stderr-only stdout');
      EqualText(E, 'ERR' + #0 + 'tail', 'stderr-only text');
    end else If Mode = 'stderr-utf8' then begin
      EqualText(S, '', 'UTF8 stderr-only stdout');
      EqualText(E, Utf8Text, 'UTF8 stderr');
    end else If Mode = 'merged' then begin
      EqualText(S, 'OUT:ERR', 'merged channels');
      EqualText(E, '', 'merged stderr empty');
    end else begin
      EqualText(S, Expected, Name);
      EqualText(E, '', 'unused stderr');
    end;
    If Mode = 'split' then Check(P.SuccessfulReads >= Length(ChildBytes('utf8')), 'split handshake reads');
    If Mode = 'delay' then Check(P.IdleCalls > 0, 'idle callback exercised');
    If Mode = 'marker' then Check(P.ReadCalls > 0, 'legacy virtual overload dispatched');
    If Mode = 'reuse' then begin
      Setup(P, 'ascii');
      Check(P.RunCommandLoop(S, E, Status) = 0, 'reuse second start');
      EqualText(S, 'MoonBot!', 'reuse second output');
      Setup(P, 'empty');
      Check(P.RunCommandLoop(S, E, Status) = 0, 'reuse empty third start');
      EqualText(S, '', 'reuse clears previous stdout');
      EqualText(E, '', 'reuse clears previous stderr');
      Check(P.FinishedCalls = 3, 'reuse finished callbacks');
    end;
  finally
    P.Free;
  end;
end;

procedure StreamCase(const Name: string);
var P: TProcess; M, Other: TMemoryStream; Mode: string; Expected, Seed: RawByteString;
  Got: Boolean; St: TInputPipeStream; Before: Integer; B: Byte;
begin
  P := TProcess.Create(nil);
  M := TMemoryStream.Create;
  Other := TMemoryStream.Create;
  try
    Mode := 'binary';
    If Name = 'stream-stderr' then Mode := 'channels';
    If Name = 'stream-stderr-only' then Mode := 'stderr-only';
    If Name = 'stream-blocking-channel' then Mode := 'stderr-waits-ack';
    If Name = 'stream-merged' then Mode := 'binary-merged';
    If Name = 'stream-partial' then Mode := 'stream-large';
    If Name = 'stream-empty' then Mode := 'empty';
    Setup(P, Mode);
    P.Options := [poUsePipes];
    If Mode = 'binary-merged' then P.Options := P.Options + [poStderrToOutput];
    P.PipeBufferSize := 65536;
    P.Execute;
    If Mode = 'stream-large' then WaitData(P, P.Output, 4097)
    else If Mode = 'stderr-waits-ack' then WaitData(P, P.StdErr)
    else WaitDone(P);
    St := P.Output;
    Expected := ChildBytes(Mode);
    If Mode = 'channels' then begin
      St := P.StdErr;
      Expected := 'ERR!';
    end;
    If (Mode = 'stderr-only') or (Mode = 'stderr-waits-ack') then begin
      St := P.StdErr;
      Expected := 'ERR' + #0 + 'tail';
    end;
    If Mode = 'binary-merged' then Expected := BinaryData(333) + BinaryData(444);
    If Name = 'stream-append' then begin
      Seed := 'prefix' + #0;
      M.WriteBuffer(Seed[1], Length(Seed));
    end else Seed := '';
    If Name = 'stream-zero-loops' then begin
      Before := St.NumBytesAvailable;
      P.ReadInputStream(St, M, 0);
      Check(M.Size = 0, 'MaxLoops=0 no stream mutation');
      Check(St.NumBytesAvailable = Before, 'MaxLoops=0 no pipe consumption');
    end;
    Got := P.ReadInputStream(St, M, 1);
    If Mode = 'stderr-waits-ack' then begin
      B := 1;
      Check(P.Input.Write(B, 1) = 1, 'stderr read ACK');
      WaitDone(P);
    end;
    Check(Got = (Length(Expected) > 0), 'stream availability result');
    If Name = 'stream-partial' then begin
      Check(M.Size = 4096, 'stream MaxLoops=1 bounded read');
      Check(P.ReadInputStream(St, M, 1), 'stream second partial read');
      WaitDone(P);
    end;
    Check(StreamBytes(M) = Seed + Expected, 'exact stream bytes');
    Check(not P.ReadInputStream(St, M), 'exhausted stream false');
    If Mode = 'channels' then begin
      Check(P.Output.NumBytesAvailable = 8, 'stderr read preserves stdout');
      Check(P.ReadInputStream(P.Output, Other), 'stdout remains readable');
      Check(StreamBytes(Other) = 'OUT12345', 'stdout exact channel');
    end;
  finally
    Other.Free;
    M.Free;
    P.Free;
  end;
end;

procedure SinkCase(const Name: string);
var P: TProcess; Sink: TWriteProbeStream; Failure: ESinkFailure;
  Returned, Got, Caught: Boolean; Expected: RawByteString;
begin
  P := TProcess.Create(nil);
  Sink := TWriteProbeStream.Create;
  Failure := nil;
  try
    If Name = 'stream-zero-write' then Sink.Mode := 1;
    If Name = 'stream-throw-write' then begin
      Sink.Mode := 2;
      Failure := ESinkFailure.Create('original sink failure');
      Sink.Failure := Failure;
    end;
    Setup(P, 'binary');
    P.Options := [poUsePipes];
    P.Execute;
    WaitDone(P);
    Returned := False;
    Got := False;
    Caught := False;
    try
      Got := P.ReadInputStream(P.Output, Sink, 1);
      Returned := True;
    except
      on E: ESinkFailure do begin
        Check(Sink.Mode = 2, 'unexpected sink exception');
        Check(E = Failure, 'original exception object preserved');
        Failure := nil;
        Check(E.Message = 'original sink failure', 'original exception message preserved');
        Caught := True;
      end;
      on E: EWriteError do begin
        Check(Sink.Mode = 1, 'unexpected EWriteError');
        Caught := True;
      end;
    end;
    If Sink.Mode = 0 then begin
      Expected := ChildBytes('binary');
      Check(Returned and Got and not Caught, 'partial-progress sink completes');
      Check(StreamBytes(Sink) = Expected, 'partial-progress sink exact bytes');
      Check(Sink.Calls = Length(Expected), 'partial-progress sink retries without lost bytes');
    end else begin
      Check(Caught and not Returned, 'failed sink cannot return success');
      Check(Sink.Size = 0, 'failed sink accepted no bytes');
      Check(Sink.Calls = 1, 'failed sink stops after first failed write');
    end;
  finally
    Failure.Free;
    Sink.Free;
    P.Free;
  end;
end;

{$IFDEF PROCESS_CODEPAGE}
procedure EncodingCase(const Name: string);
var P: TProcess; S, E: string; Status: Integer; SavedCodePage: TSystemCodePage;
begin
  SavedCodePage := DefaultSystemCodePage;
  If (Name = 'encoding-default') or (Name = 'encoding-override') then DefaultSystemCodePage := 1251;
  P := TProcess.Create(nil);
  try
    If Name = 'encoding-override' then begin
      Check(P.OutputCodePage = 1251, 'override starts with system CP1251');
      P.OutputCodePage := CP_UTF8;
      Setup(P, 'utf8');
      Check(P.RunCommandLoop(S, E, Status) = 0, 'explicit UTF8 over system CP1251');
      EqualText(S, Utf8Text, 'property overrides global system codepage');
      Exit;
    end;
    If Name = 'encoding-default' then
      Check(P.OutputCodePage = DefaultSystemCodePage, 'default output code page')
    else P.OutputCodePage := 1251;
    Setup(P, 'cp1251');
    Check(P.RunCommandLoop(S, E, Status) = 0, 'CP1251 run');
    EqualText(S, 'A' + #$0416 + #$044F + 'Z', 'explicit/default CP1251 text');
    If Name = 'encoding-reuse' then begin
      P.OutputCodePage := CP_UTF8;
      Setup(P, 'utf8');
      Check(P.RunCommandLoop(S, E, Status) = 0, 'UTF8 reuse run');
      EqualText(S, Utf8Text, 'UTF8 property after CP1251 reuse');
    end;
  finally
    P.Free;
    DefaultSystemCodePage := SavedCodePage;
  end;
end;
{$ENDIF}

procedure BufferCase(const Name: string);
const Sizes: array[0..4] of Integer = (1, 3, 4099, 65537, 7);
var P: TProcess; Data, Alias: string; Raw, Prefix: RawByteString;
  Count, Capacity, Before, Stage, Target, I: Integer; B: Byte;
  St: TInputPipeStream; Mode: string; Deadline: QWord;
begin
  P := TProcess.Create(nil);
  try
    Mode := 'binary';
    If Name = 'buffer-staged' then Mode := 'staged';
    If Name = 'buffer-stderr-staged' then Mode := 'staged-err';
    If Name = 'buffer-empty' then Mode := 'empty';
    Setup(P, Mode);
    P.Options := [poUsePipes];
    P.PipeBufferSize := 4096;
    P.Execute;
    St := P.Output;
    If Mode = 'staged-err' then St := P.StdErr;
    Data := '';
    Count := 0;
    Capacity := 0;
    Prefix := '';
    If (Name = 'buffer-prefix') or (Name = 'buffer-alias') then begin
      Prefix := 'AB' + #0;
      Capacity := 1024;
      SetLength(Data, Capacity);
      for I := 1 to Length(Prefix) do Data[I] := Char(Byte(Prefix[I]));
      Count := Length(Prefix);
      If Name = 'buffer-alias' then Alias := Data;
    end;
    If (Mode = 'staged') or (Mode = 'staged-err') then begin
      Target := 0;
      Raw := '';
      for Stage := Low(Sizes) to High(Sizes) do begin
        Inc(Target, Sizes[Stage]);
        Deadline := GetTickCount64 + 3000;
        while Count < Target do begin
          Check(GetTickCount64 < Deadline, 'staged buffer timeout');
          If St.NumBytesAvailable = 0 then begin Sleep(1); Continue; end;
          Before := Count;
          Check(P.ReadInputStream(St, Count, Capacity, Data, 1), 'staged read flag');
          Check(Count > Before, 'staged progress');
          Check(Capacity >= Count, 'staged byte capacity');
          Raw := Copy(ChildBytes('staged'), 1, Count);
          CheckByteUnits(Data, Count, Raw);
        end;
        B := 1;
        Check(P.Input.Write(B, 1) = 1, 'staged ACK');
      end;
      WaitDone(P);
    end else begin
      WaitDone(P);
      Raw := ChildBytes(Mode);
      If Name = 'buffer-zero-loops' then begin
        Before := St.NumBytesAvailable;
        P.ReadInputStream(St, Count, Capacity, Data, 0);
        Check(Count = 0, 'zero loops no byte increment');
        Check(Capacity = 0, 'zero loops no capacity growth');
        Check(St.NumBytesAvailable = Before, 'zero loops no consumption');
      end;
      Check(P.ReadInputStream(St, Count, Capacity, Data, 1) = (Raw <> ''), 'buffer read flag');
      CheckByteUnits(Data, Count, Prefix + Raw);
      If Alias <> '' then begin
        for I := 1 to Length(Prefix) do
          Check(Alias[I] = Char(Byte(Prefix[I])), 'shared buffer prefix unchanged');
        Check(Alias[Length(Prefix) + 1] = #0, 'shared buffer tail unchanged');
      end;
    end;
    Before := Count;
    Check(not P.ReadInputStream(St, Count, Capacity, Data), 'empty buffer read false');
    Check(Count = Before, 'empty buffer preserves byte count');
  finally
    P.Free;
  end;
end;

procedure DefaultClassCase;
var Saved: TProcessClass; S: string; I, Status, Before: Integer; OK: Boolean;
begin
  Saved := DefaultTProcess;
  DefaultTProcess := TObservedProcess;
  try
    Constructors := 0;
    VirtualReads := 0;
    for I := 0 to 4 do begin
      Before := VirtualReads;
      case I of
        0: OK := RunCommand(ParamStr(0), ['--child', 'ascii'], S);
        1: OK := RunCommand('"' + ParamStr(0) + '" --child ascii', S);
        2: OK := RunCommandInDir('', ParamStr(0), ['--child', 'ascii'], S);
        3: OK := RunCommandInDir('', '"' + ParamStr(0) + '" --child ascii', S);
        4: OK := RunCommandInDir('', ParamStr(0), ['--child', 'ascii'], S, Status) = 0;
      end;
      Check(OK, 'DefaultTProcess wrapper result');
      EqualText(S, 'MoonBot!', 'DefaultTProcess wrapper text');
      Check(VirtualReads > Before, 'DefaultTProcess read override dispatched #' + IntToStr(I));
    end;
    Check(Constructors = 5, 'all wrappers instantiate DefaultTProcess');
  finally
    DefaultTProcess := Saved;
  end;
end;

var Name: string;
begin
  If ParamStr(1) = '--child' then Child;
  try
    Check(SizeOf(Char) = 2, 'test must run Unicode RTL');
    DefaultSystemCodePage := CP_UTF8;
    Name := ParamStr(1);
    If Copy(Name, 1, 4) = 'api-' then ApiCase(Name)
    else If Copy(Name, 1, 5) = 'loop-' then LoopCase(Name)
    else If (Name = 'stream-short-write') or (Name = 'stream-zero-write') or (Name = 'stream-throw-write') then
      SinkCase(Name)
    else If Copy(Name, 1, 7) = 'stream-' then StreamCase(Name)
    else If Copy(Name, 1, 7) = 'buffer-' then BufferCase(Name)
    else If Name = 'default-class' then DefaultClassCase
    {$IFDEF PROCESS_CODEPAGE}
    else If Copy(Name, 1, 9) = 'encoding-' then EncodingCase(Name)
    {$ENDIF}
    else raise Exception.Create('unknown test: ' + Name);
    Writeln('PASS ', Name);
  except
    on E: Exception do begin
      Writeln('FAIL ', ParamStr(1), ': ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
