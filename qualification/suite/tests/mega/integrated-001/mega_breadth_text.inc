{ A memory-backed Text file forces Read/Write syntax, buffer boundaries and
  callback ABI to interact without touching the filesystem. }

type
  TBreadthTextRec = {$ifdef FPC}TextRec{$else}TTextRec{$endif};
  PBreadthTextState = ^TBreadthTextState;
  TBreadthTextState = record
    Input, Output: AnsiString;
    Offset, Opens, BufferCalls, Closes: Integer;
    FailOpen: Boolean;
  end;

function BreadthTextState(var Rec: TBreadthTextRec): PBreadthTextState;
begin
  Move(Rec.UserData[1], Result, SizeOf(Result));
end;

{$ifdef FPC}procedure{$else}function{$endif} BreadthTextOpen(var Rec: TBreadthTextRec){$ifndef FPC}: Integer{$endif};
var
  State: PBreadthTextState;
begin
  State := BreadthTextState(Rec);
  Inc(State^.Opens);
  Rec.BufPos := 0;
  Rec.BufEnd := 0;
  If State^.FailOpen then begin
    Rec.Mode := fmClosed;
    {$ifdef FPC}InOutRes := 101;{$else}Result := 101;{$endif}
  end else begin
    State^.Offset := 0;
    {$ifndef FPC}Result := 0;{$endif}
  end;
end;

{$ifdef FPC}procedure{$else}function{$endif} BreadthTextClose(var Rec: TBreadthTextRec){$ifndef FPC}: Integer{$endif};
begin
  Inc(BreadthTextState(Rec)^.Closes);
  Rec.Mode := fmClosed;
  {$ifndef FPC}Result := 0;{$endif}
end;

{$ifdef FPC}procedure{$else}function{$endif} BreadthTextBuffer(var Rec: TBreadthTextRec){$ifndef FPC}: Integer{$endif};
var
  State: PBreadthTextState;
  Count, OldLength: Integer;
begin
  State := BreadthTextState(Rec);
  Inc(State^.BufferCalls);
  If Rec.Mode = fmInput then begin
    Count := Length(State^.Input) - State^.Offset;
    If Count > Integer(Rec.BufSize) then
      Count := Integer(Rec.BufSize);
    If Count > 0 then begin
      Move(State^.Input[State^.Offset + 1], PAnsiChar(Rec.BufPtr)^, Count);
      Inc(State^.Offset, Count);
    end;
    Rec.BufEnd := Count;
  end else begin
    Count := Integer(Rec.BufPos);
    If Count > 0 then begin
      OldLength := Length(State^.Output);
      SetLength(State^.Output, OldLength + Count);
      Move(PAnsiChar(Rec.BufPtr)^, State^.Output[OldLength + 1], Count);
    end;
  end;
  Rec.BufPos := 0;
  {$ifndef FPC}Result := 0;{$endif}
end;

procedure BreadthPrepareText(var F: Text; var State: TBreadthTextState);
var
  Link: PBreadthTextState;
begin
  AssignFile(F, '');
  TBreadthTextRec(F).BufSize := 5;
  TBreadthTextRec(F).OpenFunc := @BreadthTextOpen;
  TBreadthTextRec(F).CloseFunc := @BreadthTextClose;
  TBreadthTextRec(F).InOutFunc := @BreadthTextBuffer;
  TBreadthTextRec(F).FlushFunc := @BreadthTextBuffer;
  Link := @State;
  Move(Link, TBreadthTextRec(F).UserData[1], SizeOf(Link));
end;

procedure RunBreadthTextRound;
var
  F: Text;
  State: TBreadthTextState;
  First, Last: Int64;
  Second: Integer;
begin
  State := Default(TBreadthTextState);
  State.Input := AnsiString('-9223372036854775807 173'#10'  50190000003  '#10);
  BreadthPrepareText(F, State);
  Reset(F);
  try
    ReadLn(F, First, Second);
    ReadLn(F, Last);
    Check((First = -9223372036854775807) and (Second = 173) and (Last = 50190000003),
      'breadth-text-int-fields-span-refills');
    Check(Eof(F), 'breadth-text-eof-after-last-field');
    Check(State.BufferCalls >= 8, 'breadth-text-numbers-cross-callback-boundaries');
  finally
    CloseFile(F);
  end;
  Check((State.Opens = 1) and (State.Closes = 1), 'breadth-text-input-open-close');

  BreadthPrepareText(F, State);
  Rewrite(F);
  try
    Write(F, First:21, AnsiChar('|'), Second:4, AnsiChar('|'), Last:14);
    Flush(F);
    Check(State.Output = AnsiString(' -9223372036854775807| 173|   50190000003'),
      'breadth-text-formatted-output-across-buffer-boundaries');
    Write(F, AnsiChar('!'));
  finally
    CloseFile(F);
  end;
  Check((State.Opens = 2) and (State.Closes = 2), 'breadth-text-output-open-close');
  Check(State.Output = AnsiString(' -9223372036854775807| 173|   50190000003!'), 'breadth-text-close-flushes-tail');
  Mix(UInt64(Length(State.Output)));
end;

procedure RunBreadthTextOpenFailure;
var
  F: Text;
  State: TBreadthTextState;
  Failure: Integer;
begin
  State := Default(TBreadthTextState);
  State.FailOpen := True;
  BreadthPrepareText(F, State);
  {$I-}
  Rewrite(F);
  {$I+}
  Failure := IOResult;
  Check((Failure = 101) and (State.Opens = 1) and (State.Closes = 0), 'breadth-text-open-error-is-pending');
  Check(IOResult = 0, 'breadth-text-ioresult-clears-error');
  State.FailOpen := False;
  Rewrite(F);
  try
    Write(F, AnsiChar('X'));
  finally
    CloseFile(F);
  end;
  Check((State.Opens = 2) and (State.Closes = 1) and (State.Output = AnsiString('X')),
    'breadth-text-reopen-after-failed-callback');
  Mix(UInt64(Failure));
end;

procedure RunBreadthTextForms;
begin
  RunBreadthTextRound;
  RunBreadthTextOpenFailure;
end;
