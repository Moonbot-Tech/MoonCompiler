"""Hooks inserted only into a private MM copy by mm_failure_gate.py."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402

DECL = '''
procedure OomArm(Mask: Cardinal);
function OomFailures: Cardinal;
function OomReserved: Pointer;
function OomReleasedReservations: Cardinal;
procedure OomPrefer(Address: Pointer);
function OomLargeLinked(P: Pointer): Boolean;
function OomLargeMapping(P: Pointer): PtrUInt;
'''
GLOBALS = '''
var
  OomMask, OomFailureCount, OomReleaseCount: Cardinal;
  OomLastReserve, OomPreferred: Pointer;
procedure OomArm(Mask: Cardinal);
begin OomMask := Mask; OomFailureCount := 0; OomLastReserve := nil; OomReleaseCount := 0; end;
function OomFailures: Cardinal;
begin Result := OomFailureCount; end;
function OomReserved: Pointer;
begin Result := OomLastReserve; end;
function OomReleasedReservations: Cardinal;
begin Result := OomReleaseCount; end;
procedure OomPrefer(Address: Pointer);
begin OomPreferred := Address; end;
'''
WIN = '''
function VirtualAlloc(lpAddress: pointer;
   dwSize: PtrUInt; flAllocationType, flProtect: cardinal): pointer; stdcall;
var Kind: Cardinal;
begin
  If lpAddress = nil then Kind := 1
  else If flAllocationType = MEM_RESERVE then Kind := 2 else Kind := 4;
  If (OomMask and Kind) <> 0 then begin
    Inc(OomFailureCount);
    Exit(nil);
  end;
  If (lpAddress = nil) and (OomPreferred <> nil) then begin
    lpAddress := OomPreferred;
    OomPreferred := nil;
    flAllocationType := flAllocationType or MEM_RESERVE;
  end;
  Result := NativeVirtualAlloc(lpAddress, dwSize, flAllocationType, flProtect);
  If (Kind = 2) and (Result <> nil) then OomLastReserve := Result;
end;
'''
WIN_FREE = '''
function VirtualFree(lpAddress: pointer; dwSize: PtrUInt; dwFreeType: cardinal): LongBool; stdcall;
begin
  Result := NativeVirtualFree(lpAddress, dwSize, dwFreeType);
  If Result and (lpAddress = OomLastReserve) and (dwFreeType = MEM_RELEASE) then Inc(OomReleaseCount);
end;
'''
LARGE = '''
function OomLargeLinked(P: Pointer): Boolean;
var H, N: PLargeBlockHeader; I: Integer;
begin
  H := Pointer(PByte(P) - LargeBlockHeaderSize);
  Result := False;
  LockLargeBlocks;
  N := LargeBlocksCircularList.NextLargeBlockHeader;
  I := 0;
  while N <> @LargeBlocksCircularList do begin
    If (N^.NextLargeBlockHeader^.PreviousLargeBlockHeader <> N) or
      (N^.PreviousLargeBlockHeader^.NextLargeBlockHeader <> N) then Break;
    If N = H then Result := True;
    N := N^.NextLargeBlockHeader;
    Inc(I);
    If I > 10000 then begin Result := False; Break; end;
  end;
  LargeBlocksLocked := False;
end;
function OomLargeMapping(P: Pointer): PtrUInt;
begin
  Result := PLargeBlockHeader(PByte(P) - LargeBlockHeaderSize)^.BlockSizeAndFlags and DropMediumAndLargeFlagsMask;
end;
'''

def faults(source):
    source = source.replace('\nimplementation\n', DECL + '\nimplementation\n', 1)
    # implementation uses must remain the first declaration; put variables after
    # the platform uses in each conditional branch.
    anchor = "function VirtualAlloc(lpAddress: pointer;\n   dwSize: PtrUInt; flAllocationType, flProtect: cardinal): pointer;\n  stdcall; external kernel32 name 'VirtualAlloc';"
    assert source.count(anchor) == 1
    source = source.replace(anchor, GLOBALS + anchor.replace('function VirtualAlloc(', 'function NativeVirtualAlloc(') + WIN)
    anchor = "function VirtualFree(lpAddress: pointer; dwSize: PtrUInt;\n   dwFreeType: cardinal): LongBool;\n  stdcall; external kernel32 name 'VirtualFree';"
    assert source.count(anchor) == 1
    source = source.replace(anchor, anchor.replace('function VirtualFree(', 'function NativeVirtualFree(') + WIN_FREE)
    anchor = 'function OsAllocMediumRaw(Size: PtrInt): pointer;\nbegin\n'
    assert source.count(anchor) == 1
    source = source.replace(anchor, GLOBALS + anchor + '  If (OomMask and 1) <> 0 then begin Inc(OomFailureCount); Exit(nil); end;\n')
    anchor = 'function OsAllocLarge(Size: PtrInt): pointer; inline;\nbegin\n  result := fpmmap'
    assert source.count(anchor) == 1
    source = source.replace(anchor, 'function OsAllocLarge(Size: PtrInt): pointer; inline;\nbegin\n  If (OomMask and 1) <> 0 then begin Inc(OomFailureCount); Exit(nil); end;\n  result := fpmmap')
    anchor = '  result := pointer(do_syscall(syscall_nr_mremap, TSysParam(addr),\n    TSysParam(old_len), TSysParam(new_len), TSysParam(MREMAP_MAYMOVE)));'
    assert source.count(anchor) == 1
    source = source.replace(anchor, '  If (OomMask and 8) <> 0 then begin Inc(OomFailureCount); result := MAP_FAILED; end\n  else\n  ' + anchor.lstrip())
    at = source.index('{$ifndef FPCMM_STANDALONE}\n\nconst\n  NewMM:')
    source = source[:at] + LARGE + source[at:]
    return source

OWNER_DECL='''
type TOomMediumReturnObserver = procedure(LockByte: PByte);
procedure OomSetMediumReturnObserver(Observer: TOomMediumReturnObserver);
'''
OWNER_IMPL='''var OomMediumReturnObserver: TOomMediumReturnObserver;
procedure OomSetMediumReturnObserver(Observer: TOomMediumReturnObserver);
begin OomMediumReturnObserver:=Observer; end;

'''
def ownership(s):
    s=faults(s)
    s=s.replace('\nimplementation\n',OWNER_DECL+'\nimplementation\n',1)
    a=s.index('function AllocNewMediumPoolOrFail(');b=s.index('{$endif MSWINDOWS}',a)
    part=s[a:b]
    # The selected helper has a direct nil-mode return. Observe that boundary,
    # not merely the syntactic end of a function bypassed by Exit.
    nil_exit = '  if ReturnNilIfGrowHeapFails then\n    exit;'
    if nil_exit in part:
        part=part.replace(nil_exit, '''  if ReturnNilIfGrowHeapFails then
  begin
    if assigned(OomMediumReturnObserver) then
      OomMediumReturnObserver(@Info.Locked);
    exit;
  end;''', 1)
    i=part.rindex('end;')
    part=part[:i]+'''  if assigned(OomMediumReturnObserver) then
    OomMediumReturnObserver(@Info.Locked);
'''+part[i:]
    return s[:a]+OWNER_IMPL+part+s[b:]


def pending(source):
    declarations = '\nprocedure PolicyArm(P: Pointer);\nfunction PolicyStage: LongInt;\nprocedure PolicyRelease;\n'
    assert source.count('\nimplementation\n') == 1
    source = source.replace('\nimplementation\n', declarations + '\nimplementation\n', 1)
    # This implementation point is outside platform conditionals in both the
    # original and the handoff versions. No production hot telemetry is added.
    at = source.index('function _FreeMemSlow(P: pointer): PtrUInt;')
    globals = '''var
  PolicyTarget: Pointer;
  PolicyCurrentStage: LongInt;
procedure PolicyArm(P: Pointer);
begin PolicyTarget := P; PolicyCurrentStage := 0; end;
function PolicyStage: LongInt;
begin Result := PolicyCurrentStage; end;
procedure PolicyRelease;
begin PolicyCurrentStage := 2; end;

'''
    source = source[:at] + globals + source[at:]
    # The barrier lands between _FreeMem's `jne @Deferred` and its target, a
    # jump the MM writes out as rel8 bytes; bytes keep their displacement across
    # the insertion, so this copy takes the written-out jumps back as mnemonics.
    source, _, problems = code_placement.written_jumps(source, 'mormot.core.fpcx64mm.pas')
    assert not problems, problems
    at = source.index('@UnlockSlow:\n', source.index('// The usual small-block release'))
    barrier = '''@UnlockSlow:
        cmp     rcx, [rip + PolicyTarget]
        jne     @PolicyDone
        cmp     dword ptr [rip + PolicyCurrentStage], 0
        jne     @PolicyDone
        mov     dword ptr [rip + PolicyCurrentStage], 1
@PolicyWait:
        pause
        cmp     dword ptr [rip + PolicyCurrentStage], 2
        jne     @PolicyWait
@PolicyDone:
'''
    return source[:at] + barrier + source[at+len('@UnlockSlow:\n'):]
