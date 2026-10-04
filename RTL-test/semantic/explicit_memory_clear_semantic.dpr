program explicit_memory_clear_semantic;
{$IFDEF FPC}{$mode delphi}{$asmmode intel}{$ENDIF}
{$INLINE OFF}
uses explicit_memory_clear_unit;
var
  Saved: Pointer;
  Source: array[0..63] of Byte;
  Count: Integer;

procedure Observe(var Buffer);
begin
  Saved := @Buffer;
  If PByte(Saved)^ <> 165 then Halt(11);
end;

function IsClear(P: Pointer): Boolean; assembler; {$IFDEF FPC}nostackframe;{$ENDIF}
asm
  {$IFDEF MSWINDOWS}mov rdx, rcx{$ELSE}mov rdx, rdi{$ENDIF}
  xor ecx, ecx
@@scan:
  cmp byte ptr [rdx+rcx], 0
  jne @@bad
  inc ecx
  cmp ecx, 64
  jne @@scan
  mov eax, 1
  ret
@@bad:
  xor eax, eax
end;

function HasPattern(P: Pointer; Count: Integer): Boolean; assembler; {$IFDEF FPC}nostackframe;{$ENDIF}
asm
  {$IFDEF MSWINDOWS}mov r8d, edx
  mov rdx, rcx{$ELSE}mov r8d, esi
  mov rdx, rdi{$ENDIF}
  xor ecx, ecx
@@scan:
  mov eax, 165
  cmp ecx, r8d
  jae @@check
  xor eax, eax
@@check:
  cmp byte ptr [rdx+rcx], al
  jne @@bad
  inc ecx
  cmp ecx, 65
  jne @@scan
  mov eax, 1
  ret
@@bad:
  xor eax, eax
end;

procedure ClearBoundary(Count: Integer);
var Key: array[0..64] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  case Count of
    0: FillChar(Key, 0, 0);
    1: FillChar(Key, 1, 0);
    3: FillChar(Key, 3, 0);
    5: FillChar(Key, 5, 0);
    7: FillChar(Key, 7, 0);
    8: FillChar(Key, 8, 0);
    9: FillChar(Key, 9, 0);
    16: FillChar(Key, 16, 0);
    63: FillChar(Key, 63, 0);
    64: FillChar(Key, 64, 0);
    65: FillChar(Key, 65, 0);
  end;
end;

{$INLINE ON}
procedure ClearPpuInline;
var Key: array[0..63] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  ClearInline(Key);
end;
{$INLINE OFF}

procedure ClearChar;
var Key: array[0..63] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  FillChar(Key, SizeOf(Key), 0);
end;

{$IFDEF FPC}
procedure ClearByte;
var Key: array[0..63] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  FillByte(Key, 64, 0);
end;
procedure ClearWord;
var Key: array[0..63] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  FillWord(Key, 32, 0);
end;
procedure ClearDWord;
var Key: array[0..63] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  FillDWord(Key, 16, 0);
end;
procedure ClearQWord;
var Key: array[0..63] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  FillQWord(Key, 8, 0);
end;
{$ENDIF}

procedure ClearMove;
var Key: array[0..63] of Byte;
begin
  FillChar(Key, SizeOf(Key), 165);
  Observe(Key);
  Move(Source, Key, SizeOf(Key));
end;

begin
  ClearChar;
  If not IsClear(Saved) then Halt(21);
  {$IFDEF FPC}
  ClearByte;
  If not IsClear(Saved) then Halt(22);
  ClearWord;
  If not IsClear(Saved) then Halt(23);
  ClearDWord;
  If not IsClear(Saved) then Halt(24);
  ClearQWord;
  If not IsClear(Saved) then Halt(25);
  {$ENDIF}
  ClearMove;
  If not IsClear(Saved) then Halt(26);
  for Count in [0,1,3,5,7,8,9,16,63,64,65] do begin
    ClearBoundary(Count);
    If not HasPattern(Saved, Count) then Halt(30 + Count);
  end;
  ClearPpuInline;
  If not IsClear(Saved) then Halt(27);
  WriteLn('EXPLICIT_MEMORY_CLEAR_SEMANTIC_PASS');
end.
