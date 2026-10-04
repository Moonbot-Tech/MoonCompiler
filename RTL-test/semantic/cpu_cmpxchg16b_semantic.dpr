program cpu_cmpxchg16b_semantic;

{ cpu.InterlockedCompareExchange128 as a program meets it: the exchange and the result on a target
  it may take, and a fault on one it may not - not aligned to 16 bytes (cmpxchg16b raises #GP) or
  not there.  The routine keeps the new value in rcx:rbx, and rbx is the caller's: the exception
  has to reach the caller's except, with the caller's locals kept in registers what they were
  (doc/ASM_LAYOUT_RULES.md, "Unwinding hand-written frames"). }

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  SysUtils, cpu;

type
  PPair = ^Int128Rec;

var
  Failures: Integer = 0;
  Buffer: array[0..7] of Int128Rec;

procedure Check(Condition: Boolean; const What: string);
begin
  If not Condition then begin
    Inc(Failures);
    WriteLn('FAIL ', What);
  end;
end;

function Pair(Lo, Hi: QWord): Int128Rec;
begin
  Result.Lo := Lo;
  Result.Hi := Hi;
end;

procedure Exchange;
var
  Target: ^Int128Rec;
  Old: Int128Rec;
begin
  Target := Pointer((PtrUInt(@Buffer[1]) + 15) and not PtrUInt(15));
  Target^ := Pair($1111, $2222);
  Old := InterlockedCompareExchange128(Target^, Pair($3333, $4444), Pair($1111, $2222));
  Check((Old.Lo = $1111) and (Old.Hi = $2222), 'the old value of a matching compare');
  Check((Target^.Lo = $3333) and (Target^.Hi = $4444), 'the new value stored on a match');
  Old := InterlockedCompareExchange128(Target^, Pair($5555, $6666), Pair($1111, $2222));
  Check((Old.Lo = $3333) and (Old.Hi = $4444), 'the current value of a failing compare');
  Check((Target^.Lo = $3333) and (Target^.Hi = $4444), 'nothing stored when the compare fails');
end;

function Fault(Target: Pointer): string; noinline;
var
  A, B, C, D: Int64;
  I: Integer;
begin
  A := $1111111111111111;
  B := $2222222222222222;
  C := $3333333333333333;
  D := $4444444444444444;
  Result := 'nothing raised';
  for I := 1 to 2 do begin
    try
      InterlockedCompareExchange128(PPair(Target)^, Pair(QWord(A), QWord(B)), Pair(QWord(C), QWord(D)));
    except
      on E: Exception do
        Result := 'raised';
    end;
    A := A + D - $4444444444444444;
    B := B xor (C - $3333333333333333);
  end;
  If (A <> $1111111111111111) or (B <> $2222222222222222) or (C <> $3333333333333333) or
     (D <> $4444444444444444) then
    Result := Result + ', the caller''s registers were not restored';
end;

var
  Got: string;
begin
  If InterlockedCompareExchange128Support then begin
    Exchange;
    Got := Fault(Pointer((PtrUInt(@Buffer[1]) + 15) and not PtrUInt(15) + 8));
    Check(Got = 'raised', 'cmpxchg16b on a target not aligned to 16 bytes: ' + Got);
    Got := Fault(nil);
    Check(Got = 'raised', 'cmpxchg16b on a target that is not there: ' + Got);
  end else
    WriteLn('no cmpxchg16b on this CPU');
  If Failures <> 0 then
    Halt(1);
  WriteLn('CPU_CMPXCHG16B_SEMANTIC_PASS');
end.
