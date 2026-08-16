program unicode_string_assign_semantic;

{$ifdef FPC}
{$mode delphi}{$H+}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif FPC}
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$ifdef FPC}
  Classes,
  {$else FPC}
  System.Classes,
  {$endif FPC}
  SysUtils;

const
  AssignThreadCount = 4;
  AssignThreadIterations = 100000;

type
  TAssignThread = class(TThread)
  private
    FPassed: Boolean;
  protected
    procedure Execute; override;
  public
    property Passed: Boolean read FPassed;
  end;

var
  SharedText: UnicodeString;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

function HeapText(const Prefix: UnicodeString; Value: Integer): UnicodeString;
begin
  Result := Prefix + IntToStr(Value);
end;

procedure TAssignThread.Execute;
var
  I: Integer;
  LocalText: UnicodeString;
begin
  FPassed := False;
  for I := 1 to AssignThreadIterations do begin
    LocalText := SharedText;
    If LocalText <> 'shared-unicode-value-12345' then
      Exit;
    LocalText := '';
  end;
  FPassed := True;
end;

procedure CheckEmptyAndLiteral;
var
  Source: UnicodeString;
  Dest: UnicodeString;
begin
  Source := '';
  Dest := HeapText('old-', 1);
  Dest := Source;
  Check(Dest = '', 'empty source clears destination');

  Dest := HeapText('old-', 2);
  Dest := 'literal-value';
  Check(Dest = 'literal-value', 'literal assignment');
end;

procedure CheckHeapAndCopyOnWrite;
var
  Source: UnicodeString;
  Dest: UnicodeString;
begin
  Source := HeapText('source-', 12345);
  Dest := HeapText('destination-', 67890);
  Dest := Source;
  Check(Dest = 'source-12345', 'heap assignment');

  Source[1] := 'S';
  Check(Source = 'Source-12345', 'source copy-on-write mutation');
  Check(Dest = 'source-12345', 'destination survives source mutation');

  Dest[1] := 'D';
  Check(Dest = 'Dource-12345', 'destination copy-on-write mutation');
  Check(Source = 'Source-12345', 'source survives destination mutation');
end;

procedure CheckSelfAndAliasedAssignment;
var
  Source: UnicodeString;
  AliasText: UnicodeString;
begin
  Source := HeapText('self-', 17);
  Source := Source;
  Check(Source = 'self-17', 'self assignment');

  AliasText := Source;
  Source := AliasText;
  Check((Source = 'self-17') and (AliasText = 'self-17'),
    'assignment from aliased storage');

  Source := '';
  Check(AliasText = 'self-17', 'alias remains alive after source release');
end;

procedure CheckRepeatedReplacement;
var
  I: Integer;
  Source: UnicodeString;
  Dest: UnicodeString;
begin
  Dest := HeapText('initial-', 0);
  for I := 1 to 1000 do begin
    Source := HeapText('value-', I);
    Dest := Source;
  end;
  Check(Dest = 'value-1000', 'repeated replacement');
end;

procedure CheckConcurrentAssignments;
var
  I: Integer;
  Threads: array[0..AssignThreadCount - 1] of TAssignThread;
begin
  SharedText := HeapText('shared-unicode-value-', 12345);
  FillChar(Threads, SizeOf(Threads), 0);
  try
    for I := Low(Threads) to High(Threads) do
      Threads[I] := TAssignThread.Create(False);
    for I := Low(Threads) to High(Threads) do
      Threads[I].WaitFor;
    for I := Low(Threads) to High(Threads) do
      Check(Threads[I].Passed, 'concurrent assignment thread ' + IntToStr(I));
    Check(SharedText = 'shared-unicode-value-12345',
      'concurrent source remains alive');
  finally
    for I := Low(Threads) to High(Threads) do
      If Assigned(Threads[I]) then
        Threads[I].Free;
  end;
  SharedText := '';
end;

procedure CheckAssignmentSemantics;
begin
  CheckEmptyAndLiteral;
  CheckHeapAndCopyOnWrite;
  CheckSelfAndAliasedAssignment;
  CheckRepeatedReplacement;
end;

begin
  try
    CheckAssignmentSemantics;
    CheckConcurrentAssignments;
    CheckAssignmentSemantics;
    WriteLn('UNICODE_STRING_ASSIGN_OK');
  except
    on E: Exception do begin
      WriteLn('UNICODE_STRING_ASSIGN_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
