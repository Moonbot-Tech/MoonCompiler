function GuardMap: PByte;
{$ifdef MSWINDOWS}
var OldProtect: DWORD;
{$endif}
begin
  {$ifdef MSWINDOWS}
  Result := VirtualAlloc(nil,3*4096,MEM_RESERVE or MEM_COMMIT,PAGE_NOACCESS);
  Require(Result<>nil,'text guard allocation');
  Require(VirtualProtect(Result+4096,4096,PAGE_READWRITE,OldProtect),'text guard middle page');
  {$else}
  Result := fpMMap(nil,3*4096,PROT_NONE,MAP_PRIVATE or MAP_ANONYMOUS,-1,0);
  Require(Result<>Pointer(-1),'text guard allocation');
  Require(fpMProtect(Result+4096,4096,PROT_READ or PROT_WRITE)=0,'text guard middle page');
  {$endif}
end;
procedure ReleaseGuardMap(P: PByte);
begin
  {$ifdef MSWINDOWS}
  Require(VirtualFree(P,0,MEM_RELEASE),'text guard release');
  {$else}
  Require(fpMUnmap(P,3*4096)=0,'text guard release');
  {$endif}
end;
procedure GuardCompare;
const
  Counts: array[0..18] of Integer = (0,1,2,7,8,9,15,16,17,31,32,33,63,64,65,127,128,129,256);
var
  MapA, MapB, PA, PB: PByte;
  A, B: UnicodeString;
  N, LengthB, Mode, I, Position, Test: Integer;
begin
  MapA := GuardMap;
  MapB := GuardMap;
  try
    for N in Counts do
      for LengthB := N to N+1 do begin
        PA := MapA+2*4096-N*2;
        PB := MapB+2*4096-LengthB*2;
        FillChar((PA-24)^,24,0);
        FillChar((PB-24)^,24,0);
        PSizeInt(PA-16)^ := -1;
        PSizeInt(PB-16)^ := -1;
        PSizeInt(PA-8)^ := N;
        PSizeInt(PB-8)^ := LengthB;
        Pointer(A) := PA;
        Pointer(B) := PB;
        for Mode := 0 to 2 do begin
          for I := 0 to N-1 do PWord(PA+I*2)^ := Ord('a')+(I mod 26);
          for I := 0 to LengthB-1 do PWord(PB+I*2)^ := Ord('a')+(I mod 26);
          If Mode=1 then
            for I := 0 to LengthB-1 do PWord(PB+I*2)^ := Ord('A')+(I mod 26);
          If Mode=2 then begin
            for I := 0 to N-1 do PWord(PA+I*2)^ := $8000+I;
            for I := 0 to LengthB-1 do PWord(PB+I*2)^ := $8000+I;
          end;
          Require(CompareSign(SysUtils.CompareText(A,B))=ReferenceCompare(A,B),'guard equal/fold/length');
          Require(CompareSign(SysUtils.CompareText(B,A))=ReferenceCompare(B,A),'guard reverse length');
          Require(SysUtils.CompareText(A,A)=0,'guard identity');
          If N=0 then Continue;
          for Test := 0 to 2 do begin
            case Test of
              0: Position := 0;
              1: Position := N div 2;
              else Position := N-1;
            end;
            PWord(PB+Position*2)^ := $ffff;
            Require(CompareSign(SysUtils.CompareText(A,B))=ReferenceCompare(A,B),'guard first differing UTF16');
            Require(CompareSign(SysUtils.CompareText(B,A))=ReferenceCompare(B,A),'guard reverse difference');
            PWord(PB+Position*2)^ := PWord(PA+Position*2)^;
          end;
        end;
        Pointer(A) := nil;
        Pointer(B) := nil;
      end;
  finally
    Pointer(A) := nil;
    Pointer(B) := nil;
    ReleaseGuardMap(MapB);
    ReleaseGuardMap(MapA);
  end;

end;
