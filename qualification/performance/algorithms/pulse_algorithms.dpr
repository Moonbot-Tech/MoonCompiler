program pulse_algorithms;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  {$ifdef FPC}
  Generics.Collections,
  {$else}
  System.Generics.Collections,
  {$endif}
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

type
  TShaState = array[0..7] of UInt32;
  TChaChaState = array[0..15] of UInt32;
  TIntArray = array of Integer;
  THashEntry = record
    Key: UInt64;
    Value: UInt64;
    Used: Boolean;
  end;

const
  ShaK: array[0..63] of UInt32 = (
    $428A2F98,$71374491,$B5C0FBCF,$E9B5DBA5,$3956C25B,$59F111F1,$923F82A4,$AB1C5ED5,
    $D807AA98,$12835B01,$243185BE,$550C7DC3,$72BE5D74,$80DEB1FE,$9BDC06A7,$C19BF174,
    $E49B69C1,$EFBE4786,$0FC19DC6,$240CA1CC,$2DE92C6F,$4A7484AA,$5CB0A9DC,$76F988DA,
    $983E5152,$A831C66D,$B00327C8,$BF597FC7,$C6E00BF3,$D5A79147,$06CA6351,$14292967,
    $27B70A85,$2E1B2138,$4D2C6DFC,$53380D13,$650A7354,$766A0ABB,$81C2C92E,$92722C85,
    $A2BFE8A1,$A81A664B,$C24B8B70,$C76C51A3,$D192E819,$D6990624,$F40E3585,$106AA070,
    $19A4C116,$1E376C08,$2748774C,$34B0BCB5,$391C0CB3,$4ED8AA4A,$5B9CCA4F,$682E6FF3,
    $748F82EE,$78A5636F,$84C87814,$8CC70208,$90BEFFFA,$A4506CEB,$BEF9A3F7,$C67178F2);

var
  Data4K: TBytes;
  Repetitive4K: TBytes;
  SortSource: TIntArray;
  SortedSource: TIntArray;

function Ror32(Value: UInt32; Count: Integer): UInt32; inline;
begin
  Result := (Value shr Count) or (Value shl (32 - Count));
end;

function Crc32(const Data: TBytes): UInt32;
var
  I, J: Integer;
  C: UInt32;
begin
  C := $FFFFFFFF;
  for I := 0 to High(Data) do
  begin
    C := C xor Data[I];
    for J := 0 to 7 do
      If (C and 1) <> 0 then
        C := (C shr 1) xor $EDB88320
      else
        C := C shr 1;
  end;
  Result := not C;
end;

procedure ShaTransform(var State: TShaState; const Block: array of Byte);
var
  W: array[0..63] of UInt32;
  A, B, C, D, E, F, G, H, S0, S1, Ch, Maj, T1, T2: UInt32;
  I: Integer;
begin
  for I := 0 to 15 do
    W[I] := (UInt32(Block[I * 4]) shl 24) or
      (UInt32(Block[I * 4 + 1]) shl 16) or
      (UInt32(Block[I * 4 + 2]) shl 8) or UInt32(Block[I * 4 + 3]);
  for I := 16 to 63 do
  begin
    S0 := Ror32(W[I - 15], 7) xor Ror32(W[I - 15], 18) xor
      (W[I - 15] shr 3);
    S1 := Ror32(W[I - 2], 17) xor Ror32(W[I - 2], 19) xor
      (W[I - 2] shr 10);
    W[I] := W[I - 16] + S0 + W[I - 7] + S1;
  end;
  A := State[0]; B := State[1]; C := State[2]; D := State[3];
  E := State[4]; F := State[5]; G := State[6]; H := State[7];
  for I := 0 to 63 do
  begin
    S1 := Ror32(E, 6) xor Ror32(E, 11) xor Ror32(E, 25);
    Ch := (E and F) xor ((not E) and G);
    T1 := H + S1 + Ch + ShaK[I] + W[I];
    S0 := Ror32(A, 2) xor Ror32(A, 13) xor Ror32(A, 22);
    Maj := (A and B) xor (A and C) xor (B and C);
    T2 := S0 + Maj;
    H := G; G := F; F := E; E := D + T1;
    D := C; C := B; B := A; A := T1 + T2;
  end;
  Inc(State[0], A); Inc(State[1], B); Inc(State[2], C); Inc(State[3], D);
  Inc(State[4], E); Inc(State[5], F); Inc(State[6], G); Inc(State[7], H);
end;

procedure Sha256(const Data: TBytes; out Digest: array of Byte);
var
  State: TShaState;
  Block: array[0..63] of Byte;
  Offset, Remaining, I: Integer;
  Bits: UInt64;
begin
  State[0] := $6A09E667; State[1] := $BB67AE85;
  State[2] := $3C6EF372; State[3] := $A54FF53A;
  State[4] := $510E527F; State[5] := $9B05688C;
  State[6] := $1F83D9AB; State[7] := $5BE0CD19;
  Offset := 0;
  while Offset + 64 <= Length(Data) do
  begin
    Move(Data[Offset], Block[0], 64);
    ShaTransform(State, Block);
    Inc(Offset, 64);
  end;
  FillChar(Block, SizeOf(Block), 0);
  Remaining := Length(Data) - Offset;
  If Remaining > 0 then
    Move(Data[Offset], Block[0], Remaining);
  Block[Remaining] := $80;
  If Remaining >= 56 then
  begin
    ShaTransform(State, Block);
    FillChar(Block, SizeOf(Block), 0);
  end;
  Bits := UInt64(Length(Data)) * 8;
  for I := 0 to 7 do
    Block[63 - I] := Byte(Bits shr (I * 8));
  ShaTransform(State, Block);
  for I := 0 to 7 do
  begin
    Digest[I * 4] := Byte(State[I] shr 24);
    Digest[I * 4 + 1] := Byte(State[I] shr 16);
    Digest[I * 4 + 2] := Byte(State[I] shr 8);
    Digest[I * 4 + 3] := Byte(State[I]);
  end;
end;

procedure QuarterRound(var A, B, C, D: UInt32); inline;
begin
  Inc(A, B); D := D xor A; D := (D shl 16) or (D shr 16);
  Inc(C, D); B := B xor C; B := (B shl 12) or (B shr 20);
  Inc(A, B); D := D xor A; D := (D shl 8) or (D shr 24);
  Inc(C, D); B := B xor C; B := (B shl 7) or (B shr 25);
end;

procedure ChaChaBlock(const Input: TChaChaState; out Output: TChaChaState);
var
  X: TChaChaState;
  I: Integer;
begin
  X := Input;
  for I := 1 to 10 do
  begin
    QuarterRound(X[0], X[4], X[8], X[12]);
    QuarterRound(X[1], X[5], X[9], X[13]);
    QuarterRound(X[2], X[6], X[10], X[14]);
    QuarterRound(X[3], X[7], X[11], X[15]);
    QuarterRound(X[0], X[5], X[10], X[15]);
    QuarterRound(X[1], X[6], X[11], X[12]);
    QuarterRound(X[2], X[7], X[8], X[13]);
    QuarterRound(X[3], X[4], X[9], X[14]);
  end;
  for I := 0 to 15 do
    Output[I] := X[I] + Input[I];
end;

function LzCompress(const Source: TBytes; out PackedData: TBytes): Integer;
var
  I, Candidate, Distance, BestDistance, BestLength, MatchLength,
    LiteralStart, LiteralLength, OutPos: Integer;

  procedure EmitLiterals(Start, Count: Integer);
  var
    Chunk: Integer;
  begin
    while Count > 0 do
    begin
      Chunk := Count;
      If Chunk > 127 then
        Chunk := 127;
      PackedData[OutPos] := Byte(Chunk);
      Inc(OutPos);
      Move(Source[Start], PackedData[OutPos], Chunk);
      Inc(OutPos, Chunk);
      Inc(Start, Chunk);
      Dec(Count, Chunk);
    end;
  end;

begin
  SetLength(PackedData, Length(Source) * 2 + 16);
  I := 0;
  OutPos := 0;
  LiteralStart := 0;
  while I < Length(Source) do
  begin
    BestLength := 0;
    BestDistance := 0;
    Candidate := I - 1;
    while (Candidate >= 0) and (I - Candidate <= 255) do
    begin
      MatchLength := 0;
      while (MatchLength < 130) and (I + MatchLength < Length(Source)) and
        (Source[Candidate + MatchLength] = Source[I + MatchLength]) do
        Inc(MatchLength);
      If MatchLength > BestLength then
      begin
        BestLength := MatchLength;
        BestDistance := I - Candidate;
      end;
      Dec(Candidate);
    end;
    If BestLength >= 4 then
    begin
      LiteralLength := I - LiteralStart;
      If LiteralLength > 0 then
        EmitLiterals(LiteralStart, LiteralLength);
      PackedData[OutPos] := Byte($80 or (BestLength - 3));
      PackedData[OutPos + 1] := Byte(BestDistance);
      Inc(OutPos, 2);
      Inc(I, BestLength);
      LiteralStart := I;
    end
    else
      Inc(I);
  end;
  LiteralLength := I - LiteralStart;
  If LiteralLength > 0 then
    EmitLiterals(LiteralStart, LiteralLength);
  SetLength(PackedData, OutPos);
  Result := OutPos;
end;

function LzDecompress(const PackedData: TBytes; ExpectedSize: Integer;
  out Target: TBytes): Integer;
var
  InPos, OutPos, Count, Distance, I: Integer;
begin
  SetLength(Target, ExpectedSize);
  InPos := 0;
  OutPos := 0;
  while InPos < Length(PackedData) do
  begin
    Count := PackedData[InPos];
    Inc(InPos);
    If (Count and $80) = 0 then
    begin
      Move(PackedData[InPos], Target[OutPos], Count);
      Inc(InPos, Count);
      Inc(OutPos, Count);
    end
    else
    begin
      Count := (Count and $7F) + 3;
      Distance := PackedData[InPos];
      Inc(InPos);
      for I := 1 to Count do
      begin
        Target[OutPos] := Target[OutPos - Distance];
        Inc(OutPos);
      end;
    end;
  end;
  Result := OutPos;
end;

procedure QuickSort(var Values: TIntArray; Left, Right: Integer);
var
  I, J, Pivot, Temp: Integer;
begin
  I := Left;
  J := Right;
  Pivot := Values[(Left + Right) shr 1];
  repeat
    while Values[I] < Pivot do Inc(I);
    while Values[J] > Pivot do Dec(J);
    If I <= J then
    begin
      Temp := Values[I]; Values[I] := Values[J]; Values[J] := Temp;
      Inc(I); Dec(J);
    end;
  until I > J;
  If Left < J then QuickSort(Values, Left, J);
  If I < Right then QuickSort(Values, I, Right);
end;

function BinarySearch(const Values: TIntArray; Value: Integer): Integer;
var
  L, H, M: Integer;
begin
  L := 0;
  H := High(Values);
  while L <= H do
  begin
    M := (L + H) shr 1;
    If Values[M] < Value then
      L := M + 1
    else If Values[M] > Value then
      H := M - 1
    else
      Exit(M);
  end;
  Result := -1;
end;

function CaseCrc32(Iterations: Integer): UInt64;
var
  I: Integer;
  D: UInt32;
begin
  D := 0;
  for I := 1 to Iterations do
    D := D xor Crc32(Data4K);
  Result := D;
end;

function CaseSha256(Iterations: Integer): UInt64;
var
  I, J: Integer;
  D: array[0..31] of Byte;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
  begin
    Sha256(Data4K, D);
    for J := 0 to 31 do
      S := S * 131 + D[J];
  end;
  Result := S;
end;

function CaseChaCha20(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Input, Output: TChaChaState;
  S: UInt64;
begin
  Input[0] := $61707865; Input[1] := $3320646E;
  Input[2] := $79622D32; Input[3] := $6B206574;
  for J := 4 to 15 do Input[J] := UInt32(J * $1020304 + 7);
  S := 0;
  for I := 1 to Iterations do
  begin
    Input[12] := UInt32(I);
    ChaChaBlock(Input, Output);
    for J := 0 to 15 do
      S := S + Output[J];
  end;
  Result := S;
end;

function CaseLzCompress(Iterations: Integer): UInt64;
var
  I: Integer;
  PackedData: TBytes;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    S := S + UInt64(LzCompress(Repetitive4K, PackedData)) + PackedData[0];
  Result := S;
end;

function CaseLzRoundTrip(Iterations: Integer): UInt64;
var
  I: Integer;
  PackedData, Restored: TBytes;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
  begin
    LzCompress(Repetitive4K, PackedData);
    If LzDecompress(PackedData, Length(Repetitive4K), Restored) <>
       Length(Repetitive4K) then
      raise EAbort.Create('LZ size mismatch');
    If not CompareMem(@Repetitive4K[0], @Restored[0], Length(Restored)) then
      raise EAbort.Create('LZ content mismatch');
    S := S + UInt64(Length(PackedData)) + Restored[High(Restored)];
  end;
  Result := S;
end;

function CaseQuickSort(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TIntArray;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
  begin
    Values := Copy(SortSource);
    QuickSort(Values, 0, High(Values));
    S := S + UInt32(Values[0]) + UInt64(UInt32(Values[High(Values)]));
  end;
  Result := S;
end;

function CaseBinarySearch(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
      S := S + UInt64(BinarySearch(SortedSource,
        SortedSource[(J * 13 + I) and High(SortedSource)]));
  Result := S;
end;

function CaseOpenHash(Iterations: Integer): UInt64;
const
  Capacity = 8192;
var
  I, J, Slot: Integer;
  Table: array of THashEntry;
  Key, S: UInt64;
begin
  S := 0;
  SetLength(Table, Capacity);
  for I := 1 to Iterations do
  begin
    FillChar(Table[0], Length(Table) * SizeOf(THashEntry), 0);
    for J := 0 to 4095 do
    begin
      Key := UInt64(UInt32(SortSource[J]));
      Slot := Integer((Key * UInt64($9E3779B185EBCA87)) and (Capacity - 1));
      while Table[Slot].Used do
        Slot := (Slot + 1) and (Capacity - 1);
      Table[Slot].Used := True;
      Table[Slot].Key := Key;
      Table[Slot].Value := UInt64(J);
    end;
    for J := 0 to 4095 do
    begin
      Key := UInt64(UInt32(SortSource[J]));
      Slot := Integer((Key * UInt64($9E3779B185EBCA87)) and (Capacity - 1));
      while Table[Slot].Key <> Key do
        Slot := (Slot + 1) and (Capacity - 1);
      S := S + Table[Slot].Value;
    end;
  end;
  Result := S;
end;

function CaseGenericList(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<Integer>;
  S: UInt64;
begin
  S := 0;
  List := TList<Integer>.Create;
  try
    for I := 1 to Iterations do
    begin
      List.Clear;
      for J := 0 to 511 do
        List.Add(SortSource[J]);
      for J := 0 to List.Count - 1 do
        S := S + UInt32(List[J]);
    end;
  finally
    List.Free;
  end;
  Result := S;
end;

procedure VerifyAlgorithms;
var
  TestData, Digest, PackedData, Restored: TBytes;
  Hex: string;
  I: Integer;
begin
  TestData := TEncoding.ASCII.GetBytes('123456789');
  If Crc32(TestData) <> $CBF43926 then
    raise EAbort.Create('CRC32 oracle failed');
  TestData := TEncoding.ASCII.GetBytes('abc');
  SetLength(Digest, 32);
  Sha256(TestData, Digest);
  Hex := '';
  for I := 0 to High(Digest) do
    Hex := Hex + IntToHex(Digest[I], 2);
  If not SameText(Hex,
    'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') then
    raise EAbort.Create('SHA-256 oracle failed: ' + Hex);
  LzCompress(Repetitive4K, PackedData);
  LzDecompress(PackedData, Length(Repetitive4K), Restored);
  If (Length(Restored) <> Length(Repetitive4K)) or
     not CompareMem(@Restored[0], @Repetitive4K[0], Length(Restored)) then
    raise EAbort.Create('LZ round-trip oracle failed');
end;

procedure InitializeData;
var
  I: Integer;
  X: UInt64;
begin
  SetLength(Data4K, 4096);
  SetLength(Repetitive4K, 4096);
  SetLength(SortSource, 4096);
  X := UInt64($D1B54A32D192ED03);
  for I := 0 to 4095 do
  begin
    X := X xor (X shr 12); X := X xor (X shl 25); X := X xor (X shr 27);
    X := X * UInt64(2685821657736338717);
    Data4K[I] := Byte(X);
    Repetitive4K[I] := Byte((I div 64) xor (I and 7));
    SortSource[I] := Integer(UInt32(X));
  end;
  SortedSource := Copy(SortSource);
  QuickSort(SortedSource, 0, High(SortedSource));
  VerifyAlgorithms;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_algorithms', Profile, SelectedCase);
  InitializeData;
  Found := False;
  PulseRunCase('pulse_algorithms', 'crc32-bitwise-4k', 'codegen', 'Pascal',
    @CaseCrc32, 4096 * 8, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'sha256-4k', 'codegen', 'Pascal',
    @CaseSha256, 4096, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'chacha20-block', 'codegen', 'Pascal',
    @CaseChaCha20, 20 * 16, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'lz-compress-4k', 'codegen+memory', 'Pascal',
    @CaseLzCompress, 4096, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'lz-roundtrip-4k', 'codegen+memory', 'Pascal',
    @CaseLzRoundTrip, 8192, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'quicksort-4096', 'codegen+rtl', 'Pascal',
    @CaseQuickSort, 4096, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'binary-search-256', 'codegen', 'Pascal',
    @CaseBinarySearch, 256, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'open-hash-4096', 'codegen+memory', 'Pascal',
    @CaseOpenHash, 8192, Profile, SelectedCase, Found);
  PulseRunCase('pulse_algorithms', 'generic-list-512', 'rtl',
    'Generics.Collections', @CaseGenericList, 1024, Profile, SelectedCase,
    Found);
  PulseFinish('pulse_algorithms', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
