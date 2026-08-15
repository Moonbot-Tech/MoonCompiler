program hash_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  Generics.Hashes;

const
  ThreadIterations = 10000;

type
  THashThread = class(TThread)
  private
    FData: Pointer;
    FLength: Integer;
    FExpected: Cardinal;
    FValid: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AData: Pointer; ALength: Integer; AExpected: Cardinal);
    property Valid: Boolean read FValid;
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('HASH_SEMANTIC_FAIL: ' + AMessage);
end;

constructor THashThread.Create(AData: Pointer; ALength: Integer;
  AExpected: Cardinal);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FData := AData;
  FLength := ALength;
  FExpected := AExpected;
  FValid := True;
end;

procedure THashThread.Execute;
var
  I: Integer;
begin
  for I := 1 to ThreadIterations do
    if xxHash32Pascal($9E3779B9, FData, FLength) <> FExpected then
    begin
      FValid := False;
      Exit;
    end;
end;

procedure Run;
var
  Buffer: array[0..271] of Byte;
  Threads: array[0..3] of THashThread;
  Expected, PascalHash, AsmHash: Cardinal;
  I, J, Offset: Integer;
  Text: RawByteString;
begin
  Check(xxHash32Pascal(0, nil, 0) = $02CC5D05, 'empty golden vector');
  Text := 'a';
  Check(xxHash32Pascal(0, Pointer(Text), Length(Text)) = $550D7456,
    'one-byte golden vector');
  Text := 'abc';
  Check(xxHash32Pascal(0, Pointer(Text), Length(Text)) = $32D153FF,
    'three-byte golden vector');

  for I := 0 to High(Buffer) do
    Buffer[I] := Byte((I * 73 + 19) and $FF);
  for Offset := 0 to 7 do
    for I := 0 to 255 do
    begin
      PascalHash := xxHash32Pascal($9E3779B9, @Buffer[Offset], I);
      AsmHash := xxHash32($9E3779B9, @Buffer[Offset], I);
      Check(PascalHash = AsmHash,
        Format('implementation agreement offset=%d length=%d', [Offset, I]));
      Check(PascalHash = xxHash32Pascal($9E3779B9, @Buffer[Offset], I),
        Format('determinism offset=%d length=%d', [Offset, I]));
    end;

  Expected := xxHash32Pascal($9E3779B9, @Buffer[3], 255);
  for I := 0 to High(Threads) do
  begin
    Threads[I] := THashThread.Create(@Buffer[3], 255, Expected);
    Threads[I].Start;
  end;
  for J := 0 to High(Threads) do
  begin
    Threads[J].WaitFor;
    Check((Threads[J].FatalException = nil) and Threads[J].Valid,
      'threaded determinism');
    Threads[J].Free;
  end;
end;

begin
  try
    Run;
    WriteLn('HASH_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
