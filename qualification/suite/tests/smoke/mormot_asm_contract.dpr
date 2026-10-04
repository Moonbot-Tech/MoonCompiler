program mormot_asm_contract;
{$ifdef FPC}{$mode delphi}{$endif}{$H+}{$Q-}{$R-}
uses SysUtils, mormot.core.base;
var
  Data: array[0..4095] of Byte;
  A: mormot.core.base.PIntegerArray;
  S: PAnsiChar;
  P: PUtf8Char;
  Digest: UInt64;
  Features: TX64CpuFeatures;
  L, Offset, I, K, N, Expected, Actual: Integer;
procedure Fold(V: UInt64);
begin
  Digest := (Digest xor V) * UInt64(1099511628211);
end;
begin
  try
    If mormot.core.base.StrLen(nil) <> 0 then Halt(21);
    If Hash32(nil, 0) <> 0 then Halt(22);
    If Hash32(nil, 17) <> 0 then Halt(23);
    If xxHash32(0, nil, 0) <> $02CC5D05 then Halt(24);
    If PosChar(PUtf8Char(nil), 'x') <> nil then Halt(25);
    If ByteScanIndex(nil, 0, 42) <> -1 then Halt(26);
    If IntegerScanIndex(nil, 0, 42) <> -1 then Halt(27);
    Digest := 14695981039346656037;
    for Offset := 0 to 31 do
      for L := 0 to 259 do begin
        for I := 0 to High(Data) do
          Data[I] := Byte((I * 17 + L) mod 251 + 1);
        S := PAnsiChar(@Data[Offset]);
        Fold(Hash32(mormot.core.base.PCardinalArray(S), L));
        Fold(xxHash32(1234567, S, L));
        for I := 0 to L - 1 do
          S[I] := 'a';
        S[L] := #0;
        If mormot.core.base.StrLen(S) <> L then Halt(11);
        If L > 0 then S[L div 2] := 'Z';
        P := PosChar(PUtf8Char(S), 'Z');
        If L = 0 then begin
          If P <> nil then Halt(12);
        end else If P <> PUtf8Char(S + L div 2) then Halt(13);
        If PosChar(PUtf8Char(S), 'z') <> nil then Halt(14);
        If ByteScanIndex(mormot.core.base.PByteArray(S), L, Ord('Z')) <> (L div 2) then
          If L <> 0 then Halt(15);
        If ByteScanIndex(mormot.core.base.PByteArray(S), L, 255) <> -1 then Halt(16);
        A := mormot.core.base.PIntegerArray(@Data[Offset]);
        for I := 0 to 259 do A[I] := I * 3;
        for K := 0 to 2 do begin
          If K = 0 then Expected := -1
          else If K = 1 then Expected := L div 2
          else Expected := L - 1;
          If (L = 0) or (Expected < 0) then begin
            Expected := -1;
            N := 10000;
          end else N := Expected * 3;
          Actual := IntegerScanIndex(mormot.core.base.PCardinalArray(A), L, N);
          If Actual <> Expected then Halt(17);
        end;
      end;
    Features := X64CpuFeatures;
    A := mormot.core.base.PIntegerArray((NativeUInt(@Data[0]) + 31) and not NativeUInt(31));
    for K := 0 to 1 do begin
      If K = 0 then Exclude(X64CpuFeatures, cpuAVX2) else X64CpuFeatures := Features;
      for N := 1 to 8 do begin
        L := N * 32;
        for I := 0 to L - 1 do A[I] := I - 37;
        DynArrayHashTableAdjust(A, 15, L);
        for I := 0 to L - 1 do begin
          Expected := I - 37;
          If Expected > 15 then Dec(Expected);
          If A[I] <> Expected then Halt(18);
        end;
      end;
    end;
    X64CpuFeatures := Features;
    If Digest <> UInt64($F575CB2E1BF6CAF9) then Halt(28);
    WriteLn('MORMOT_ASM_CONTRACT_PASS digest=', IntToHex(Digest, 16));
  except
    on E: Exception do begin
      WriteLn(E.ClassName, ': ', E.Message);
      Halt(29);
    end;
  end;
end.
