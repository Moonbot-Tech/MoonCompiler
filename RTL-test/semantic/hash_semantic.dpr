program hash_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
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

function ReferenceChecksum(Data: PByte; Count: Integer): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    Inc(Result, Data[I]);
end;

function ReferenceAdler32(Data: PByte; Count: Integer): Cardinal;
const
  ModAdler = 65521;
var
  A, B: Cardinal;
  I: Integer;
begin
  A := 1;
  B := 0;
  for I := 0 to Count - 1 do
  begin
    A := (A + Data[I]) mod ModAdler;
    B := (B + A) mod ModAdler;
  end;
  Result := (B shl 16) or A;
end;

function ReferenceSdbm(Data: PByte; Count: Integer): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    Result := Data[I] + (Result shl 6) + (Result shl 16) - Result;
end;

procedure CheckHashFamilies(Data: Pointer; ByteCount: Integer);
var
  DelphiPrimary, DelphiSecondary: Cardinal;
  LittlePrimary, LittleSecondary: Cardinal;
  WordPrimary, WordSecondary: Cardinal;
  WordCount: Integer;
begin
  Check(SimpleChecksumHash(Data, ByteCount) =
    ReferenceChecksum(Data, ByteCount), 'simple checksum reference');
  Check(Adler32(Data, ByteCount) = ReferenceAdler32(Data, ByteCount),
    'Adler32 reference');
  Check(sdbm(Data, ByteCount) = ReferenceSdbm(Data, ByteCount),
    'sdbm reference');

  LittlePrimary := $10203040;
  LittleSecondary := 0;
  HashLittle2(Data, ByteCount, LittlePrimary, LittleSecondary);
  Check(LittlePrimary = HashLittle(Data, ByteCount, $10203040),
    'HashLittle2 primary agreement');

  DelphiPrimary := $10203040;
  DelphiSecondary := 0;
  DelphiHashLittle2(Data, ByteCount, DelphiPrimary, DelphiSecondary);
  Check(Integer(DelphiPrimary) = DelphiHashLittle(Data, ByteCount, $10203040),
    'DelphiHashLittle2 primary agreement');

  WordCount := ByteCount div SizeOf(LongWord);
  WordPrimary := $10203040;
  WordSecondary := 0;
  HashWord2(PLongWord(Data), WordCount, WordPrimary, WordSecondary);
  Check(WordPrimary = HashWord(PLongWord(Data), WordCount, $10203040),
    'HashWord2 primary agreement');
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
  CheckHashFamilies(@Buffer[0], Length(Buffer));
  CheckHashFamilies(@Buffer[1], Length(Buffer) - 1);
  CheckHashFamilies(nil, 0);
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
