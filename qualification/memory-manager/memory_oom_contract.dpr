program memory_oom_contract;

{$mode delphi}
{$H+}

uses
  mormot.core.fpcx64mm,
  SysUtils;

procedure Require(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
  begin
    WriteLn('MEMORY_OOM_CONTRACT_FAIL ', MessageText);
    Halt(1);
  end;
end;

procedure RequireOutOfMemory(const Name: string; Proc: TProcedure);
begin
  try
    Proc;
    Require(False, Name + ' returned');
  except
    on E: EOutOfMemory do
      Exit;
    on E: Exception do
      Require(False, Name + ' raised ' + E.ClassName);
  end;
end;

const
  Huge = PtrUInt(1) shl 60;

var
  A, AAlias: RawByteString;
  U, UAlias: UnicodeString;
  P, OldP, Returned: Pointer;

procedure FailGetMem;
begin
  P := GetMem(Huge);
end;

procedure FailAllocMem;
begin
  P := AllocMem(Huge);
end;

procedure FailReallocSmall;
begin
  Returned := ReallocMem(P, Huge);
end;

procedure FailReallocNil;
begin
  Returned := ReallocMem(P, Huge);
end;

procedure FailReallocLarge;
begin
  Returned := ReallocMem(P, Huge);
end;

procedure FailUnicodeEmpty;
begin
  U := '';
  SetLength(U, Huge div SizeOf(UnicodeChar));
end;

procedure FailUnicodeUnique;
begin
  U := 'preserved';
  SetLength(U, Huge div SizeOf(UnicodeChar));
end;

procedure FailUnicodeShared;
begin
  U := 'preserved';
  UAlias := U;
  SetLength(U, Huge div SizeOf(UnicodeChar));
end;

procedure FailAnsiEmpty;
begin
  A := '';
  SetLength(A, Huge);
end;

procedure FailAnsiUnique;
begin
  A := 'preserved';
  SetLength(A, Huge);
end;

procedure FailAnsiShared;
begin
  A := 'preserved';
  AAlias := A;
  SetLength(A, Huge);
end;

begin
  ReturnNilIfGrowHeapFails := False;
  P := nil;
  RequireOutOfMemory('GetMem', @FailGetMem);
  Require(P = nil, 'GetMem changed destination');
  RequireOutOfMemory('AllocMem', @FailAllocMem);
  Require(P = nil, 'AllocMem changed destination');
  RequireOutOfMemory('Realloc nil', @FailReallocNil);
  Require((P = nil) and (Returned = nil), 'Realloc nil changed destination');

  P := GetMem(64);
  OldP := P;
  PByte(P)^ := $5A;
  Returned := P;
  RequireOutOfMemory('Realloc small', @FailReallocSmall);
  Require(P = OldP, 'small realloc lost old pointer');
  Require(PByte(P)^ = $5A, 'small realloc changed old data');
  FreeMem(P);

  P := GetMem(2 shl 20);
  OldP := P;
  PByte(P)^ := $A5;
  Returned := P;
  RequireOutOfMemory('Realloc large', @FailReallocLarge);
  Require(P = OldP, 'large realloc lost old pointer');
  Require(PByte(P)^ = $A5, 'large realloc changed old data');
  FreeMem(P);

  RequireOutOfMemory('Unicode empty', @FailUnicodeEmpty);
  Require(U = '', 'Unicode empty changed');
  RequireOutOfMemory('Unicode unique', @FailUnicodeUnique);
  Require(U = 'preserved', 'Unicode unique changed');
  RequireOutOfMemory('Unicode shared', @FailUnicodeShared);
  Require((U = 'preserved') and (UAlias = 'preserved'),
    'Unicode shared changed');
  RequireOutOfMemory('Ansi empty', @FailAnsiEmpty);
  Require(A = '', 'Ansi empty changed');
  RequireOutOfMemory('Ansi unique', @FailAnsiUnique);
  Require(A = 'preserved', 'Ansi unique changed');
  RequireOutOfMemory('Ansi shared', @FailAnsiShared);
  Require((A = 'preserved') and (AAlias = 'preserved'),
    'Ansi shared changed');

  ReturnNilIfGrowHeapFails := True;
  try
    P := GetMem(Huge);
    Require(P = nil, 'ReturnNil GetMem did not return nil');
    P := GetMem(64);
    OldP := P;
    PByte(P)^ := $3C;
    Returned := ReallocMem(P, Huge);
    Require(Returned = nil, 'ReturnNil realloc did not return nil');
    Require(P = OldP, 'ReturnNil realloc lost old pointer');
    Require(PByte(P)^ = $3C, 'ReturnNil realloc changed old data');
    FreeMem(P);
  finally
    ReturnNilIfGrowHeapFails := False;
  end;

  WriteLn('MEMORY_OOM_CONTRACT_PASS');
end.
