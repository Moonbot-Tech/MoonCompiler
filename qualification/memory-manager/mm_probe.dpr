program mm_probe;

{ Probe program of the memory-manager gates (mm_layout_gate.py and
  mm_profile_matrix.py): it names the MM unit itself, so it links the bundled
  allocator under a vanilla runtime with any FPCMM_* profile as well as under
  the product pin, and it exercises GetMem/ReallocMem/FreeMem on every small
  class and on medium and large sizes as a smoke test.  The layout gate reads
  the MM routines out of its executable. }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  SysUtils;

var
  P: array[0..255] of Pointer;
  I, J, Round: Integer;
  S: RawByteString;
  Sum: UInt64;
begin
  Sum := 0;
  for Round := 1 to 200 do begin
    for I := 0 to 255 do
      GetMem(P[I], (I mod 40) * 16 + 1 + (Round and 7));
    for I := 0 to 255 do
      PByte(P[I])^ := Byte(I);
    for I := 0 to 255 do
      ReallocMem(P[I], (I mod 40) * 32 + 9);
    for I := 0 to 255 do
      Inc(Sum, PByte(P[I])^);
    for I := 255 downto 0 do
      FreeMem(P[I]);
    GetMem(P[0], 40000 + Round);
    GetMem(P[1], 3000000);
    ReallocMem(P[0], 50000);
    FreeMem(P[1]);
    FreeMem(P[0]);
  end;
  S := '';
  for J := 1 to 3000 do
    S := S + 'x';
  Inc(Sum, Length(S));
  If Sum <> 200 * 32640 + 3000 then begin
    WriteLn('MMPROBE_FAIL ', Sum);
    Halt(1);
  end;
  WriteLn('MMPROBE_OK');
end.
