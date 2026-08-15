program pulse_workloads;

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
  Math,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

type
  TBody = record
    X, Y, Z, VX, VY, VZ, Mass: Double;
  end;
  TBodies = array[0..4] of TBody;
  PTreeNode = ^TTreeNode;
  TTreeNode = record
    Left, Right: PTreeNode;
    Value: Integer;
  end;
  PListNode = ^TListNode;
  TListNode = record
    Next: PListNode;
    Key, Value: Integer;
  end;
  TComplex = record
    Re, Im: Double;
  end;

const
  PiValue = 3.141592653589793;
  SolarMass = 4 * PiValue * PiValue;
  DaysPerYear = 365.24;
  SpectralSize = 128;
  StreamCount = 2097152;
  GridSize = 128;
  FloydSize = 64;
  ImageSize = 256;
  FftSize = 1024;

var
  SpectralU, SpectralV, SpectralTmp: array of Double;
  StreamA, StreamB, StreamC: array of Double;
  GridInitial, GridA, GridB: array of Double;
  FloydBase: array of Integer;
  ImageInput, ImageOutput: array of Single;
  FftInput: array of TComplex;
  StateInput: RawByteString;

function SpectralA(I, J: Integer): Double; inline;
var
  Sum: Integer;
begin
  Sum := I + J;
  Result := 1.0 / (Sum * (Sum + 1) div 2 + I + 1);
end;

procedure MultiplyAv(const V: array of Double; var Av: array of Double);
var
  I, J: Integer;
  S: Double;
begin
  for I := 0 to High(Av) do
  begin
    S := 0;
    for J := 0 to High(V) do
      S := S + SpectralA(I, J) * V[J];
    Av[I] := S;
  end;
end;

procedure MultiplyAtv(const V: array of Double; var Atv: array of Double);
var
  I, J: Integer;
  S: Double;
begin
  for I := 0 to High(Atv) do
  begin
    S := 0;
    for J := 0 to High(V) do
      S := S + SpectralA(J, I) * V[J];
    Atv[I] := S;
  end;
end;

function CaseSpectralNorm(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Vbv, Vv: Double;
begin
  for J := 0 to High(SpectralU) do
    SpectralU[J] := 1.0;
  for I := 1 to Iterations do
  begin
    MultiplyAv(SpectralU, SpectralTmp);
    MultiplyAtv(SpectralTmp, SpectralV);
    MultiplyAv(SpectralV, SpectralTmp);
    MultiplyAtv(SpectralTmp, SpectralU);
  end;
  Vbv := 0;
  Vv := 0;
  for J := 0 to High(SpectralU) do
  begin
    Vbv := Vbv + SpectralU[J] * SpectralV[J];
    Vv := Vv + SpectralV[J] * SpectralV[J];
  end;
  Vbv := Sqrt(Vbv / Vv);
  Result := PUInt64(@Vbv)^;
end;

procedure InitializeBodies(out Bodies: TBodies);
begin
  FillChar(Bodies, SizeOf(Bodies), 0);
  Bodies[0].Mass := SolarMass;
  Bodies[1].X := 4.84143144246472090; Bodies[1].Y := -1.16032004402742839;
  Bodies[1].Z := -0.103622044471123139; Bodies[1].VX := 0.00166007664274403694 * DaysPerYear;
  Bodies[1].VY := 0.00769901118419740425 * DaysPerYear;
  Bodies[1].VZ := -0.0000690460016972063023 * DaysPerYear;
  Bodies[1].Mass := 0.000954791938424326609 * SolarMass;
  Bodies[2].X := 8.34336671824457987; Bodies[2].Y := 4.12479856412430479;
  Bodies[2].Z := -0.403523417114321381; Bodies[2].VX := -0.00276742510726862411 * DaysPerYear;
  Bodies[2].VY := 0.00499852801234917238 * DaysPerYear;
  Bodies[2].VZ := 0.0000230417297573763929 * DaysPerYear;
  Bodies[2].Mass := 0.000285885980666130812 * SolarMass;
  Bodies[3].X := 12.8943695621391310; Bodies[3].Y := -15.1111514016981531;
  Bodies[3].Z := -0.223307578892655734; Bodies[3].VX := 0.00296460137564761618 * DaysPerYear;
  Bodies[3].VY := 0.00237847173959480950 * DaysPerYear;
  Bodies[3].VZ := -0.0000296589568540230525 * DaysPerYear;
  Bodies[3].Mass := 0.0000436624404335156298 * SolarMass;
  Bodies[4].X := 15.3796971148509165; Bodies[4].Y := -25.9193146099879641;
  Bodies[4].Z := 0.179258772950371181; Bodies[4].VX := 0.00268067772490389322 * DaysPerYear;
  Bodies[4].VY := 0.00162824170038242295 * DaysPerYear;
  Bodies[4].VZ := -0.0000951592254519715870 * DaysPerYear;
  Bodies[4].Mass := 0.0000515138902046611451 * SolarMass;
end;

procedure AdvanceBodies(var Bodies: TBodies; Dt: Double);
var
  I, J: Integer;
  Dx, Dy, Dz, Distance2, Magnitude: Double;
begin
  for I := 0 to High(Bodies) - 1 do
    for J := I + 1 to High(Bodies) do
    begin
      Dx := Bodies[I].X - Bodies[J].X;
      Dy := Bodies[I].Y - Bodies[J].Y;
      Dz := Bodies[I].Z - Bodies[J].Z;
      Distance2 := Dx * Dx + Dy * Dy + Dz * Dz;
      Magnitude := Dt / (Sqrt(Distance2) * Distance2);
      Bodies[I].VX := Bodies[I].VX - Dx * Bodies[J].Mass * Magnitude;
      Bodies[I].VY := Bodies[I].VY - Dy * Bodies[J].Mass * Magnitude;
      Bodies[I].VZ := Bodies[I].VZ - Dz * Bodies[J].Mass * Magnitude;
      Bodies[J].VX := Bodies[J].VX + Dx * Bodies[I].Mass * Magnitude;
      Bodies[J].VY := Bodies[J].VY + Dy * Bodies[I].Mass * Magnitude;
      Bodies[J].VZ := Bodies[J].VZ + Dz * Bodies[I].Mass * Magnitude;
    end;
  for I := 0 to High(Bodies) do
  begin
    Bodies[I].X := Bodies[I].X + Dt * Bodies[I].VX;
    Bodies[I].Y := Bodies[I].Y + Dt * Bodies[I].VY;
    Bodies[I].Z := Bodies[I].Z + Dt * Bodies[I].VZ;
  end;
end;

function BodyEnergy(const Bodies: TBodies): Double;
var
  I, J: Integer;
  Dx, Dy, Dz: Double;
begin
  Result := 0;
  for I := 0 to High(Bodies) do
  begin
    Result := Result + Bodies[I].Mass * (Sqr(Bodies[I].VX) +
      Sqr(Bodies[I].VY) + Sqr(Bodies[I].VZ)) * 0.5;
    for J := I + 1 to High(Bodies) do
    begin
      Dx := Bodies[I].X - Bodies[J].X;
      Dy := Bodies[I].Y - Bodies[J].Y;
      Dz := Bodies[I].Z - Bodies[J].Z;
      Result := Result - Bodies[I].Mass * Bodies[J].Mass /
        Sqrt(Dx * Dx + Dy * Dy + Dz * Dz);
    end;
  end;
end;

function CaseNBody(Iterations: Integer): UInt64;
var
  Bodies: TBodies;
  I, J: Integer;
  Energy: Double;
begin
  InitializeBodies(Bodies);
  for I := 1 to Iterations do
    for J := 1 to 100 do
      AdvanceBodies(Bodies, 0.01);
  Energy := BodyEnergy(Bodies);
  Result := PUInt64(@Energy)^;
end;

function MakeTree(Value, Depth: Integer): PTreeNode;
begin
  GetMem(Result, SizeOf(TTreeNode));
  Result^.Value := Value;
  If Depth = 0 then
  begin
    Result^.Left := nil;
    Result^.Right := nil;
  end
  else
  begin
    Result^.Left := MakeTree(Value * 2 - 1, Depth - 1);
    Result^.Right := MakeTree(Value * 2, Depth - 1);
  end;
end;

function CheckTree(Node: PTreeNode): Integer;
begin
  If Node^.Left = nil then
    Exit(Node^.Value);
  Result := CheckTree(Node^.Left) + Node^.Value - CheckTree(Node^.Right);
end;

procedure FreeTree(Node: PTreeNode);
begin
  If Node^.Left <> nil then
  begin
    FreeTree(Node^.Left);
    FreeTree(Node^.Right);
  end;
  FreeMem(Node);
end;

function CaseBinaryTrees(Iterations: Integer): UInt64;
var
  I: Integer;
  Node: PTreeNode;
  Digest: Int64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    Node := MakeTree(I, 10);
    Digest := Digest + CheckTree(Node);
    FreeTree(Node);
  end;
  Result := UInt64(Digest);
end;

function CaseMandelbrot(Iterations: Integer): UInt64;
var
  N, X, Y, K, I: Integer;
  Cx, Cy, Zr, Zi, Tr, Ti, Step: Double;
  Digest: UInt64;
begin
  N := 128;
  Step := 2.0 / N;
  Digest := 0;
  for I := 1 to Iterations do
    for Y := 0 to N - 1 do
    begin
      Cy := Y * Step - 1.0;
      for X := 0 to N - 1 do
      begin
        Cx := X * Step - 1.5;
        Zr := 0; Zi := 0; Tr := 0; Ti := 0;
        K := 0;
        while (K < 50) and (Tr + Ti < 4.0) do
        begin
          Zi := 2.0 * Zr * Zi + Cy;
          Zr := Tr - Ti + Cx;
          Ti := Zi * Zi;
          Tr := Zr * Zr;
          Inc(K);
        end;
        Digest := Digest + UInt64(K + X + Y);
      end;
    end;
  Result := Digest;
end;

function Fannkuch8: Integer;
var
  Permutation, CopyPermutation, Count: array[0..7] of Integer;
  R, I, K, First, Flips, MaxFlips, Temp: Integer;
begin
  for I := 0 to 7 do
  begin
    Permutation[I] := I;
    Count[I] := 0;
  end;
  R := 8;
  MaxFlips := 0;
  repeat
    while R <> 1 do
    begin
      Count[R - 1] := R;
      Dec(R);
    end;
    If (Permutation[0] <> 0) and (Permutation[7] <> 7) then
    begin
      CopyPermutation := Permutation;
      Flips := 0;
      First := CopyPermutation[0];
      while First <> 0 do
      begin
        K := First;
        I := 0;
        while I < K do
        begin
          Temp := CopyPermutation[I];
          CopyPermutation[I] := CopyPermutation[K];
          CopyPermutation[K] := Temp;
          Inc(I); Dec(K);
        end;
        Inc(Flips);
        First := CopyPermutation[0];
      end;
      If Flips > MaxFlips then
        MaxFlips := Flips;
    end;
    repeat
      If R = 8 then
        Exit(MaxFlips);
      Temp := Permutation[0];
      for I := 0 to R - 1 do
        Permutation[I] := Permutation[I + 1];
      Permutation[R] := Temp;
      Dec(Count[R]);
      If Count[R] > 0 then Break;
      Inc(R);
    until False;
  until False;
end;

function CaseFannkuch(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(Fannkuch8);
end;

function CaseStreamCopy(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: Double;
begin
  for I := 1 to Iterations do
    for J := 0 to High(StreamA) do
      StreamC[J] := StreamA[J];
  S := StreamC[0] + StreamC[High(StreamC)];
  Result := PUInt64(@S)^;
end;

function CaseStreamScale(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: Double;
begin
  for I := 1 to Iterations do
    for J := 0 to High(StreamA) do
      StreamB[J] := 3.0 * StreamC[J];
  S := StreamB[0] + StreamB[High(StreamB)];
  Result := PUInt64(@S)^;
end;

function CaseStreamAdd(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: Double;
begin
  for I := 1 to Iterations do
    for J := 0 to High(StreamA) do
      StreamC[J] := StreamA[J] + StreamB[J];
  S := StreamC[0] + StreamC[High(StreamC)];
  Result := PUInt64(@S)^;
end;

function CaseStreamTriad(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: Double;
begin
  for I := 1 to Iterations do
    for J := 0 to High(StreamA) do
      StreamA[J] := StreamB[J] + 3.0 * StreamC[J];
  S := StreamA[0] + StreamA[High(StreamA)];
  Result := PUInt64(@S)^;
end;

function CaseFloydWarshall(Iterations: Integer): UInt64;
var
  Matrix: array of Integer;
  Iteration, I, J, K, Via, Index: Integer;
  Digest: UInt64;
begin
  SetLength(Matrix, Length(FloydBase));
  Digest := 0;
  for Iteration := 1 to Iterations do
  begin
    Move(FloydBase[0], Matrix[0], Length(Matrix) * SizeOf(Integer));
    for K := 0 to FloydSize - 1 do
      for I := 0 to FloydSize - 1 do
        for J := 0 to FloydSize - 1 do
        begin
          Index := I * FloydSize + J;
          Via := Matrix[I * FloydSize + K] + Matrix[K * FloydSize + J];
          If Via < Matrix[Index] then
            Matrix[Index] := Via;
        end;
    Digest := Digest + UInt64(Matrix[FloydSize - 1]);
  end;
  Result := Digest;
end;

function CaseJacobi2D(Iterations: Integer): UInt64;
var
  Iteration, Step, I, J, Index: Integer;
  S: Double;
  Digest: UInt64;
begin
  Digest := 0;
  for Iteration := 1 to Iterations do
  begin
    Move(GridInitial[0], GridA[0], Length(GridA) * SizeOf(Double));
    Move(GridInitial[0], GridB[0], Length(GridB) * SizeOf(Double));
    for Step := 1 to 4 do
    begin
      for I := 1 to GridSize - 2 do
        for J := 1 to GridSize - 2 do
        begin
          Index := I * GridSize + J;
          GridB[Index] := (GridA[Index] + GridA[Index - 1] + GridA[Index + 1] +
            GridA[Index - GridSize] + GridA[Index + GridSize]) * 0.2;
        end;
      for I := 1 to GridSize - 2 do
        for J := 1 to GridSize - 2 do
        begin
          Index := I * GridSize + J;
          GridA[Index] := GridB[Index];
        end;
    end;
    S := GridA[GridSize + 1] +
      GridA[(GridSize div 2) * GridSize + GridSize div 2];
    Digest := Digest + PUInt64(@S)^;
  end;
  Result := Digest;
end;

procedure Fft(var Data: array of TComplex);
var
  I, J, K, M, Half: Integer;
  Angle, WRe, WIm, URe, UIm, TRe, TIm: Double;
  Temp: TComplex;
begin
  J := 0;
  for I := 1 to High(Data) do
  begin
    K := Length(Data) shr 1;
    while (J and K) <> 0 do
    begin
      J := J xor K;
      K := K shr 1;
    end;
    J := J xor K;
    If I < J then
    begin
      Temp := Data[I]; Data[I] := Data[J]; Data[J] := Temp;
    end;
  end;
  M := 2;
  while M <= Length(Data) do
  begin
    Half := M shr 1;
    for K := 0 to Half - 1 do
    begin
      Angle := -2.0 * PiValue * K / M;
      WRe := Cos(Angle); WIm := Sin(Angle);
      I := K;
      while I < Length(Data) do
      begin
        J := I + Half;
        TRe := WRe * Data[J].Re - WIm * Data[J].Im;
        TIm := WRe * Data[J].Im + WIm * Data[J].Re;
        URe := Data[I].Re; UIm := Data[I].Im;
        Data[I].Re := URe + TRe; Data[I].Im := UIm + TIm;
        Data[J].Re := URe - TRe; Data[J].Im := UIm - TIm;
        Inc(I, M);
      end;
    end;
    M := M shl 1;
  end;
end;

function CaseFft1024(Iterations: Integer): UInt64;
var
  Data: array of TComplex;
  I: Integer;
  S: Double;
begin
  SetLength(Data, FftSize);
  for I := 1 to Iterations do
  begin
    Move(FftInput[0], Data[0], Length(Data) * SizeOf(TComplex));
    Fft(Data);
  end;
  S := Data[1].Re + Data[17].Im + Data[511].Re;
  Result := UInt64(Trunc((S + 16.0) * 1000000000.0));
end;

function CaseConvolution(Iterations: Integer): UInt64;
var
  Iteration, X, Y, Dx, Dy: Integer;
  S, Digest: Single;
begin
  for Iteration := 1 to Iterations do
    for Y := 1 to ImageSize - 2 do
      for X := 1 to ImageSize - 2 do
      begin
        S := 0;
        for Dy := -1 to 1 do
          for Dx := -1 to 1 do
            S := S + ImageInput[(Y + Dy) * ImageSize + X + Dx] *
              (1.0 / 9.0);
        ImageOutput[Y * ImageSize + X] := S;
      end;
  Digest := ImageOutput[ImageSize + 1] +
    ImageOutput[(ImageSize div 2) * ImageSize + ImageSize div 2];
  Result := PUInt32(@Digest)^;
end;

function CaseStateMachine(Iterations: Integer): UInt64;
type
  TState = (stStart, stSign, stInteger, stDot, stFraction, stExponent,
    stExponentSign, stExponentDigits, stError);
var
  Iteration, I: Integer;
  State: TState;
  Ch: AnsiChar;
  Valid, Invalid: UInt64;

  procedure FinishToken;
  begin
    If State in [stInteger, stFraction, stExponentDigits] then
      Inc(Valid)
    else If State <> stStart then
      Inc(Invalid);
    State := stStart;
  end;

begin
  Valid := 0;
  Invalid := 0;
  for Iteration := 1 to Iterations do
  begin
    State := stStart;
    for I := 1 to Length(StateInput) do
    begin
      Ch := StateInput[I];
      If Ch = ' ' then
      begin
        FinishToken;
        Continue;
      end;
      case State of
        stStart: If Ch in ['+', '-'] then State := stSign
          else If Ch in ['0'..'9'] then State := stInteger else State := stError;
        stSign: If Ch in ['0'..'9'] then State := stInteger else State := stError;
        stInteger: If Ch = '.' then State := stDot
          else If Ch in ['e', 'E'] then State := stExponent
          else If not (Ch in ['0'..'9']) then State := stError;
        stDot: If Ch in ['0'..'9'] then State := stFraction else State := stError;
        stFraction: If Ch in ['e', 'E'] then State := stExponent
          else If not (Ch in ['0'..'9']) then State := stError;
        stExponent: If Ch in ['+', '-'] then State := stExponentSign
          else If Ch in ['0'..'9'] then State := stExponentDigits else State := stError;
        stExponentSign: If Ch in ['0'..'9'] then State := stExponentDigits else State := stError;
        stExponentDigits: If not (Ch in ['0'..'9']) then State := stError;
        stError: ;
      end;
    end;
    FinishToken;
  end;
  Result := Valid or (Invalid shl 32);
end;

function CaseLinkedList(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Head, Node, Current, Previous: PListNode;
  Digest: UInt64;
begin
  Digest := 0;
  for Iteration := 1 to Iterations do
  begin
    Head := nil;
    for I := 0 to 511 do
    begin
      GetMem(Node, SizeOf(TListNode));
      Node^.Key := (I * 40503 + 17) and 65535;
      Node^.Value := I;
      Previous := nil;
      Current := Head;
      while (Current <> nil) and (Current^.Key < Node^.Key) do
      begin
        Previous := Current;
        Current := Current^.Next;
      end;
      Node^.Next := Current;
      If Previous = nil then Head := Node else Previous^.Next := Node;
    end;
    Current := Head;
    while Current <> nil do
    begin
      Digest := Digest + UInt64(Current^.Key xor Current^.Value);
      Node := Current^.Next;
      FreeMem(Current);
      Current := Node;
    end;
  end;
  Result := Digest;
end;

procedure InitializeData;
var
  I, J: Integer;
  X: UInt64;
begin
  SetLength(SpectralU, SpectralSize);
  SetLength(SpectralV, SpectralSize);
  SetLength(SpectralTmp, SpectralSize);
  SetLength(StreamA, StreamCount);
  SetLength(StreamB, StreamCount);
  SetLength(StreamC, StreamCount);
  SetLength(GridInitial, GridSize * GridSize);
  SetLength(GridA, GridSize * GridSize);
  SetLength(GridB, GridSize * GridSize);
  SetLength(FloydBase, FloydSize * FloydSize);
  SetLength(ImageInput, ImageSize * ImageSize);
  SetLength(ImageOutput, ImageSize * ImageSize);
  SetLength(FftInput, FftSize);
  X := UInt64($D1B54A32D192ED03);
  for I := 0 to High(StreamA) do
  begin
    StreamA[I] := 1.0 + (I and 255) * 0.001;
    StreamB[I] := 2.0 + (I and 127) * 0.002;
    StreamC[I] := 0;
  end;
  for I := 0 to High(GridInitial) do
  begin
    GridInitial[I] := (I mod GridSize) * 0.01 + (I div GridSize) * 0.02;
    GridA[I] := GridInitial[I];
    GridB[I] := GridInitial[I];
  end;
  for I := 0 to FloydSize - 1 do
    for J := 0 to FloydSize - 1 do
      If I = J then FloydBase[I * FloydSize + J] := 0
      else FloydBase[I * FloydSize + J] := 1 + ((I * 17 + J * 29) mod 1000);
  for I := 0 to High(ImageInput) do
  begin
    X := X * UInt64(2862933555777941757) + UInt64(3037000493);
    ImageInput[I] := (X and 65535) / 65535.0;
  end;
  for I := 0 to High(FftInput) do
  begin
    FftInput[I].Re := Sin(2 * PiValue * I / 31) + Cos(2 * PiValue * I / 17);
    FftInput[I].Im := 0;
  end;
  StateInput := '';
  for I := 0 to 255 do
    StateInput := StateInput + RawByteString(AnsiString(IntToStr(I) + ' ' +
      IntToStr(-I) + '.125 ' + IntToStr(I) + 'e-3 bad' + IntToStr(I) + ' '));
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_workloads', Profile, SelectedCase);
  InitializeData;
  Found := False;
  PulseRunCase('pulse_workloads', 'spectral-norm-128', 'codegen', 'Pascal',
    @CaseSpectralNorm, SpectralSize * SpectralSize * 4, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_workloads', 'nbody-5x100', 'codegen+math', 'Pascal',
    @CaseNBody, 100 * 10, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'binary-trees-depth-10', 'codegen+mm',
    'Pascal', @CaseBinaryTrees, 2047, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'mandelbrot-128', 'codegen', 'Pascal',
    @CaseMandelbrot, 128 * 128, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'fannkuch-8', 'codegen', 'Pascal',
    @CaseFannkuch, 40320, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'stream-copy', 'memory', 'Pascal',
    @CaseStreamCopy, StreamCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'stream-scale', 'memory', 'Pascal',
    @CaseStreamScale, StreamCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'stream-add', 'memory', 'Pascal',
    @CaseStreamAdd, StreamCount * 3, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'stream-triad', 'memory', 'Pascal',
    @CaseStreamTriad, StreamCount * 3, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'floyd-warshall-64', 'codegen+memory',
    'Pascal', @CaseFloydWarshall, FloydSize * FloydSize * FloydSize, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'jacobi-2d-128x4', 'codegen+memory', 'Pascal',
    @CaseJacobi2D, GridSize * GridSize * 8, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'fft-1024', 'codegen+math', 'Pascal',
    @CaseFft1024, FftSize * 10, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'convolution-256', 'codegen+memory', 'Pascal',
    @CaseConvolution, ImageSize * ImageSize * 9, Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'numeric-state-machine', 'codegen', 'Pascal',
    @CaseStateMachine, Length(StateInput), Profile, SelectedCase, Found);
  PulseRunCase('pulse_workloads', 'linked-list-insert-sort-512', 'codegen+mm',
    'Pascal', @CaseLinkedList, 512, Profile, SelectedCase, Found);
  PulseFinish('pulse_workloads', SelectedCase, Found);
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
