program OomRegisters;
{$mode delphi}{$asmmode intel}
uses mormot.core.fpcx64mm, SysUtils;
var
  Kind, Failed: Integer;
  P: Pointer;
  SeenRbx, SeenR14: QWord;
  Caught: Boolean;
  Held: array[0..99999] of Pointer;
  HeldCount, J: Integer;

procedure RunCanary; noinline;
begin
  asm
    mov rbx, $1122334455667788
    mov r14, $2233445566778899
  end ['RBX', 'R14'];
  try
    case Kind of
      0: P := GetMem(High(PtrUInt));
      1: P := AllocMem(High(PtrUInt));
      2, 3: ReallocMem(P, High(PtrUInt));
      4: P := GetMem(512);
    end;
  except
    on EOutOfMemory do begin
      asm
        mov [rip + SeenRbx], rbx
        mov [rip + SeenR14], r14
      end;
      Caught := True;
    end;
  end;
end;

var
  OldP: Pointer;
begin
  for Kind := 0 to 4 do begin
    P := nil;
    If Kind = 2 then P := GetMem(64);
    If Kind = 3 then P := GetMem(2 * 1024 * 1024);
    If Kind = 4 then begin
      ReturnNilIfGrowHeapFails := True;
      OomArm(1);
      repeat
        If HeldCount = Length(Held) then Halt(5);
        Held[HeldCount] := GetMem(512);
        If Held[HeldCount] = nil then Break;
        Inc(HeldCount);
      until False;
      ReturnNilIfGrowHeapFails := False;
    end;
    OldP := P;
    Caught := False;
    SeenRbx := 0;
    SeenR14 := 0;
    RunCanary;
    OomArm(0);
    If not Caught or (SeenRbx <> $1122334455667788) or (SeenR14 <> $2233445566778899) or (P <> OldP) then begin
      WriteLn('REGISTER_FAIL kind=', Kind, ' caught=', Ord(Caught), ' rbx=', IntToHex(SeenRbx, 16), ' r14=', IntToHex(SeenR14, 16));
      Inc(Failed);
    end;
    If P <> nil then FreeMem(P);
    for J := 0 to HeldCount - 1 do FreeMem(Held[J]);
    HeldCount := 0;
    If CurrentHeapFragmentationStatus.Errors <> 0 then Halt(2);
    If Caught and (SeenRbx = $1122334455667788) and (SeenR14 = $2233445566778899) then
      WriteLn('REGISTER_PASS kind=', Kind);
  end;
  If Failed <> 0 then Halt(1);
end.
