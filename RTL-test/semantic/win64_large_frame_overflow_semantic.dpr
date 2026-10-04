program win64_large_frame_overflow_semantic;

{%TARGET=win64}

{ A frame of a page or more is probed page by page, and the probe that finds no stack left
  raises the stack overflow.  The unwinder has to take that probe for part of the prologue it
  is: the allocation is the frame's from the instruction that allocates on, and the probes run
  in front of it with rsp where it was (doc/COMPILER_FIXES.md, "Win64 frames of 4 KB and
  more").  A recursion through a frame of four pages (probed one by one) and one of sixteen
  (probed in a loop) runs out of stack; the overflow has to arrive as EStackOverflow in the
  except of the outermost caller, whose locals kept in registers are what they were. }

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  SysUtils;

var
  Failures: Integer = 0;
  Sink: Int64;

procedure Check(Condition: Boolean; const What: string);
begin
  If not Condition then begin
    Inc(Failures);
    WriteLn('FAIL ', What);
  end;
end;

function DeepSmall(Level: Integer): Int64; noinline;
var
  Frame: array[0..16383] of Byte;  { four pages: probed one store a page }
begin
  Frame[Level and 16383] := Byte(Level);
  Result := DeepSmall(Level + 1) + Frame[(Level * 7) and 16383];
end;

function DeepLarge(Level: Integer): Int64; noinline;
var
  Frame: array[0..65535] of Byte;  { sixteen pages: probed in a loop }
begin
  Frame[Level and 65535] := Byte(Level);
  Result := DeepLarge(Level + 1) + Frame[(Level * 7) and 65535];
end;

function Overflow(Which: Integer): string; noinline;
var
  A, B, C, D: Int64;
  I: Integer;
begin
  A := $1111111111111111;
  B := $2222222222222222;
  C := $3333333333333333;
  D := $4444444444444444;
  Result := 'nothing raised';
  for I := 1 to 1 do begin
    try
      If Which = 0 then
        Sink := DeepSmall(0)
      else
        Sink := DeepLarge(0);
    except
      on E: EStackOverflow do
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
  Which: Integer;
  Got: string;
begin
  { one overflow a process: Windows gives a thread its guard page back only by request.
    Without a parameter (the RTL-test run) the frame probed in a loop. }
  Which := StrToIntDef(ParamStr(1), 1);
  Got := Overflow(Which);
  Check(Got = 'raised', 'a stack overflow in a frame of ' + IntToStr(4 + 12 * Which) + ' pages: ' + Got);
  If Failures <> 0 then
    Halt(1);
  WriteLn('WIN64_LARGE_FRAME_OVERFLOW_SEMANTIC_PASS');
end.
