program build_smoke;

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  System.SysUtils,
  System.Generics.Collections;

var
  Buffer: Pointer;
  Values: TList<Integer>;
  Text: String;

function StringKind(const Value: AnsiString): Integer; overload;
begin
  Result := 1;
end;

function StringKind(const Value: UnicodeString): Integer; overload;
begin
  Result := 2;
end;

function IntelAsmIdentity(Value: PtrUInt): PtrUInt;
asm
  {$ifdef MSWINDOWS}
  mov rax, rcx
  {$else}
  mov rax, rdi
  {$endif MSWINDOWS}
end;

begin
  Text := 'Unicode';
  If StringKind(Text) <> 2 then
    Halt(3);
  Values := TList<Integer>.Create;
  try
    Values.Add(42);
    If Values[0] <> 42 then
      Halt(4);
  finally
    Values.Free;
  end;
  If IntelAsmIdentity($123456789ABCDEF0) <> $123456789ABCDEF0 then
    Halt(2);
  GetMem(Buffer, 256);
  try
    FillChar(Buffer^, 256, $A5);
    If PByte(Buffer)[0] <> $A5 then
      Halt(1);
  finally
    FreeMem(Buffer);
  end;
  Writeln('MOONBOT_BUILD_OK');
end.
