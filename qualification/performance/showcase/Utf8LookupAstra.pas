unit Utf8LookupAstra;

// Stand-only alternative: short keys and the long-key arena offset share space.
// The hash and linear probing match Utf8Lookup; no input padding is required.
{$mode delphiunicode}
{$H+}

interface

uses SysUtils, Utf8Lookup;

type
  TUtf8HybridTable = class(TUtf8Lookup)
  private type
    TSlot = record
      Hash, Len: UInt32;
      Value: UInt64;
      case Boolean of
        False: (ShortText: array[0..15] of Byte);
        True: (Offset: SizeUInt);
    end;
  private
    FSlots: TArray<TSlot>;
    FArena: TBytes;
    FUsed: SizeUInt;
  public
    constructor Create(ExpectedCount: SizeInt); override;
    procedure Add(P: Pointer; N: SizeInt; Value: UInt64); override;
    function TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean; override;
  end;

implementation

constructor TUtf8HybridTable.Create(ExpectedCount: SizeInt);
var Capacity: SizeInt;
begin
  inherited Create(ExpectedCount);
  Capacity := 8;
  while Capacity < ExpectedCount * 2 do Capacity := Capacity * 2;
  SetLength(FSlots, Capacity);
end;

procedure TUtf8HybridTable.Add(P: Pointer; N: SizeInt; Value: UInt64);
var H: UInt32; I: SizeInt; Text: Pointer; Needed, Capacity: SizeUInt;
begin
  CheckInsert(P, N);
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    If (FSlots[I].Hash = H) and (FSlots[I].Len = N) then begin
      If N <= SizeOf(FSlots[I].ShortText) then Text := @FSlots[I].ShortText
      else Text := @FArena[FSlots[I].Offset];
      If SameBytes(Text, P, N) then raise EArgumentException.Create('Duplicate key');
    end;
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  If N <= SizeOf(FSlots[I].ShortText) then begin
    If N <> 0 then Move(P^, FSlots[I].ShortText, N);
  end else begin
    Needed := FUsed + SizeUInt(N);
    If Needed > SizeUInt(Length(FArena)) then begin
      Capacity := Length(FArena);
      If Capacity = 0 then Capacity := 256;
      while Capacity < Needed do Capacity := Capacity * 2;
      SetLength(FArena, Capacity);
    end;
    Move(P^, FArena[FUsed], N);
    FSlots[I].Offset := FUsed;
    FUsed := Needed;
  end;
  FSlots[I].Len := N;
  FSlots[I].Value := Value;
  FSlots[I].Hash := H;
  Inc(FCount);
end;

function TUtf8HybridTable.TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean;
var H: UInt32; I: SizeInt; Text: Pointer;
begin
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    If (FSlots[I].Hash = H) and (FSlots[I].Len = N) then begin
      If N <= SizeOf(FSlots[I].ShortText) then Text := @FSlots[I].ShortText
      else Text := @FArena[FSlots[I].Offset];
      If SameBytes(Text, P, N) then begin
        Value := FSlots[I].Value;
        Exit(True);
      end;
    end;
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  Value := 0;
  Result := False;
end;


end.
