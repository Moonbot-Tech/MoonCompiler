program mov_storeback_semantic;

{ "mov mem,%reg; mov %reg,mem" stores back the value just loaded, so the
  x86 peephole (MovMov2Mov 1) drops the second MOV, and the first one too
  when %reg is dead (Mov2Nop 6). Two red forms:

  Syslog is shaped after mORMot 2 SyslogMessage: at O3 spill coalescing
  gives Start the stack slot of the parameter Dest, and the copy
  "Start := Dest" became a load of Dest and its store back into that slot
  (Linux: "movq 16(%rbp),%rdx; movq %rdx,16(%rbp)"). The liveness of the
  register was asked at the load itself, which writes it, so the load went
  as well and Dest^ := '<' wrote through what the register held before:
  the source text here. The four K values keep the register pressure that
  produces the shape on both ABIs.

  Chase: "mov (%reg),%reg; mov %reg,(%reg)" stores through the new
  pointer, not back where it was read from; O2 and O3 lost the store. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  PRawByteString = ^RawByteString;
  TStamp = record
    Year, Month, DayOfWeek, Day, Hour, Minute, Second, MilliSecond: Word;
  end;

var
  Fails: Integer = 0;
  Host, AppName: RawByteString;
  Cells: array[0..7] of PtrInt;

procedure Check(Ok: Boolean; const Name: string);
begin
  if not Ok then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

function PutNumber(P: PAnsiChar; V: PtrUInt): PAnsiChar; noinline;
begin
  repeat
    P^ := AnsiChar(Ord('0') + V mod 10);
    Inc(P);
    V := V div 10;
  until V = 0;
  Result := P;
end;

procedure GetStamp(out T: TStamp; Local: Boolean; Tix: Int64 = 0); noinline;
begin
  FillChar(T, SizeOf(T), 0);
  T.Year := 2026;
end;

function PutDate(P: PAnsiChar; Expanded: Boolean; Y, M, D: PtrUInt): PAnsiChar; noinline;
begin
  Result := PutNumber(P, Y);
end;

function PutTime(P: PAnsiChar; Expanded: Boolean; H, M, S, MS: PtrUInt;
  First: AnsiChar = 'T'; WithMS: Boolean = False): PAnsiChar; noinline;
begin
  P^ := First;
  Result := P + 1;
end;

function IsAscii(P: PAnsiChar; Len: PtrUInt): Boolean; noinline;
begin
  Result := True;
end;

function PutText(P: PAnsiChar; const Text: RawByteString): PAnsiChar; noinline;
begin
  P^ := ' ';
  Inc(P);
  Move(Pointer(Text)^, P^, Length(Text));
  Result := P + Length(Text);
end;

procedure TrimText(var P: PAnsiChar; var Len: PtrInt; TrimDate: Boolean;
  MaxLen: PtrInt); noinline;
begin
  while (Len > 0) and (P^ <= ' ') do
  begin
    Inc(P);
    Dec(Len);
  end;
  while (Len > 0) and (P[Len - 1] <= ' ') do
    Dec(Len);
  if Len > MaxLen then
    Len := MaxLen;
end;

function Syslog(Facility, Severity: Byte; P: PAnsiChar; Len: PtrInt;
  const ProcId, MsgId: RawByteString; Dest: PAnsiChar; DestSize: PtrInt;
  TrimDate: Boolean; const Name: RawByteString = ''): PtrInt; noinline;
var
  Start: PAnsiChar;
  N: PRawByteString;
  T: TStamp;
  K0, K1, K2, K3: PtrInt;
begin
  Result := 0;
  if DestSize < 127 then
    Exit;
  Start := Dest;
  K0 := Len * 3 + Ord(P[0]);
  K1 := Len * 4 + Ord(P[1]);
  K2 := Len * 5 + Ord(P[2]);
  K3 := Len * 6 + Ord(P[3]);
  Dest^ := '<';
  Dest := PutNumber(Dest + 1, Severity + Facility shl 3);
  PInteger(Dest)^ := Ord('>') + Ord('1') shl 8 + Ord(' ') shl 16;
  Inc(Dest, 3);
  GetStamp(T, False);
  PutDate(Dest, True, T.Year, T.Month, T.Day);
  PutTime(Dest + 10, True, T.Hour, T.Minute, T.Second, T.MilliSecond, 'T', True);
  Dest[23] := 'Z';
  Inc(Dest, 24);
  if Name <> '' then
    N := @Name
  else
    N := @AppName;
  if Length(Host) + Length(N^) + Length(ProcId) + Length(MsgId) +
     (Dest - Start) + 15 > DestSize then
    Exit;
  Dest := PutText(Dest, Host);
  Dest := PutText(Dest, N^);
  Dest := PutText(Dest, ProcId);
  Dest := PutText(Dest, MsgId);
  Dest := PutText(Dest, '');
  Dest^ := ' ';
  Inc(Dest);
  TrimText(P, Len, TrimDate, DestSize - (Dest - Start) - 3);
  if Len < 2 then
    Exit;
  if not IsAscii(P, Len) then
  begin
    PInteger(Dest)^ := $bfbbef;
    Inc(Dest, 3);
  end;
  Move(P^, Dest^, Len);
  Dest[Len] := #0;
  Result := (Dest - Start) + Len + K0 + K1 + K2 + K3;
end;

procedure Chase(Q: PPtrInt; Count: PtrInt); noinline;
var
  I: PtrInt;
begin
  for I := 1 to Count do
  begin
    Q := PPtrInt(Q^);
    Q^ := PtrInt(Q);
  end;
end;

var
  Source: array[0..2047] of AnsiChar;
  Buffer: array[0..2047] of AnsiChar;
begin
  Host := 'host';
  AppName := 'app';
  FillChar(Source, SizeOf(Source), 0);
  Move(PAnsiChar(' test ')^, Source, 6);
  FillChar(Buffer, SizeOf(Buffer), 1);
  Syslog(4, 2, @Source, 6, '', '', @Buffer, SizeOf(Buffer), False);
  Check(Source[0] = ' ', 'syslog source kept');
  Check((Buffer[0] = '<') and (Buffer[3] = '>'), 'syslog destination written');

  Cells[0] := PtrInt(@Cells[2]);
  Cells[2] := PtrInt(@Cells[5]);
  Chase(@Cells[0], 1);
  Check(Cells[2] = PtrInt(@Cells[2]), 'chase store through the new pointer');

  if Fails <> 0 then
    Halt(1);
  WriteLn('MOV_STOREBACK_PASS');
end.
