program safecall_assembler;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$asmmode intel}{$ENDIF}
{ A safecall routine written in assembler is wrapped like any safecall
  routine, as Delphi 12.2 does on Win64: the body runs inside the implicit
  frame, an exception in it becomes an HRESULT that the caller raises, and
  the routine returns the HRESULT of the wrapper (S_OK on a normal exit) -
  the value the body leaves in EAX is not the result.  The result of a
  safecall function is the hidden last parameter.  The compiler used to stop
  on such a routine on Win64 and to refuse the Delphi form on Linux. }
uses
  SysUtils;

var
  Failures: Integer;

procedure SafeOk; safecall; assembler;
asm
  xor eax, eax
end;

{ E_FAIL in EAX is no failure: the wrapper returns S_OK }
procedure SafeEaxIgnored; safecall; assembler;
asm
  mov eax, $80004005
end;

{ the only parameter is the hidden result: RCX on Win64, RDI on Linux }
function SafeAnswer: Integer; safecall; assembler;
asm
{$IFDEF MSWINDOWS}
  mov dword ptr [rcx], 42
{$ELSE}
  mov dword ptr [rdi], 42
{$ENDIF}
end;

{ an access violation inside the body }
procedure SafeFaults; safecall; assembler;
asm
  xor ecx, ecx
  mov eax, dword ptr [rcx]
end;

{ Delphi also permits an asm body without an explicit assembler directive.
  The compiler must keep its safecall frame around that body. }
procedure SafeImplicitFault; safecall;
asm
  xor ecx, ecx
  mov eax, dword ptr [rcx]
end;

procedure SafePascalFails; safecall;
begin
  raise Exception.Create('pascal');
end;

type
  TSafeProc = procedure; safecall;

procedure Check(const Name: string; Condition: Boolean);
begin
  If not Condition then begin
    WriteLn('FAIL ', Name);
    Inc(Failures);
  end;
end;

function Raises(P: TSafeProc): string;
begin
  Result := '';
  try
    P();
  except
    on E: Exception do
      Result := E.ClassName;
  end;
end;

var
  Direct: string;
  P: TSafeProc;
begin
  Failures := 0;
  SafeOk;
  Check('ok', True);
  Direct := '';
  try
    SafeEaxIgnored;
  except
    on E: Exception do
      Direct := E.ClassName;
  end;
  Check('eax-ignored-direct', Direct = '');
  Check('eax-ignored-indirect', Raises(@SafeEaxIgnored) = '');
  Check('answer', SafeAnswer = 42);
  Direct := '';
  try
    SafeFaults;
  except
    on E: Exception do
      Direct := E.ClassName;
  end;
  Check('fault-direct ' + Direct, Direct = 'ESafecallException');
  Check('fault-indirect', Raises(@SafeFaults) = 'ESafecallException');
  Check('implicit-asm-fault', Raises(@SafeImplicitFault) = 'ESafecallException');
  Check('pascal', Raises(@SafePascalFails) = 'ESafecallException');
  P := SafeOk;
  Check('ok-indirect', Raises(P) = '');
  If Failures = 0 then
    WriteLn('SAFECALL_ASSEMBLER_OK')
  else begin
    WriteLn('SAFECALL_ASSEMBLER_FAILED ', Failures);
    Halt(1);
  end;
end.
