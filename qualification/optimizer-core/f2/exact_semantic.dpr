program exact_semantic;

{$IFDEF FPC}
{$MODE DELPHI}
{$ASMMODE INTEL}
{$ENDIF}
{$Q-}{$R-}

uses SysUtils;

type
  TSide = (LowSide, HighSide);
  TCell = record
    Value: Double;
    function Side: TSide; inline;
  end;
  TCells = array of TCell;

procedure Check(Value: Boolean; const Name: string);
begin
  If not Value then begin
    WriteLn('FAIL:', Name);
    Halt(1);
  end;
end;

function GetControl: Cardinal; assembler;
var
  Value: Cardinal;
asm
  stmxcsr Value
  mov eax, Value
end;

procedure PutControl(Value: Cardinal); assembler;
var
  State: Cardinal;
asm
  mov eax, Value
  mov State, eax
  ldmxcsr State
end;

function OracleDouble(Value: Int64): Double; assembler;
asm
  mov rax, Value
  xorps xmm0, xmm0
  cvtsi2sd xmm0, rax
end;

function OracleSingle(Value: Integer): Single; assembler;
asm
  mov eax, Value
  xorps xmm0, xmm0
  cvtsi2ss xmm0, eax
end;

function TCell.Side: TSide;
begin
  If Value < 0 then
    Result := LowSide
  else
    Result := HighSide;
end;

function ExactSigned(Value, Count: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Value;
    Inc(I);
  end;
end;

function ExactUnsigned(Value: Cardinal; Count: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Value;
    Inc(I);
  end;
end;

function ExactSmall(Value: Word; Count: Integer): Single; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Single(Value);
    Inc(I);
  end;
end;

function ExactWidened(Value, Count: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Double(Int64(Value));
    Inc(I);
  end;
end;

function WithTemps(Window: Integer; const Cells: TCells): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Length(Cells) - 1 do
    with Cells[I] do
      If Side = HighSide then
        Result := Result + Double(Window);
end;

function TempInteger(Scale: Int64; const Cells: TCells): Int64; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Length(Cells) - 1 do
    If Cells[I].Side = HighSide then
      Result := Result + Scale * 257;
end;

function Snapshot(const Converted: Double; var Original: Integer): Double; inline;
begin
  Inc(Original);
  Result := Converted;
end;

function InlineAlias(Value: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := Snapshot(Double(Value), Value);
end;
function Mutated(Value, Count: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Value;
    Inc(Value);
    Inc(I);
  end;
end;

function Escaped(Value, Count: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
  P: PInteger;
begin
  P := @Value;
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Value;
    Inc(P^);
    Inc(I);
  end;
end;

function Inexact64(Value: Int64; Count: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Double(Value);
    Inc(I);
  end;
end;

function InexactSingle(Value, Count: Integer): Single; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Single(Value);
    Inc(I);
  end;
end;

{$Q+}
function CheckedChild(Value, Count: Integer): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Double(Value + 1);
    Inc(I);
  end;
end;
{$Q-}

function Pressure(Value, Count: Integer; A, B, C, D, E, F, G: Double): Double; {$IFDEF FPC}noinline;{$ENDIF}
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + Value + A + B + C + D + E + F + G;
    A := A + 1;
    B := B + 2;
    C := C + 3;
    D := D + 4;
    E := E + 5;
    F := F + 6;
    G := G + 7;
    Inc(I);
  end;
end;

var
  Saved, Control, Mode, Flags: Cardinal;
  V, Count, I: Integer;
  Cells: TCells;
  Got, Expected: Double;
  GotSingle, ExpectedSingle: Single;
const
  SignedValues: array[0..4] of Integer = (0, 1, -1, Low(Integer), High(Integer));
  UnsignedValues: array[0..3] of Cardinal = (0, 1, $80000000, $FFFFFFFF);
begin
  Saved := GetControl;
  SetLength(Cells, 5);
  for I := 0 to High(Cells) do
    Cells[I].Value := I - 2;
  try
    for Mode := 0 to 3 do begin
      Control := (Saved and not $603F) or $1F80 or (Mode shl 13);
      for Count := 0 to 3 do begin
        for V in SignedValues do begin
          Expected := OracleDouble(Int64(V) * Count);
          PutControl(Control);
          Got := ExactSigned(V, Count);
          Flags := GetControl and $3F;
          Check((Got = Expected) and (Flags = 0), 'exact signed');
          PutControl(Control);
          Got := ExactWidened(V, Count);
          Flags := GetControl and $3F;
          Check((Got = Expected) and (Flags = 0), 'exact widened');
        end;
        for I := 0 to High(UnsignedValues) do begin
          Expected := OracleDouble(Int64(UnsignedValues[I]) * Count);
          PutControl(Control);
          Got := ExactUnsigned(UnsignedValues[I], Count);
          Flags := GetControl and $3F;
          Check((Got = Expected) and (Flags = 0), 'exact unsigned');
        end;
        ExpectedSingle := OracleSingle(65535 * Count);
        PutControl(Control);
        GotSingle := ExactSmall(65535, Count);
        Flags := GetControl and $3F;
        Check((GotSingle = ExpectedSingle) and (Flags = 0), 'exact small');
      end;
      PutControl(Control);
      Got := Inexact64(9007199254740993, 0);
      Flags := GetControl and $3F;
      Check((Got = 0) and (Flags = 0), 'inexact double zero trip');
      PutControl(Control);
      GotSingle := InexactSingle(16777217, 0);
      Flags := GetControl and $3F;
      Check((GotSingle = 0) and (Flags = 0), 'inexact single zero trip');
      PutControl(Control);
      Expected := OracleDouble(9007199254740993);
      PutControl(Control);
      Got := Inexact64(9007199254740993, 1);
      Flags := GetControl and $3F;
      Check((Got = Expected) and (Flags = $20), 'inexact double rounding');
      PutControl(Control);
      ExpectedSingle := OracleSingle(16777217);
      PutControl(Control);
      GotSingle := InexactSingle(16777217, 1);
      Flags := GetControl and $3F;
      Check((GotSingle = ExpectedSingle) and (Flags = $20), 'inexact single rounding');
      PutControl(Control);
      Check(WithTemps(7, Cells) = 21, 'with inline temps');
      Check(TempInteger(7, Cells) = 5397, 'integer with temps');
      Check(InlineAlias(7) = 7, 'inline conversion snapshot');
      Check(Mutated(5, 4) = 26, 'mutated parameter');
      Check(Escaped(5, 4) = 26, 'escaped parameter');
      Check(CheckedChild(High(Integer), 0) = 0, 'checked zero trip');
      Check(Pressure(5, 3, 1, 2, 3, 4, 5, 6, 7) = 183, 'pressure');
      PutControl(Control or $20);
      Got := ExactSigned(7, 3);
      Flags := GetControl and $3F;
      Check((Got = 21) and (Flags = $20), 'sticky precision preserved');
    end;
  finally
    PutControl(Saved);
  end;
  WriteLn('EXACT-LICM:PASS');
end.
