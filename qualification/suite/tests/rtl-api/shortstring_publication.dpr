program shortstring_publication;

{$mode delphiunicode}
{$optimization noautoinline}

uses
  {$ifdef unix}cthreads, cwstring,{$endif}
  Classes, SysUtils, SyncObjs;

type
  TOne = string[1];
  TFive = string[5];
  TWriter = class(TThread)
    procedure Execute; override;
  end;
  TReader = class(TThread)
    procedure Execute; override;
  end;

var
  One: TOne;
  Five, First, Last: TFive;
  Prior, Probe: TUnicodeStringManager;
  InspectOne: Boolean;
  Calls, Failed, Stop: LongInt;
  WriterReady, ReadNow, ReadDone: TEvent;

procedure Check(Ok: Boolean; const Why: string);
begin
  If not Ok then begin
    Writeln('FAIL ', Why);
    Halt(1);
  end;
end;

procedure TReader.Execute;
var
  S: TFive;
  U: UnicodeString;
begin
  while ReadNow.WaitFor(High(Cardinal)) = wrSignaled do begin
    If Terminated then Exit;
    If InspectOne then begin
      S := One;
      U := One;
    end else begin
      S := Five;
      U := Five;
    end;
    If (S <> First) or (U <> UnicodeString(First)) then Inc(Failed);
    ReadDone.SetEvent;
  end;
end;

procedure Observe;
begin
  Inc(Calls);
  ReadNow.SetEvent;
  Check(ReadDone.WaitFor(5000) = wrSignaled, 'reader observed pending conversion');
end;

procedure FromUnicode(P: PUnicodeChar; var Dest: RawByteString; CP: TSystemCodePage; Len: SizeInt);
begin
  Observe;
  Prior.Unicode2AnsiMoveProc(P, Dest, CP, Len);
end;

procedure FromWide(P: PWideChar; var Dest: RawByteString; CP: TSystemCodePage; Len: SizeInt);
begin
  Observe;
  Prior.Wide2AnsiMoveProc(P, Dest, CP, Len);
end;

procedure CheckConversion(Kind: Integer; const OldValue, NewValue: TFive);
var
  U: UnicodeString;
  W: WideString;
  P: PWideChar;
  S: TFive;
begin
  First := OldValue;
  U := NewValue;
  W := U;
  P := PWideChar(U);
  Calls := 0;
  Failed := 0;
  If InspectOne then One := OldValue else Five := OldValue;
  SetUnicodeStringManager(Probe);
  try
    If InspectOne then
      case Kind of
        0: One := U;
        1: One := W;
        2: One := P;
      end
    else
      case Kind of
        0: Five := U;
        1: Five := W;
        2: Five := P;
      end;
  finally
    SetUnicodeStringManager(Prior);
  end;
  If InspectOne then S := One else S := Five;
  Check(Calls = 1, 'conversion hook');
  Check(Failed = 0, 'old value before conversion completed');
  Check(S = NewValue, 'converted value');
end;

procedure TWriter.Execute;
begin
  Five := Last;
  WriterReady.SetEvent;
  repeat
    Five := First;
    Five := Last;
  until InterlockedCompareExchange(Stop, 0, 0) <> 0;
end;

procedure CheckSnapshot(const S: UnicodeString);
var
  I: Integer;
begin
  Check(Length(S) = Length(First), 'snapshot length');
  for I := 1 to Length(S) do
    Check((S[I] = WideChar(First[I])) or (S[I] = WideChar(Last[I])), 'unexpected snapshot byte');
end;

procedure CheckConcurrentShortCopy;
var
  Worker: TWriter;
  S: TFive;
  U: UnicodeString;
  I: Integer;
begin
  First := 'ABCDE';
  Last := '12345';
  Five := First;
  WriterReady := TEvent.Create(nil, True, False, '');
  Worker := TWriter.Create(False);
  try
    Check(WriterReady.WaitFor(5000) = wrSignaled, 'writer started');
    for I := 1 to 50000 do begin
      S := Five;
      U := Five;
      CheckSnapshot(UnicodeString(S));
      CheckSnapshot(U);
    end;
  finally
    InterlockedExchange(Stop, 1);
    Worker.WaitFor;
    Worker.Free;
    WriterReady.Free;
  end;
end;

var
  I: Integer;
  U: UnicodeString;
  W: WideString;
  P: PWideChar;
  Reader: TReader;
begin
  GetUnicodeStringManager(Prior);
  Probe := Prior;
  Probe.Unicode2AnsiMoveProc := @FromUnicode;
  Probe.Wide2AnsiMoveProc := @FromWide;
  ReadNow := TEvent.Create(nil, False, False, '');
  ReadDone := TEvent.Create(nil, False, False, '');
  Reader := TReader.Create(False);
  try
    for I := 0 to 2 do begin
      InspectOne := True;
      CheckConversion(I, 'K', 'K');
      CheckConversion(I, 'K', 'Q');
      InspectOne := False;
      CheckConversion(I, 'ABCDE', 'ABCDE');
      CheckConversion(I, 'ABCDE', '12345');
    end;
  finally
    Reader.Terminate;
    ReadNow.SetEvent;
    Reader.WaitFor;
    Reader.Free;
    ReadDone.Free;
    ReadNow.Free;
  end;
  U := '123456789';
  Five := U;
  Check(Five = '12345', 'truncation');
  U := 'A'#0'B';
  Five := U;
  Check(Five = 'A'#0'B', 'counted zero');
  U := '';
  Five := U;
  Check(Five = '', 'empty UnicodeString');
  W := '';
  Five := 'abc';
  Five := W;
  Check(Five = '', 'empty WideString');
  P := nil;
  Five := 'abc';
  Five := P;
  Check(Five = '', 'nil pointer');
  CheckConcurrentShortCopy;
  Writeln('SHORTSTRING_PUBLICATION_OK');
end.
