program oom_injected;
{$mode delphi}{$H+}{$Q-}{$R-}
uses mormot.core.fpcx64mm, SysUtils {$ifdef MSWINDOWS}, Windows{$endif};
const MaxHeld = 100000;
var Held: array[0..MaxHeld - 1] of Pointer;
    HeldCount, J: Integer;
    P, OldP, Returned, Region, NextRegion, Reserved: Pointer;
    Name: string;
    OldSize, NewSize, OldCapacity, OldMapping, I: PtrUInt;
    Mask, Failures, Released: Cardinal;
    NilMode, Failed, WasLarge, SuccessCase, IsGet, IsAlloc: Boolean;
    {$ifdef MSWINDOWS} Info: TMemoryBasicInformation; {$endif}

procedure Require(B: Boolean; const Text: string);
begin
  If not B then begin OomArm(0); WriteLn('INJECTED_FAIL ', Text); Halt(1); end;
end;

procedure FillOld;
begin
  for I := 0 to OldSize - 1 do PByte(P)[I] := Byte(I * 17 + 83);
end;

procedure CheckOldData(Buffer: Pointer; Count: PtrUInt);
var J: PtrUInt;
begin
  for J := 0 to Count - 1 do
    Require(PByte(Buffer)[J] = Byte(J * 17 + 83), 'old data changed');
end;

procedure Exhaust(Size: PtrUInt);
var Q: Pointer;
begin
  ReturnNilIfGrowHeapFails := True;
  OomArm(1);
  repeat
    Q := GetMem(Size);
    If Q = nil then Break;
    Require(HeldCount < MaxHeld, 'exhaust bound');
    Held[HeldCount] := Q;
    Inc(HeldCount);
  until False;
  Require(OomFailures > 0, 'exhaust did not hit OS failure');
  OomArm(0);
end;

begin
  Name := ParamStr(1);
  IsGet := (Copy(Name, 1, 4) = 'get-') or (Name = 'overflow-get');
  IsAlloc := Copy(Name, 1, 6) = 'alloc-';
  NilMode := ParamStr(2) = 'nil';
  OldSize := 0;
  NewSize := 0;
  Mask := 15;
  SuccessCase := False;
  If Name = 'get-small' then NewSize := 512
  else If Name = 'alloc-small' then NewSize := 512
  else If Name = 'get-medium' then NewSize := 65536
  else If Name = 'alloc-medium' then NewSize := 65536
  else If Name = 'get-large' then NewSize := 2 shl 20
  else If Name = 'alloc-large' then NewSize := 2 shl 20
  else If Name = 'realloc-nil' then NewSize := 65536
  else If Name = 'small-medium' then begin OldSize := 64; NewSize := 65536; end
  else If Name = 'small-large' then begin OldSize := 64; NewSize := 2 shl 20; end
  else If Name = 'medium-large' then begin OldSize := 65536; NewSize := 2 shl 20; end
  else If Name = 'large-grow' then begin OldSize := 2 shl 20; NewSize := 8 shl 20; end
  else If Name = 'large-small' then begin OldSize := 2 shl 20; NewSize := 512; end
  else If Name = 'large-medium' then begin OldSize := 2 shl 20; NewSize := 65536; end
  else If Name = 'large-shrink' then begin OldSize := 8 shl 20; NewSize := 2 shl 20; end
  else If Name = 'overflow-get' then NewSize := High(PtrUInt)
  else If Name = 'overflow-realloc' then begin OldSize := 65536; NewSize := High(PtrUInt); end
  else If (Name = 'reserve-fail') or (Name = 'commit-fail') or (Name = 'commit-fallback') or (Name = 'inplace') then begin
    OldSize := 2 shl 20;
    NewSize := 8 shl 20;
    {$ifdef MSWINDOWS}
    Region := Windows.VirtualAlloc(nil, 32 shl 20, MEM_RESERVE, PAGE_READWRITE);
    Require(Region <> nil, 'fixture reserve');
    Require(Windows.VirtualFree(Region, 0, MEM_RELEASE), 'fixture release');
    OomPrefer(Region);
    {$else}
    Require(False, 'Windows-specific case');
    {$endif}
    If Name = 'reserve-fail' then Mask := 3
    else If Name = 'commit-fail' then Mask := 5
    else If Name = 'commit-fallback' then begin Mask := 4; SuccessCase := True; end
    else begin Mask := 0; SuccessCase := True; end;
  end
  else If Name = 'remap-fallback' then begin
    OldSize := 2 shl 20; NewSize := 8 shl 20; Mask := 8; SuccessCase := True;
  end else Require(False, 'unknown case');
  WasLarge := OldSize >= 2 shl 20;
  If OldSize <> 0 then begin
    P := GetMem(OldSize);
    OldP := P;
    OldCapacity := MemSize(P);
    FillOld;
    If WasLarge then begin
      OldMapping := OomLargeMapping(P);
      Require(OomLargeLinked(P), 'old block absent before operation');
    end;
    {$ifdef MSWINDOWS}
    If Region <> nil then begin
      NextRegion := PByte(Region) + OldMapping;
      Require(Windows.VirtualQuery(NextRegion, Info, SizeOf(Info)) <> 0, 'fixture query');
      Require(Info.State = MEM_FREE, 'next segment not free');
    end;
    {$endif}
  end;
  If NewSize < 2 shl 20 then Exhaust(NewSize);
  ReturnNilIfGrowHeapFails := NilMode;
  Returned := Pointer(1);
  OomArm(Mask);
  Failed := False;
  try
    If IsGet then Returned := GetMem(NewSize)
    else If IsAlloc then Returned := AllocMem(NewSize)
    else Returned := ReallocMem(P, NewSize);
    Failures := OomFailures;
    Reserved := OomReserved;
    Released := OomReleasedReservations;
    OomArm(0);
    If not SuccessCase then begin
      Require(NilMode, 'failure did not raise');
      Require(Returned = nil, 'ReturnNil did not return nil');
    end;
  except
    on E: EOutOfMemory do begin
      Failures := OomFailures;
      Reserved := OomReserved;
      Released := OomReleasedReservations;
      OomArm(0);
      Failed := True;
      Require(not NilMode and not SuccessCase, 'unexpected EOutOfMemory');
    end;
    on E: Exception do begin
      OomArm(0);
      WriteLn('INJECTED_FAIL exception=', E.ClassName);
      Halt(1);
    end;
  end;
  ReturnNilIfGrowHeapFails := False;
  If (Name <> 'overflow-get') and (Name <> 'overflow-realloc') and (Name <> 'inplace') then
    Require(Failures > 0, 'target operation did not hit injected failure');
  If OldSize <> 0 then begin
    If SuccessCase then begin
      Require(P = Returned, 'successful realloc result differs');
      CheckOldData(P, OldSize);
    end else begin
      Require(P = OldP, 'failed realloc changed var pointer');
      Require(MemSize(P) = OldCapacity, 'failed realloc changed capacity');
      CheckOldData(P, OldSize);
      If WasLarge then Require(OomLargeLinked(P), 'failed realloc lost large-list membership');
    end;
  end;
  {$ifdef MSWINDOWS}
  If (Name = 'commit-fail') or (Name = 'commit-fallback') then begin
    Require(Reserved = NextRegion, 'did not exercise successful reserve before failed commit');
    Require(Released = 1, 'failed commit did not release reservation');
    If Name = 'commit-fail' then begin
      Require(Windows.VirtualQuery(NextRegion, Info, SizeOf(Info)) <> 0, 'rollback query');
      Require(Info.State = MEM_FREE, 'failed commit leaked reserved region');
    end;
  end;
  If Name = 'inplace' then Require(P = OldP, 'in-place path not reached');
  {$endif}
  Require(CurrentHeapFragmentationStatus.Errors = 0, 'heap topology after failure');
  If P <> nil then FreeMem(P);
  for J := 0 to HeldCount - 1 do FreeMem(Held[J]);
  Require(CurrentHeapFragmentationStatus.Errors = 0, 'heap topology after cleanup');
  WriteLn('INJECTED_PASS case=', Name, ' nil=', Ord(NilMode), ' failures=', Failures,
    ' held=', HeldCount, ' raised=', Ord(Failed));
end.
