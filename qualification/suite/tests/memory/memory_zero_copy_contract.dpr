program memory_zero_copy_contract;

{$APPTYPE CONSOLE}
{$ifdef FPC}
  {$mode delphi}
  {$asmmode intel}
{$endif}

{ AllocMem must return zeroed memory and ReallocMem must carry the old contents over, for every size
  and whatever instruction does the work: the 16-byte loop (below 256 bytes), the loop of two 16-byte
  steps per turn (from 256 bytes to the "rep" threshold) and "rep stosd" / "rep movsb" (above it).
  The block behind the one that is written must keep its header and its contents: the loops write
  whole 16-byte chunks and must not write one chunk too many.

  With FPCMM_ERMSFILL_TEST the zeroing threshold is forced to both of its values (768 and 2048), so
  one machine proves both; the value chosen at start-up is checked against the processor vendor. }

uses
  mormot.core.fpcx64mm;

const
  MaxSize = 5000;
  Dirty = $A5;

var
  Failures: Integer;
  MovedIntoGap: Integer; // moves that landed between two live blocks: the ones that prove the bounds

procedure Fail(const Msg: string; Size: PtrUInt);
begin
  WriteLn('FAIL ', Msg, ' size=', Size);
  Inc(Failures);
  if Failures > 20 then
    Halt(1);
end;

function AllBytes(P: PByte; Count: PtrUInt; Value: Byte): Boolean;
var
  I: PtrUInt;
begin
  Result := False;
  for I := 0 to Count - 1 do
    if P[I] <> Value then
      Exit;
  Result := True;
end;

procedure Paint(P: PByte; Count: PtrUInt; Seed: PtrUInt);
var
  I: PtrUInt;
begin
  for I := 0 to Count - 1 do
    P[I] := Byte(I * 7 + Seed);
end;

function Painted(P: PByte; Count: PtrUInt; Seed: PtrUInt): Boolean;
var
  I: PtrUInt;
begin
  Result := False;
  for I := 0 to Count - 1 do
    if P[I] <> Byte(I * 7 + Seed) then
      Exit;
  Result := True;
end;

// three blocks of one size in a row; the middle one goes back and is the next block of that size
procedure CheckAllocMem(Size: PtrUInt);
var
  A, B, C, Z: PByte;
  HeaderC: PtrUInt;
begin
  GetMem(A, Size);
  GetMem(B, Size);
  GetMem(C, Size);
  FillChar(A^, Size, Dirty);
  FillChar(B^, Size, Dirty);
  FillChar(C^, Size, Dirty);
  HeaderC := PPtrUInt(C - SizeOf(Pointer))^;
  FreeMem(B);
  Z := AllocMem(Size);
  if not AllBytes(Z, Size, 0) then
    Fail('AllocMem left a byte that is not zero', Size);
  if Z = B then
  begin
    if PPtrUInt(C - SizeOf(Pointer))^ <> HeaderC then
      Fail('AllocMem wrote over the header of the next block', Size);
    if not AllBytes(C, Size, Dirty) or not AllBytes(A, Size, Dirty) then
      Fail('AllocMem wrote into a neighbour block', Size);
  end;
  FreeMem(Z);
  FreeMem(C);
  FreeMem(A);
end;

// the new block of a moving ReallocMem is the block freed last in its class: it lies between X and Z
procedure CheckReallocMove(Size, NewSize: PtrUInt);
var
  P, X, Y, Z: PByte;
  HeaderZ, Kept: PtrUInt;
begin
  GetMem(P, Size);
  Paint(P, Size, Size);
  GetMem(X, NewSize);
  GetMem(Y, NewSize);
  GetMem(Z, NewSize);
  FillChar(X^, NewSize, Dirty);
  FillChar(Z^, NewSize, Dirty);
  HeaderZ := PPtrUInt(Z - SizeOf(Pointer))^;
  FreeMem(Y);
  ReallocMem(P, NewSize);
  Kept := Size;
  if NewSize < Kept then
    Kept := NewSize;
  if not Painted(P, Kept, Size) then
    Fail('ReallocMem lost the contents', Size);
  if P = Y then
  begin
    Inc(MovedIntoGap);
    if PPtrUInt(Z - SizeOf(Pointer))^ <> HeaderZ then
      Fail('ReallocMem wrote over the header of the next block', Size);
    if not AllBytes(Z, NewSize, Dirty) or not AllBytes(X, NewSize, Dirty) then
      Fail('ReallocMem wrote into a neighbour block', Size);
  end;
  FreeMem(P);
  FreeMem(Z);
  FreeMem(X);
end;

procedure AllSizes;
var
  Size: PtrUInt;
begin
  for Size := 1 to MaxSize do
  begin
    CheckAllocMem(Size);
    CheckReallocMove(Size, Size * 2 + 17);   // growth that moves
    CheckReallocMove(Size * 5 + 128, Size);  // a small block moves when it shrinks below a quarter
  end;
end;

{$ifdef FPCMM_ERMSFILL_TEST}
function VendorIsAmd: Boolean; assembler; nostackframe;
asm
        mov     r8, rbx
        xor     eax, eax
        cpuid
        xor     eax, eax
        cmp     ecx, $444D4163 // "cAMD", the last third of "AuthenticAMD"
        jne     @no
        mov     al, 1
@no:    mov     rbx, r8
end;

procedure BothThresholds;
var
  AtStart, Expected: PtrUInt;
begin
  AtStart := Fpcx64mmTestErmsFillMinSize(0);
  if AtStart = 0 then
  begin
    WriteLn('profile without FPCMM_ERMS: one pass');
    AllSizes;
    Exit;
  end;
  if VendorIsAmd then
    Expected := 2048
  else
    Expected := 768;
  if AtStart <> Expected then
    Fail('zeroing threshold chosen at start-up', AtStart);
  Fpcx64mmTestErmsFillMinSize(768);
  AllSizes;
  Fpcx64mmTestErmsFillMinSize(2048);
  AllSizes;
  Fpcx64mmTestErmsFillMinSize(AtStart);
  WriteLn('thresholds 768 and 2048 checked, start-up value ', AtStart);
end;
{$endif FPCMM_ERMSFILL_TEST}

begin
  Failures := 0;
  {$ifdef FPCMM_ERMSFILL_TEST}
  BothThresholds;
  {$else}
  AllSizes;
  {$endif FPCMM_ERMSFILL_TEST}
  if MovedIntoGap < MaxSize div 2 then
    Fail('too few moves landed between two live blocks', MovedIntoGap);
  if Failures <> 0 then
    Halt(1);
  WriteLn('moves between two live blocks: ', MovedIntoGap);
  WriteLn('MEMORY_ZERO_COPY_CONTRACT_PASS');
end.
